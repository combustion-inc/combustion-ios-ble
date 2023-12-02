//  NodeRequest.swift

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

/// Class representing a Combustion BLE Node UART request.
class NodeRequest : NodeUARTMessage {
    /// Length of header component of message.
    static let HEADER_LENGTH = 10
    
    /// Contains message data.
    var data = Data()
    
    /// Random ID for this request, for tracking request-response pairs
    var requestId : UInt32
    
    /// Length of payload
    let payloadLength: Int
    
    /// Node message type
    let messageType: NodeMessageType
    
    /// Constructor for generating a new Request object.
    /// - parameter payloadLength: Length of payload of message
    /// - parameter type: Type of message
    init(outgoingPayload: Data, type: NodeMessageType) {
        self.messageType = type
        
        // Sync Bytes { 0xCA, 0xFE }
        data.append(0xCA)
        data.append(0xFE)
        
        // Calculate CRC over Message Type, request ID, payload length, payload
        var crcData = Data()
        
        // Message type
        crcData.append(type.rawValue)
        
        // Request ID
        self.requestId = UInt32.random(in: 1...UInt32.max)
        crcData.append(Data(bytes: &requestId, count: MemoryLayout<UInt32>.size))
        
        // Payload length
        crcData.append(UInt8(outgoingPayload.count))
        
        // Payload
        crcData.append(outgoingPayload)
        
        var crcValue = crcData.crc16ccitt()
        
        // CRC
        data.append(Data(bytes: &crcValue, count: MemoryLayout.size(ofValue: crcValue)))
        
        // Message Type, payload length, payload
        data.append(crcData)
        
        self.payloadLength = outgoingPayload.count
    }
    
    
    /// Constructor for an incoming Request object (from MeatNet).
    /// - parameter requestId: Request ID of this message from the Network
    /// - parameter payloadLength: Length of this message's payload
    init(requestId: UInt32, payloadLength: Int, type: NodeMessageType) {
        self.payloadLength = payloadLength
        self.requestId = requestId
        self.messageType = type
    }
    
}

extension NodeRequest {
    
    static func requestFromData(_ data : Data) -> NodeRequest? {
        // Sync bytes
        let syncBytes = data.subdata(in: 0..<2)
        let syncString = syncBytes.reduce("") {$0 + String(format: "%02x", $1)}
        guard syncString == "cafe" else {
            print("CombustionBLE : NodeRequest::fromData(): Missing sync bytes in request")
            return nil
        }
        
        // Message type
        let typeByte = data.subdata(in: 4..<5)
        let typeRaw = typeByte.withUnsafeBytes {
            $0.load(as: UInt8.self)
        }
        
        guard let messageType = NodeMessageType(rawValue: typeRaw) else {
            print("CombustionBLE : NodeRequest::fromData(): Unknown message type in request : \(typeRaw)")
            return nil
        }
        
        // Request ID
        let requestIdBytes = data.subdata(in: 5..<9)
        let requestId = requestIdBytes.withUnsafeBytes {
            $0.load(as: UInt32.self)
        }
        
        // Payload Length
        let lengthByte = data.subdata(in: 9..<10)
        let payloadLength = lengthByte.withUnsafeBytes {
            $0.load(as: UInt8.self)
        }
        
        // CRC
        let crcBytes = data.subdata(in: 2..<4)
        let crc = crcBytes.withUnsafeBytes {
            $0.load(as: UInt16.self)
        }
        
        let crcDataLength = 6 + Int(payloadLength)
        var crcData = data.dropFirst(4)
        crcData = crcData.dropLast(crcData.count - crcDataLength)
        
        let calculatedCRC = crcData.crc16ccitt()
        
        guard crc == calculatedCRC else {
            print("NodeRequest::fromData(): Invalid CRC")
            return nil
        }
        
        let requestLength = Int(payloadLength) + HEADER_LENGTH
        
        // Invalid number of bytes
        if(data.count < requestLength) {
            return nil
        }
        
        // print("Success: \(success), payloadLength: \(payloadLength)")
        
        switch messageType {
        case .probeStatus:
            return NodeProbeStatusRequest.fromRaw(data: data, requestId: requestId, payloadLength: Int(payloadLength))
        case .heartbeat:
            return NodeHeartbeatRequest.fromRaw(data: data, requestId: requestId, payloadLength: Int(payloadLength))
        case .syncThermometerList:
            // Nothing to do for this message type
            return nil
        default:
            print("CombustionBLE : Unknown node request type: \(messageType)")
            return nil
        }
    }
}
