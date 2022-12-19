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
        static let messageTimeOutSeconds = 3
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
    
    private var setIDCompletionHandlers : [String: MessageSentHandler] = [:]
    private var setColorCompletionHandlers : [String: MessageSentHandler] = [:]
    private var setPredictionCompletionHandlers : [String: MessageSentHandler] = [:]
    private var readOverTemperatureCompletionHandlers : [String: MessageSentHandler] = [:]
    
    func checkForTimeout() {
        checkForMessageTimeout(messageHandlers: &setIDCompletionHandlers)
        checkForMessageTimeout(messageHandlers: &setColorCompletionHandlers)
        checkForMessageTimeout(messageHandlers: &setPredictionCompletionHandlers)
        checkForMessageTimeout(messageHandlers: &readOverTemperatureCompletionHandlers)
    }
    
    func clearHandlersForDevice(_ identifier: UUID) {
        setColorCompletionHandlers.removeValue(forKey: identifier.uuidString)
        setIDCompletionHandlers.removeValue(forKey: identifier.uuidString)
        setPredictionCompletionHandlers.removeValue(forKey: identifier.uuidString)
        readOverTemperatureCompletionHandlers.removeValue(forKey: identifier.uuidString)
    }
    
    func addSetIDCompletionHandler(_ device: Device, completionHandler: @escaping SuccessCompletionHandler) {
        if let bleIdentifier = device.bleIdentifier {
            setIDCompletionHandlers[bleIdentifier] = MessageSentHandler(timeSent: Date(),
                                                                        successHandler: completionHandler,
                                                                        readOverTemperatureHandler: nil)
        }
    }
    
    func addSetColorCompletionHandler(_ device: Device, completionHandler: @escaping SuccessCompletionHandler) {
        if let bleIdentifier = device.bleIdentifier {
            setColorCompletionHandlers[bleIdentifier] = MessageSentHandler(timeSent: Date(),
                                                                           successHandler: completionHandler,
                                                                           readOverTemperatureHandler: nil)
        }
    }
    
    func addSetPredictionCompletionHandler(_ device: Device, completionHandler: @escaping SuccessCompletionHandler) {
        if let bleIdentifier = device.bleIdentifier {
            setPredictionCompletionHandlers[bleIdentifier] = MessageSentHandler(timeSent: Date(),
                                                                                successHandler: completionHandler,
                                                                                readOverTemperatureHandler: nil)
        }
    }
    
    func addReadOverTemperatureCompletionHandler(_ device: Device, completionHandler: @escaping ReadOverTemperatureCompletionHandler) {
        if let bleIdentifier = device.bleIdentifier {
            readOverTemperatureCompletionHandlers[bleIdentifier] = MessageSentHandler(timeSent: Date(),
                                                                                      successHandler: nil,
                                                                                      readOverTemperatureHandler: completionHandler)
        }
    }
    
    func callSetIDCompletionHandler(_ identifier: UUID, response: SetIDResponse) {
        callSuccessCompletionHandler(identifier: identifier,
                                     success: response.success,
                                     handlers: &setIDCompletionHandlers)
    }
    
    func callSetColorCompletionHandler(_ identifier: UUID, response: SetColorResponse) {
        callSuccessCompletionHandler(identifier: identifier,
                                     success: response.success,
                                     handlers: &setColorCompletionHandlers)
    }
    
    func callSetPredictionCompletionHandler(_ identifier: UUID, response: SetPredictionResponse) {
        callSuccessCompletionHandler(identifier: identifier,
                                     success: response.success,
                                     handlers: &setPredictionCompletionHandlers)
    }
    
    func callReadOverTemperatureCompletionHandler(_ identifier: UUID, response: ReadOverTemperatureResponse) {
        readOverTemperatureCompletionHandlers[identifier.uuidString]?.readOverTemperatureHandler?(response.success, response.flagSet)
        readOverTemperatureCompletionHandlers.removeValue(forKey: identifier.uuidString)
    }
    
    private func checkForMessageTimeout(messageHandlers: inout [String: MessageSentHandler]) {
        let currentTime = Date()
        var keysToRemove = [String]()
        
        for key in messageHandlers.keys {
            if let messageHandler = messageHandlers[key],
               Int(currentTime.timeIntervalSince(messageHandler.timeSent)) > Constants.messageTimeOutSeconds {
                
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
    
    private func callSuccessCompletionHandler(identifier: UUID, success: Bool, handlers: inout [String: MessageSentHandler]) {
        handlers[identifier.uuidString]?.successHandler?(success)
        handlers.removeValue(forKey: identifier.uuidString)
    }
}
