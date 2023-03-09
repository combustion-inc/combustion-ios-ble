//  NodeResponse.swift

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

class NodeResponse : NodeUARTMessage {
    static let HEADER_LENGTH = 15
    
    // Node Response messages have the leftmost bit in the 'message type' field set to 1.
    static let RESPONSE_TYPE_FLAG : UInt8 = 0x80
    
    let success: Bool
    let payloadLength: Int
    
    let requestId: UInt32
    let responseId: UInt32
    
    init(success: Bool, requestId: UInt32, responseId: UInt32, payloadLength: Int) {
        self.success = success
        self.payloadLength = payloadLength
        self.requestId = requestId
        self.responseId = responseId
    }
}

extension NodeResponse {
    
    static func responseFromData(_ data : Data) -> NodeResponse? {
        // Sync bytes
        let syncBytes = data.subdata(in: 0..<2)
        let syncString = syncBytes.reduce("") {$0 + String(format: "%02x", $1)}
        guard syncString == "cafe" else {
            print("NodeResponse::fromData(): Missing sync bytes in response")
            return nil
        }
        
        // Message type
        let typeByte = data.subdata(in: 4..<5)
        let typeRaw = typeByte.withUnsafeBytes {
            $0.load(as: UInt8.self)
        }
        
        // Verify that this is a Response by checking the response type flag
        guard typeRaw & RESPONSE_TYPE_FLAG == RESPONSE_TYPE_FLAG else {
            // If that 'response type' bit isn't set, this is probably a Request.
            return nil
        }
        
        guard let messageType = NodeMessageType(rawValue: (typeRaw & ~RESPONSE_TYPE_FLAG)) else {
            print("NodeResponse::fromData(): Unknown message type in response")
            return nil
        }
        
        // Request ID
        let requestIdBytes = data.subdata(in: 5..<9)
        let requestId = requestIdBytes.withUnsafeBytes {
            $0.load(as: UInt32.self)
        }
        
        // Response ID
        let responseIdBytes = data.subdata(in: 9..<13)
        let responseId = responseIdBytes.withUnsafeBytes {
            $0.load(as: UInt32.self)
        }
        
        
        // Success/Fail
        let successByte = data.subdata(in: 13..<14)
        let success = successByte.withUnsafeBytes {
            $0.load(as: Bool.self)
        }

        // Payload Length
        let lengthByte = data.subdata(in: 14..<15)
        let payloadLength = lengthByte.withUnsafeBytes {
            $0.load(as: UInt8.self)
        }
        
        // CRC
        let crcBytes = data.subdata(in: 2..<4)
        let crc = crcBytes.withUnsafeBytes {
            $0.load(as: UInt16.self)
        }
        
        let crcDataLength = 11 + Int(payloadLength)
        var crcData = data.dropFirst(4)
        crcData = crcData.dropLast(crcData.count - crcDataLength)
        
        let calculatedCRC = crcData.crc16ccitt()
        
        guard crc == calculatedCRC else {
            print("NodeResponse::fromData(): Invalid CRC")
            return nil
        }
        
        let responseLength = Int(payloadLength) + HEADER_LENGTH
        
        // Invalid number of bytes
        if(data.count < responseLength) {
            print("Bad number of bytes")
            return nil
        }
        
        // print("Success: \(success), payloadLength: \(payloadLength)")
        
        switch messageType {
        case .log:
            return NodeReadLogsResponse.fromRaw(data: data, success: success, requestId: requestId, responseId: responseId, payloadLength: Int(payloadLength))
//        case .setID:
//            return NodeSetIDResponse(success: success, payloadLength: Int(payloadLength))
//        case .setColor:
//            return NodeSetColorResponse(success: success, payloadLength: Int(payloadLength))
        case .sessionInfo:
            return NodeReadSessionInfoResponse.fromRaw(data: data, success: success, requestId: requestId, responseId: responseId, payloadLength: Int(payloadLength))
        case .setPrediction:
            return NodeSetPredictionResponse(success: success, requestId: requestId, responseId: responseId, payloadLength: Int(payloadLength))
        case .probeFirmwareRevision:
            return NodeReadFirmwareRevisionResponse.fromRaw(data: data, success: success, requestId: requestId, responseId: responseId, payloadLength: Int(payloadLength))
        case .probeHardwareRevision:
            return NodeReadHardwareRevisionResponse.fromRaw(data: data, success: success, requestId: requestId, responseId: responseId, payloadLength: Int(payloadLength))
        case .probeModelInformation:
            return NodeReadModelInfoResponse.fromRaw(data: data, success: success, requestId: requestId, responseId: responseId, payloadLength: Int(payloadLength))
//        case .readOverTemperature:
//            return NodeReadOverTemperatureResponse(data: data, success: success, payloadLength: Int(payloadLength))
        default:
            print("Unknown node response type: \(messageType)")
            return nil
        }
    }
}
