//  Request.swift

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

/// Class representing a Combustion BLE UART request.
class Request {
    /// Length of header component of message.
    static let HEADER_SIZE = 6
    
    /// Contains message data.
    var data = Data()
    
    /// Constructor for Request object.
    /// - parameter payloadLength: Length of payload of message
    /// - parameter type: Type of message
    init(payload: Data, type: MessageType) {
        
        // Sync Bytes { 0xCA, 0xFE }
        data.append(0xCA)
        data.append(0xFE)
        
        // Calculate CRC over Message Type, payload length, payload
        var crcData = Data()
        
        // Message type
        crcData.append(type.rawValue)
        
        // Payload length
        crcData.append(UInt8(payload.count))
        
        // Payload
        crcData.append(payload)
        
        var crcValue = crcData.crc16ccitt()
        
        // CRC
        data.append(Data(bytes: &crcValue, count: MemoryLayout.size(ofValue: crcValue)))
        
        // Message Type, payload length, payload
        data.append(crcData)
    }
}
