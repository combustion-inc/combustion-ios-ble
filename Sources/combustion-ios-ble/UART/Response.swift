//
//  Response.swift
//  Needle
//
//  Created by Jesse Johnston on 10/19/20.
//  Copyright © 2020 Jason Machacek. All rights reserved.
//

import Foundation

class Response {
    static let HEADER_LENGTH = 7
    
    let success: Bool
    
    init(success: Bool) {
        self.success = success
    }
}

extension Response {
    static func fromData(_ data : Data) -> Response? {
        // print()
        // print("*** Parsing UART response")
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
        
        // print("Success: \(success), payloadLength: \(payloadLength)")
        
        switch messageType {
        case .Log:
            return LogResponse(data: data, success: success)
        }
    }
}
