import Foundation

/// A validated prefix of one table read. Partial entries are not a replacement for the
/// node's last complete table, and must not be used to infer that other links were removed.
public struct NodeLinkingTableProgress: Equatable, Sendable {
    public let entries: [NodeLinkingTableEntry]
    public let pagesReceived: Int
    public let totalPages: Int
    public let totalCount: Int
    public var isComplete: Bool { pagesReceived == totalPages }

    public init(entries: [NodeLinkingTableEntry], pagesReceived: Int, totalPages: Int, totalCount: Int) {
        self.entries = entries
        self.pagesReceived = pagesReceived
        self.totalPages = totalPages
        self.totalCount = totalCount
    }
}

public typealias NodeLinkingTableProgressHandler = @MainActor @Sendable (NodeLinkingTableProgress) -> Void

struct LinkingTablePage: Sendable {
    let page: UInt8
    let totalPages: UInt8
    let totalCount: UInt8
    let entries: [NodeLinkingTableEntry]
}

/// The only state read outside the main actor. Every access is protected by this lock.
private final class LinkingTableCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

/// Safe to cancel from any thread. The flag invalidates queued callbacks immediately;
/// cleanup and client callbacks are then performed on the main actor.
final class LinkingTableReadHandle: CommandHandle, Sendable {
    private let cancellation: LinkingTableCancellation
    private let cancelAction: @Sendable () -> Void

    fileprivate init(cancellation: LinkingTableCancellation, cancelAction: @escaping @Sendable () -> Void) {
        self.cancellation = cancellation
        self.cancelAction = cancelAction
    }

    func cancel() {
        cancellation.cancel()
        cancelAction()
    }
}

@MainActor
final class LinkingTableReadOperation {
    struct PendingPage {
        let requestID: UInt32
        let command: CommandHandle
    }

    let id: UUID
    private let sendPage: @MainActor (UInt8, @escaping @Sendable (CommandResult) -> Void) -> PendingPage
    private let takePage: @MainActor (UInt32) -> LinkingTablePage?
    private let discardPage: @MainActor (UInt32) -> Void
    private let isCurrent: @MainActor () -> Bool
    private let publishComplete: @MainActor ([NodeLinkingTableEntry]) -> Void
    private let progressHandler: NodeLinkingTableProgressHandler?
    private let completionHandler: @MainActor (CommandResult) -> Void
    private let didFinish: @MainActor () -> Void
    private let cancellation = LinkingTableCancellation()
    private var pendingPage: PendingPage?
    private var pageGeneration: UUID?
    private var entries: [NodeLinkingTableEntry] = []
    private var totalPages: UInt8?
    private var totalCount: UInt8?
    private var finished = false

    init(id: UUID = UUID(),
         sendPage: @escaping @MainActor (UInt8, @escaping @Sendable (CommandResult) -> Void) -> PendingPage,
         takePage: @escaping @MainActor (UInt32) -> LinkingTablePage?,
         discardPage: @escaping @MainActor (UInt32) -> Void,
         isCurrent: @escaping @MainActor () -> Bool,
         publishComplete: @escaping @MainActor ([NodeLinkingTableEntry]) -> Void,
         progressHandler: NodeLinkingTableProgressHandler?,
         didFinish: @escaping @MainActor () -> Void,
         completionHandler: @escaping @MainActor (CommandResult) -> Void) {
        self.id = id
        self.sendPage = sendPage
        self.takePage = takePage
        self.discardPage = discardPage
        self.isCurrent = isCurrent
        self.publishComplete = publishComplete
        self.progressHandler = progressHandler
        self.didFinish = didFinish
        self.completionHandler = completionHandler
    }

    func start() -> LinkingTableReadHandle {
        let handle = LinkingTableReadHandle(cancellation: cancellation) { [weak self] in
            Task { @MainActor [weak self] in self?.cancel() }
        }
        fetchPage(0)
        return handle
    }

    func cancel() {
        cancellation.cancel()
        finish(.cancelled)
    }

    private func fetchPage(_ page: UInt8) {
        guard !finished else { return }
        guard !cancellation.isCancelled, isCurrent() else { finish(.cancelled); return }
        let generation = UUID()
        pageGeneration = generation
        let pending = sendPage(page) { [weak self] result in
            Task { @MainActor [weak self] in
                self?.receive(result, page: page, generation: generation)
            }
        }
        guard !finished, !cancellation.isCancelled, isCurrent() else {
            discardPage(pending.requestID)
            pending.command.cancel()
            finish(.cancelled)
            return
        }
        pendingPage = pending
    }

    private func receive(_ result: CommandResult, page: UInt8, generation: UUID) {
        guard !finished, pageGeneration == generation else { return }
        guard !cancellation.isCancelled, isCurrent() else { finish(.cancelled); return }
        guard let pending = pendingPage else { finish(.failure); return }
        guard result == .success else { finish(result); return }
        pendingPage = nil
        pageGeneration = nil
        guard let response = takePage(pending.requestID), response.page == page else {
            finish(.failure)
            return
        }
        if page == 0 {
            totalPages = response.totalPages
            totalCount = response.totalCount
        }
        guard response.totalPages == totalPages, response.totalCount == totalCount,
              response.entries.count <= 4 else { finish(.failure); return }
        let emptyTable = response.totalPages == 0 && page == 0 && response.totalCount == 0 && response.entries.isEmpty
        guard emptyTable || page < response.totalPages else { finish(.failure); return }
        let nextEntries = entries + response.entries
        guard nextEntries.count <= Int(response.totalCount) else { finish(.failure); return }
        let complete = emptyTable || Int(page) + 1 == Int(response.totalPages)
        guard !complete || nextEntries.count == Int(response.totalCount) else { finish(.failure); return }
        entries = nextEntries
        if complete { publishComplete(entries) }
        guard !finished, !cancellation.isCancelled, isCurrent() else { finish(.cancelled); return }
        progressHandler?(.init(entries: entries, pagesReceived: emptyTable ? 0 : Int(page) + 1,
                               totalPages: Int(response.totalPages), totalCount: Int(response.totalCount)))
        guard !finished, !cancellation.isCancelled, isCurrent() else { finish(.cancelled); return }
        if complete { finish(.success) } else { fetchPage(page + 1) }
    }

    private func finish(_ result: CommandResult) {
        guard !finished else { return }
        finished = true
        pageGeneration = nil
        let pending = pendingPage
        pendingPage = nil
        if let pending {
            discardPage(pending.requestID)
            pending.command.cancel()
        }
        didFinish()
        completionHandler(result)
    }
}

final class EmptyLinkingTableCommandHandle: CommandHandle {
    func cancel() {}
}
