//  MessageHandlers.swift

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

public class MessageHandlers {
    private enum Constants {
        static let directConnectionTimeOutSeconds = 5
        static let meatnetTimeOutSeconds = 30
    }
    
    // Generic completion handler for BLE messages
    /// - parameter success: Response messsage was received with success flag set
    public typealias SuccessCompletionHandler = (_ success: Bool) -> Void
    
    // Generic completion handler for BLE messages
    /// - parameter success: Response messsage was received with success flag set
    /// - parameter overTemperature: Over Temperature flag value from thermometer
    public typealias ReadOverTemperatureCompletionHandler = (_ success: Bool, _ overTemperature: Bool) -> Void
    
    // Structs to store when BLE message was sent and the completion handler for message
    private struct MessageSentHandler {
        let timeSent: Date
        let successHandler: SuccessCompletionHandler?
        let readOverTemperatureHandler: ReadOverTemperatureCompletionHandler?
    }
    
    // Completion handlers for direct probe connections
    // Dictionary of dictionaries
    // key - Message type
    // value - Dictionary (key - BLE identifier of probe, value: Message handler object)
    private var completionHandlers: [MessageType : [String: MessageSentHandler]] = [:]
    
    // Completion handlers for meatnet connections
    // Dictionary of dictionaries
    // key - Message type
    // value - Dictionary (key - Message request ID, value: Message handler object)
    private var nodeCompletionHandlers : [NodeMessageType : [UInt32: MessageSentHandler]] = [:]
    
    init() {
        // Initialize dictionaries for each message type
        for messageType in MessageType.allCases {
            completionHandlers[messageType] = [:]
        }
        
        for messageType in NodeMessageType.allCases {
            nodeCompletionHandlers[messageType] = [:]
        }
    }
    
    func checkForTimeout() {
        for messageType in MessageType.allCases {
            guard var handlers = completionHandlers[messageType] else { continue }
            checkForMessageTimeout(messageHandlers: &handlers)
        }
        
        for messageType in NodeMessageType.allCases {
            guard var handlers = nodeCompletionHandlers[messageType] else { continue }
            checkForNodeMessageTimeout(messageHandlers: &handlers)
        }
    }
    
    func clearHandlersForDevice(_ identifier: UUID) {
        for messageType in MessageType.allCases {
            completionHandlers[messageType]?.removeValue(forKey: identifier.uuidString)
        }
    }
    
    func addSuccessCompletionHandler(_ device: Device, request: Request, completionHandler: @escaping SuccessCompletionHandler) {
        if let bleIdentifier = device.bleIdentifier {
            completionHandlers[request.messageType]?[bleIdentifier] = MessageSentHandler(timeSent: Date(),
                                                                                 successHandler: completionHandler,
                                                                                 readOverTemperatureHandler: nil)
        }
    }
    
    func addReadOverTemperatureCompletionHandler(_ device: Device, request: Request, completionHandler: @escaping ReadOverTemperatureCompletionHandler) {
        if let bleIdentifier = device.bleIdentifier {
            completionHandlers[request.messageType]?[bleIdentifier] = MessageSentHandler(timeSent: Date(),
                                                                                 successHandler: nil,
                                                                                 readOverTemperatureHandler: completionHandler)
        }
    }
    
    func callSuccessHandler(_ identifier: UUID, response: Response) {
        guard var handlers = completionHandlers[response.messageType] else { return }
        
        // Call the handler
        handlers[identifier.uuidString]?.successHandler?(response.success)
        
        // Remove the handler
        handlers.removeValue(forKey: identifier.uuidString)
    }
    
    func callReadOverTemperatureCompletionHandler(_ identifier: UUID, response: ReadOverTemperatureResponse) {
        guard var handlers = completionHandlers[response.messageType] else { return }
        
        // Call the handler
        handlers[identifier.uuidString]?.readOverTemperatureHandler?(response.success, response.flagSet)
        
        // Remove the handler
        handlers.removeValue(forKey: identifier.uuidString)
    }
    
    private func checkForMessageTimeout(messageHandlers: inout [String: MessageSentHandler]) {
        let currentTime = Date()
        var keysToRemove = [String]()
        
        for key in messageHandlers.keys {
            if let messageHandler = messageHandlers[key],
               Int(currentTime.timeIntervalSince(messageHandler.timeSent)) > Constants.directConnectionTimeOutSeconds {
                
                // Messsage timeout has elapsed, therefore call handler with failure
                messageHandler.successHandler?(false)
                messageHandler.readOverTemperatureHandler?(false, false)
                
                // Save key to remove
                keysToRemove.append(key)
            }
        }
        
        // Remove keys that timed out
        for key in keysToRemove {
            messageHandlers.removeValue(forKey: key)
        }
    }
    
    private func checkForNodeMessageTimeout(messageHandlers: inout [UInt32: MessageSentHandler]) {
        let currentTime = Date()
        var keysToRemove = [UInt32]()
        
        for key in messageHandlers.keys {
            if let messageHandler = messageHandlers[key],
               Int(currentTime.timeIntervalSince(messageHandler.timeSent)) > Constants.meatnetTimeOutSeconds {
                
                // Messsage timeout has elapsed, therefore call handler with failure
                messageHandler.successHandler?(false)
                messageHandler.readOverTemperatureHandler?(false, false)
                
                // Save key to remove
                keysToRemove.append(key)
            }
        }
        
        // Remove keys that timed out
        for key in keysToRemove {
            messageHandlers.removeValue(forKey: key)
        }
    }
}

///////////////////////////////////
/// MARK - MeatNet Node completion handlers
///////////////////////////////////

extension MessageHandlers {
    func addNodeSuccessCompletionHandler(request: NodeRequest, completionHandler: @escaping SuccessCompletionHandler) {
        nodeCompletionHandlers[request.messageType]?[request.requestId] = MessageSentHandler(timeSent: Date(),
                                                                                             successHandler: completionHandler,
                                                                                             readOverTemperatureHandler: nil)
    }
    
    func callNodeSuccessCompletionHandler(response: NodeResponse) {
        guard var handlers = nodeCompletionHandlers[response.messageType] else { return }
        
        handlers[response.requestId]?.successHandler?(response.success)
        handlers.removeValue(forKey: response.requestId)
    }

}
