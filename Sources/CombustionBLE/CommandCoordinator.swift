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

protocol DeviceStatusConfirmingRequest {
    var confirmationSerialNumber: String { get }
    func isConfirmed(by status: DeviceStatus) -> Bool
}

private typealias CommandCompletionAction = (completion: CommandCompletionHandler, result: CommandResult)

public final class CommandCoordinator {
    private enum Constants {
        static let requestTimeoutSeconds: TimeInterval = 30
        static let commandRetryIntervalSeconds: TimeInterval = 5
        static let readOverTemperatureTimeoutSeconds: TimeInterval = 5
    }

    typealias DateProvider = () -> Date
    typealias SendAction = () -> Void
    typealias ReadOverTemperatureCompletionHandler = (_ success: Bool, _ overTemperature: Bool) -> Void

    private struct DirectCommandKey: Hashable {
        let messageType: MessageType
        let identifier: String
    }

    private struct NodeCommandKey: Hashable {
        let messageType: NodeMessageType
        let requestId: UInt32
    }

    private class CommandOperation {
        let send: SendAction
        let completion: CommandCompletionHandler
        let timeSent: Date
        var nextRetryTime: Date

        init(send: @escaping SendAction,
             completion: @escaping CommandCompletionHandler,
             timeSent: Date) {
            self.send = send
            self.completion = completion
            self.timeSent = timeSent
            self.nextRetryTime = timeSent.addingTimeInterval(Constants.commandRetryIntervalSeconds)
        }
    }

    private final class DirectCommandOperation: CommandOperation {
        let key: DirectCommandKey
        let request: Request

        init(identifier: String,
             request: Request,
             send: @escaping SendAction,
             completion: @escaping CommandCompletionHandler,
             timeSent: Date) {
            self.key = DirectCommandKey(messageType: request.messageType, identifier: identifier)
            self.request = request
            super.init(send: send, completion: completion, timeSent: timeSent)
        }
    }

    private final class NodeCommandOperation: CommandOperation {
        let key: NodeCommandKey
        let request: NodeRequest

        init(request: NodeRequest,
             send: @escaping SendAction,
             completion: @escaping CommandCompletionHandler,
             timeSent: Date) {
            self.key = NodeCommandKey(messageType: request.messageType, requestId: request.requestId)
            self.request = request
            super.init(send: send, completion: completion, timeSent: timeSent)
        }
    }

    private final class DirectCommandHandle: CommandHandle {
        private weak var commandCoordinator: CommandCoordinator?
        private let key: DirectCommandKey

        init(commandCoordinator: CommandCoordinator, key: DirectCommandKey) {
            self.commandCoordinator = commandCoordinator
            self.key = key
        }

        func cancel() {
            commandCoordinator?.cancelDirectCommand(key: key)
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

    private struct ReadOverTemperatureHandler {
        let timeSent: Date
        let completion: ReadOverTemperatureCompletionHandler
    }

    private var directCommandOperations: [DirectCommandKey: DirectCommandOperation] = [:]
    private var nodeCommandOperations: [NodeCommandKey: NodeCommandOperation] = [:]
    private var readOverTemperatureHandlers: [String: ReadOverTemperatureHandler] = [:]

    private let dateProvider: DateProvider
    private let queue = DispatchQueue(label: "com.combustion.ble.command-coordinator")

    init(dateProvider: @escaping DateProvider = Date.init) {
        self.dateProvider = dateProvider
    }

    func checkForTimeout() {
        let now = dateProvider()
        let actions = queue.sync { () -> (completions: [CommandCompletionAction],
                                          retries: [SendAction],
                                          readOverTemperatures: [ReadOverTemperatureCompletionHandler]) in
            var completions: [CommandCompletionAction] = []
            var retries: [SendAction] = []
            var readOverTemperatures: [ReadOverTemperatureCompletionHandler] = []

            checkCommandProgress(operations: Array(directCommandOperations.values),
                                 now: now,
                                 commandCompletions: &completions,
                                 commandRetries: &retries,
                                 removeOperation: { operation in
                                     directCommandOperations.removeValue(forKey: operation.key)
                                 })
            checkCommandProgress(operations: Array(nodeCommandOperations.values),
                                 now: now,
                                 commandCompletions: &completions,
                                 commandRetries: &retries,
                                 removeOperation: { operation in
                                     nodeCommandOperations.removeValue(forKey: operation.key)
                                 })
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

    func clearCommandsForDevice(_ identifier: UUID) {
        queue.sync {
            for key in directCommandOperations.keys where key.identifier == identifier.uuidString {
                directCommandOperations.removeValue(forKey: key)
            }

            readOverTemperatureHandlers.removeValue(forKey: identifier.uuidString)
        }
    }

    @discardableResult
    func addDirectCommandHandler(identifier: String,
                                 request: Request,
                                 send: @escaping SendAction,
                                 completionHandler: @escaping CommandCompletionHandler) -> CommandHandle {
        let operation = DirectCommandOperation(identifier: identifier,
                                               request: request,
                                               send: send,
                                               completion: completionHandler,
                                               timeSent: dateProvider())
        queue.sync {
            directCommandOperations[operation.key] = operation
        }

        send()
        return DirectCommandHandle(commandCoordinator: self, key: operation.key)
    }

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

    func callDirectCommandHandler(identifier: UUID, response: Response) {
        let key = DirectCommandKey(messageType: response.messageType, identifier: identifier.uuidString)
        if let action = completeDirectCommand(key: key, result: response.success ? .success : .failure) {
            action.completion(action.result)
        }
    }

    func callNodeCommandHandler(response: NodeResponse) {
        let key = NodeCommandKey(messageType: response.messageType, requestId: response.requestId)
        if let action = completeNodeCommand(key: key, result: response.success ? .success : .failure) {
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

    func confirmCommandStatus(serialNumber: String, status: DeviceStatus) {
        let currentOperations = queue.sync {
            (direct: Array(directCommandOperations.values),
             node: Array(nodeCommandOperations.values))
        }

        for operation in currentOperations.direct {
            guard let request = operation.request as? DeviceStatusConfirmingRequest,
                  request.confirmationSerialNumber == serialNumber,
                  request.isConfirmed(by: status),
                  let action = completeDirectCommand(key: operation.key, result: .success) else {
                continue
            }

            action.completion(action.result)
        }

        for operation in currentOperations.node {
            guard let request = operation.request as? DeviceStatusConfirmingRequest,
                  request.confirmationSerialNumber == serialNumber,
                  request.isConfirmed(by: status),
                  let action = completeNodeCommand(key: operation.key, result: .success) else {
                continue
            }

            action.completion(action.result)
        }
    }

    private func checkCommandProgress<Operation: CommandOperation>(operations: [Operation],
                                                                   now: Date,
                                                                   commandCompletions: inout [CommandCompletionAction],
                                                                   commandRetries: inout [SendAction],
                                                                   removeOperation: (Operation) -> Operation?) {
        for operation in operations {
            if now.timeIntervalSince(operation.timeSent) >= Constants.requestTimeoutSeconds {
                if let operation = removeOperation(operation) {
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

    private func checkReadOverTemperatureTimeout(now: Date,
                                                 readOverTemperatureCompletions: inout [ReadOverTemperatureCompletionHandler]) {
        for (identifier, handler) in Array(readOverTemperatureHandlers) {
            if now.timeIntervalSince(handler.timeSent) >= Constants.readOverTemperatureTimeoutSeconds {
                readOverTemperatureCompletions.append(handler.completion)
                readOverTemperatureHandlers.removeValue(forKey: identifier)
            }
        }
    }

    private func cancelDirectCommand(key: DirectCommandKey) {
        if let action = completeDirectCommand(key: key, result: .cancelled) {
            action.completion(action.result)
        }
    }

    private func cancelNodeCommand(key: NodeCommandKey) {
        if let action = completeNodeCommand(key: key, result: .cancelled) {
            action.completion(action.result)
        }
    }

    private func completeDirectCommand(key: DirectCommandKey, result: CommandResult) -> CommandCompletionAction? {
        return queue.sync {
            guard let operation = directCommandOperations.removeValue(forKey: key) else { return nil }
            return (operation.completion, result)
        }
    }

    private func completeNodeCommand(key: NodeCommandKey, result: CommandResult) -> CommandCompletionAction? {
        return queue.sync {
            guard let operation = nodeCommandOperations.removeValue(forKey: key) else { return nil }
            return (operation.completion, result)
        }
    }
}
