//  CommandCoordinator.swift

/*--
MIT License

Copyright (c) 2021 Combustion Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
--*/

import Foundation

@available(*, deprecated, renamed: "CommandCoordinator")
public typealias MessageHandlers = CommandCoordinator

/// A request that can be completed by observing a matching device status update
/// instead of waiting for only the command response packet.
protocol DeviceStatusConfirmingRequest {
    var confirmationSerialNumber: String { get }
    func isConfirmed(by status: DeviceStatus) -> Bool
}

private typealias CommandCompletionAction = (completion: CommandCompletionHandler, result: CommandResult)

/// Identifies a single transport attempt for a command response.
///
/// Routed commands can be retried over different transports. Each send returns
/// the response keys that should complete the command if a direct or
/// node response arrives later.
enum CommandAttemptKey: Hashable {
    case direct(messageType: MessageType, identifier: String)
    case node(messageType: NodeMessageType, requestId: UInt32)
}

/// Coordinates BLE command lifetimes, retries, cancellation, and completion.
///
/// `CommandCoordinator` tracks commands after their write has been requested
/// and completes them when one of three signals arrives:
/// - a direct probe command response,
/// - a MeatNet node command response,
/// - or a device status update that confirms the requested state was applied.
///
/// The coordinator does not choose routes or perform BLE writes directly.
/// Callers provide send closures so `DeviceManager` can decide whether a send
/// should go direct to the probe or through a connected node based on the
/// current connection graph. Node command handlers represent one fixed MeatNet
/// transport. Routed command handlers represent one probe command that
/// may switch transports on retry while sharing the original timeout and
/// completion handler.
public final class CommandCoordinator {
    private enum Constants {
        static let requestTimeoutSeconds: TimeInterval = 30
        static let commandRetryIntervalSeconds: TimeInterval = 5
        static let readOverTemperatureTimeoutSeconds: TimeInterval = 5
    }

    typealias DateProvider = () -> Date
    /// Sends a command over one fixed transport.
    typealias SendAction = () -> Void

    /// Sends a command over the currently selected route and returns
    /// the response keys that should complete that send attempt.
    typealias RoutedSendAction = () -> Set<CommandAttemptKey>

    /// Returns whether a device status update confirms that a command applied.
    typealias CommandConfirmationHandler = (_ status: DeviceStatus) -> Bool
    typealias ReadOverTemperatureCompletionHandler = (_ success: Bool, _ overTemperature: Bool) -> Void

    private struct NodeCommandKey: Hashable {
        let messageType: NodeMessageType
        let requestId: UInt32
    }

    private final class NodeCommandOperation {
        let key: NodeCommandKey
        let request: NodeRequest
        let send: SendAction
        let completion: CommandCompletionHandler
        let timeSent: Date
        var nextRetryTime: Date

        init(request: NodeRequest,
             send: @escaping SendAction,
             completion: @escaping CommandCompletionHandler,
             timeSent: Date) {
            self.key = NodeCommandKey(messageType: request.messageType, requestId: request.requestId)
            self.request = request
            self.send = send
            self.completion = completion
            self.timeSent = timeSent
            self.nextRetryTime = timeSent.addingTimeInterval(Constants.commandRetryIntervalSeconds)
        }
    }

    private final class RoutedCommandOperation {
        let id = UUID()
        let targetSerialNumber: String
        let send: RoutedSendAction
        let isConfirmed: CommandConfirmationHandler
        let completion: CommandCompletionHandler
        let timeSent: Date
        let retriesEnabled: Bool
        var nextRetryTime: Date
        var attemptKeys: Set<CommandAttemptKey> = []

        init(targetSerialNumber: String,
             send: @escaping RoutedSendAction,
             isConfirmed: @escaping CommandConfirmationHandler,
             completion: @escaping CommandCompletionHandler,
             timeSent: Date,
             retriesEnabled: Bool) {
            self.targetSerialNumber = targetSerialNumber
            self.send = send
            self.isConfirmed = isConfirmed
            self.completion = completion
            self.timeSent = timeSent
            self.retriesEnabled = retriesEnabled
            self.nextRetryTime = timeSent.addingTimeInterval(Constants.commandRetryIntervalSeconds)
        }
    }

    private final class NodeCommandHandle: CommandHandle {
        private weak var commandCoordinator: CommandCoordinator?
        private let key: NodeCommandKey

        init(commandCoordinator: CommandCoordinator, key: NodeCommandKey) {
            self.commandCoordinator = commandCoordinator
            self.key = key
        }

        func cancel() {
            commandCoordinator?.cancelNodeCommand(key: key)
        }
    }

    private final class RoutedCommandHandle: CommandHandle {
        private weak var commandCoordinator: CommandCoordinator?
        private let id: UUID

        init(commandCoordinator: CommandCoordinator, id: UUID) {
            self.commandCoordinator = commandCoordinator
            self.id = id
        }

        func cancel() {
            commandCoordinator?.cancelRoutedCommand(id: id)
        }
    }

    private struct ReadOverTemperatureHandler {
        let timeSent: Date
        let completion: ReadOverTemperatureCompletionHandler
    }

    /// Fixed MeatNet node commands keyed by the node response type and request ID.
    ///
    /// These are used for commands whose target is a node/accessory route rather
    /// than a probe command that can switch between direct and MeatNet transports.
    private var nodeCommandOperations: [NodeCommandKey: NodeCommandOperation] = [:]

    /// probe commands keyed by coordinator-generated operation ID.
    ///
    /// Each operation may accumulate multiple direct or node attempt keys as it
    /// is sent and retried across changing routes. Any matching attempt response
    /// or status confirmation completes the whole command.
    private var routedCommandOperations: [UUID: RoutedCommandOperation] = [:]

    private var readOverTemperatureHandlers: [String: ReadOverTemperatureHandler] = [:]

    private let dateProvider: DateProvider
    private let queue = DispatchQueue(label: "com.combustion.ble.command-coordinator")

    init(dateProvider: @escaping DateProvider = Date.init) {
        self.dateProvider = dateProvider
    }

    /// Advances command state for timeouts and scheduled retries.
    ///
    /// This method is intended to be called periodically by `DeviceManager`.
    /// Retry sends and completion callbacks are invoked outside the internal
    /// queue to avoid re-entrant coordinator work while state is locked.
    func checkForTimeout() {
        let now = dateProvider()
        let actions = queue.sync { () -> (completions: [CommandCompletionAction],
                                          retries: [SendAction],
                                          readOverTemperatures: [ReadOverTemperatureCompletionHandler]) in
            var completions: [CommandCompletionAction] = []
            var retries: [SendAction] = []
            var readOverTemperatures: [ReadOverTemperatureCompletionHandler] = []

            checkNodeCommandProgress(operations: Array(nodeCommandOperations.values),
                                     now: now,
                                     commandCompletions: &completions,
                                     commandRetries: &retries)
            checkRoutedCommandProgress(operations: Array(routedCommandOperations.values),
                                       now: now,
                                       commandCompletions: &completions,
                                       commandRetries: &retries)
            checkReadOverTemperatureTimeout(now: now,
                                            readOverTemperatureCompletions: &readOverTemperatures)

            return (completions, retries, readOverTemperatures)
        }

        for send in actions.retries {
            send()
        }

        for action in actions.completions {
            action.completion(action.result)
        }

        for completion in actions.readOverTemperatures {
            completion(false, false)
        }
    }

    /// Updates pending command state after a peripheral disconnects.
    ///
    /// Routed commands stay pending, but their stale direct response keys are
    /// removed so a later retry can complete through whatever route is available
    /// at that time.
    func handleDeviceDisconnected(identifier: UUID) {
        let readOverTemperatureCompletions = queue.sync { () -> [ReadOverTemperatureCompletionHandler] in
            let identifierString = identifier.uuidString

            for operation in routedCommandOperations.values {
                operation.attemptKeys = operation.attemptKeys.filter { key in
                    switch key {
                    case .direct(_, let attemptIdentifier):
                        return attemptIdentifier != identifierString
                    case .node:
                        return true
                    }
                }
            }

            return readOverTemperatureHandlers
                .removeValue(forKey: identifierString)
                .map { [$0.completion] } ?? []
        }

        for completion in readOverTemperatureCompletions {
            completion(false, false)
        }
    }

    /// Tracks a command sent over a fixed MeatNet node request.
    ///
    /// - Parameters:
    ///   - request: Node request being sent.
    ///   - send: Closure that writes the node request.
    ///   - completionHandler: Called when the command succeeds, fails, times out, or is cancelled.
    @discardableResult
    func addNodeCommandHandler(request: NodeRequest,
                               send: @escaping SendAction,
                               completionHandler: @escaping CommandCompletionHandler) -> CommandHandle {
        let operation = NodeCommandOperation(request: request,
                                             send: send,
                                             completion: completionHandler,
                                             timeSent: dateProvider())
        queue.sync {
            nodeCommandOperations[operation.key] = operation
        }

        send()
        return NodeCommandHandle(commandCoordinator: self, key: operation.key)
    }

    /// Tracks a probe command that may switch routes between retries.
    ///
    /// Each send chooses the best currently available route and returns the
    /// response key or keys for that attempt. The command completes when any
    /// attempt response arrives, when `isConfirmed` matches a status update for
    /// `targetSerialNumber`, when the original timeout expires, or when the
    /// returned handle is cancelled.
    ///
    /// - Parameters:
    ///   - targetSerialNumber: Probe serial number used for status confirmation.
    ///   - send: Closure that selects a route, writes the command, and returns attempt keys.
    ///   - isConfirmed: Predicate that accepts a device status update confirming success.
    ///   - retriesEnabled: Whether the send closure should be retried until timeout.
    ///   - completionHandler: Called when the command succeeds, fails, times out, or is cancelled.
    @discardableResult
    func addRoutedCommandHandler(targetSerialNumber: String,
                                 send: @escaping RoutedSendAction,
                                 isConfirmed: @escaping CommandConfirmationHandler,
                                 retriesEnabled: Bool = true,
                                 completionHandler: @escaping CommandCompletionHandler) -> CommandHandle {
        let operation = RoutedCommandOperation(targetSerialNumber: targetSerialNumber,
                                               send: send,
                                               isConfirmed: isConfirmed,
                                               completion: completionHandler,
                                               timeSent: dateProvider(),
                                               retriesEnabled: retriesEnabled)
        queue.sync {
            routedCommandOperations[operation.id] = operation
        }

        sendRoutedCommand(id: operation.id)
        return RoutedCommandHandle(commandCoordinator: self, id: operation.id)
    }

    /// Completes a pending routed command from a direct probe response.
    func callDirectCommandHandler(identifier: UUID, response: Response) {
        if let action = completeRoutedCommand(attemptKey: .direct(messageType: response.messageType,
                                                                  identifier: identifier.uuidString),
                                              result: response.success ? .success : .failure) {
            action.completion(action.result)
        }
    }

    /// Completes a pending fixed node or routed command from a MeatNet node response.
    func callNodeCommandHandler(response: NodeResponse) {
        let key = NodeCommandKey(messageType: response.messageType, requestId: response.requestId)
        if let action = completeNodeCommand(key: key, result: response.success ? .success : .failure) {
            action.completion(action.result)
        } else if let action = completeRoutedCommand(attemptKey: .node(messageType: response.messageType,
                                                                       requestId: response.requestId),
                                                     result: response.success ? .success : .failure) {
            action.completion(action.result)
        }
    }

    func addReadOverTemperatureHandler(identifier: String,
                                       completionHandler: @escaping ReadOverTemperatureCompletionHandler) {
        queue.sync {
            readOverTemperatureHandlers[identifier] = ReadOverTemperatureHandler(timeSent: dateProvider(),
                                                                                 completion: completionHandler)
        }
    }

    func callReadOverTemperatureHandler(identifier: UUID, response: ReadOverTemperatureResponse) {
        let completion = queue.sync {
            readOverTemperatureHandlers.removeValue(forKey: identifier.uuidString)?.completion
        }

        completion?(response.success, response.flagSet)
    }

    /// Completes pending commands that can be confirmed by the latest device status.
    func confirmCommandStatus(serialNumber: String, status: DeviceStatus) {
        let nodeOperations = queue.sync { Array(nodeCommandOperations.values) }

        for operation in nodeOperations {
            guard let request = operation.request as? DeviceStatusConfirmingRequest,
                  request.confirmationSerialNumber == serialNumber,
                  request.isConfirmed(by: status),
                  let action = completeNodeCommand(key: operation.key, result: .success) else {
                continue
            }

            action.completion(action.result)
        }

        let routedOperations = queue.sync {
            Array(routedCommandOperations.values)
        }

        for operation in routedOperations {
            guard operation.targetSerialNumber == serialNumber,
                  operation.isConfirmed(status),
                  let action = completeRoutedCommand(id: operation.id, result: .success) else {
                continue
            }

            action.completion(action.result)
        }
    }

    private func checkNodeCommandProgress(operations: [NodeCommandOperation],
                                          now: Date,
                                          commandCompletions: inout [CommandCompletionAction],
                                          commandRetries: inout [SendAction]) {
        for operation in operations {
            if now.timeIntervalSince(operation.timeSent) >= Constants.requestTimeoutSeconds {
                if let operation = nodeCommandOperations.removeValue(forKey: operation.key) {
                    commandCompletions.append((operation.completion, .failure))
                }
                continue
            }

            if now >= operation.nextRetryTime {
                commandRetries.append(operation.send)
                operation.nextRetryTime = operation.nextRetryTime.addingTimeInterval(Constants.commandRetryIntervalSeconds)
            }
        }
    }

    private func checkRoutedCommandProgress(operations: [RoutedCommandOperation],
                                            now: Date,
                                            commandCompletions: inout [CommandCompletionAction],
                                            commandRetries: inout [SendAction]) {
        for operation in operations {
            if now.timeIntervalSince(operation.timeSent) >= Constants.requestTimeoutSeconds {
                if let operation = routedCommandOperations.removeValue(forKey: operation.id) {
                    commandCompletions.append((operation.completion, .failure))
                }
                continue
            }

            if operation.retriesEnabled && now >= operation.nextRetryTime {
                let id = operation.id
                commandRetries.append { [weak self] in
                    self?.sendRoutedCommand(id: id)
                }
                operation.nextRetryTime = operation.nextRetryTime.addingTimeInterval(Constants.commandRetryIntervalSeconds)
            }
        }
    }

    private func checkReadOverTemperatureTimeout(now: Date,
                                                 readOverTemperatureCompletions: inout [ReadOverTemperatureCompletionHandler]) {
        for (identifier, handler) in Array(readOverTemperatureHandlers) {
            if now.timeIntervalSince(handler.timeSent) >= Constants.readOverTemperatureTimeoutSeconds {
                readOverTemperatureCompletions.append(handler.completion)
                readOverTemperatureHandlers.removeValue(forKey: identifier)
            }
        }
    }

    private func cancelNodeCommand(key: NodeCommandKey) {
        if let action = completeNodeCommand(key: key, result: .cancelled) {
            action.completion(action.result)
        }
    }

    private func cancelRoutedCommand(id: UUID) {
        if let action = completeRoutedCommand(id: id, result: .cancelled) {
            action.completion(action.result)
        }
    }

    private func completeNodeCommand(key: NodeCommandKey, result: CommandResult) -> CommandCompletionAction? {
        return queue.sync {
            guard let operation = nodeCommandOperations.removeValue(forKey: key) else { return nil }
            return (operation.completion, result)
        }
    }

    private func completeRoutedCommand(attemptKey: CommandAttemptKey,
                                       result: CommandResult) -> CommandCompletionAction? {
        return queue.sync {
            guard let operation = routedCommandOperations.values.first(where: { operation in
                operation.attemptKeys.contains(attemptKey)
            }) else {
                return nil
            }

            routedCommandOperations.removeValue(forKey: operation.id)
            return (operation.completion, result)
        }
    }

    private func completeRoutedCommand(id: UUID, result: CommandResult) -> CommandCompletionAction? {
        return queue.sync {
            guard let operation = routedCommandOperations.removeValue(forKey: id) else { return nil }
            return (operation.completion, result)
        }
    }

    private func sendRoutedCommand(id: UUID) {
        guard let operation = queue.sync(execute: { routedCommandOperations[id] }) else { return }

        let attemptKeys = operation.send()
        guard !attemptKeys.isEmpty else {
            return
        }

        queue.sync {
            routedCommandOperations[id]?.attemptKeys.formUnion(attemptKeys)
        }
    }

}
