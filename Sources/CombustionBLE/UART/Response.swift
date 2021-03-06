//  Response.swift

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

class Response {
    static let HEADER_LENGTH = 7
    
    let success: Bool
    let payLoadLength: Int
    
    init(success: Bool, payLoadLength: Int) {
        self.success = success
        self.payLoadLength = payLoadLength
    }
}

extension Response {
    static func fromData(_ data : Data) -> [Response] {
        var responses = [Response]()
        
        var numberBytesRead = 0
        
        while(numberBytesRead < data.count) {
            let bytesToDecode = data.subdata(in: numberBytesRead..<data.count)
            if let response = responseFromData(bytesToDecode) {
                responses.append(response)
                numberBytesRead += (response.payLoadLength + Response.HEADER_LENGTH)
            }
            else {
                // Found invalid response, break out of while loop
                break
            }
        }
        
        return responses
    }
    
    private static func responseFromData(_ data : Data) -> Response? {
        // Sync bytes
        let syncBytes = data.subdata(in: 0..<2)
        let syncString = syncBytes.reduce("") {$0 + String(format: "%02x", $1)}
        guard syncString == "cafe" else {
            print("Response::fromData(): Missing sync bytes in response")
            return nil
        }
        
        // CRC : TODO (bytes 2,3)
        
        // Message type
        let typeByte = data.subdata(in: 4..<5)
        let typeRaw = typeByte.withUnsafeBytes {
            $0.load(as: UInt8.self)
        }
        
        guard let messageType = MessageType(rawValue: typeRaw) else {
            print("Response::fromData(): Unknown message type in response")
            return nil
        }
        
        // Success/Fail
        let successByte = data.subdata(in: 5..<6)
        let success = successByte.withUnsafeBytes {
            $0.load(as: Bool.self)
        }

        // Payload Length
        let lengthByte = data.subdata(in: 6..<7)
        let payloadLength = lengthByte.withUnsafeBytes {
            $0.load(as: UInt8.self)
        }
        
        let responseLength = Int(payloadLength) + HEADER_LENGTH
        
        // Invalid number of bytes
        if(data.count < responseLength) {
            return nil
        }
        
        // print("Success: \(success), payloadLength: \(payloadLength)")
        
        switch messageType {
        case .Log:
            return LogResponse(data: data, success: success)
        case .SetID:
            return SetIDResponse(success: success, payLoadLength: Int(payloadLength))
        case .SetColor:
            return SetColorResponse(success: success, payLoadLength: Int(payloadLength))
        case .SessionInfo:
            return SessionInfoResponse(data: data, success: success)
        }
    }
}
