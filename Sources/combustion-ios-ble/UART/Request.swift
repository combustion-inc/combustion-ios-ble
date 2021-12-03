//
//  Request.swift
//  Needle
//
//  Created by Jesse Johnston on 10/19/20.
//  Copyright © 2021 Combustion Inc. All rights reserved.
//

import Foundation

/// Class representing a Combustion BLE UART request.
class Request {
    /// Length of header component of message.
    static let HEADER_SIZE = 6
    
    /// Contains message data.
    var data: Data
    
    /// Constructor for Request object.
    /// - parameter payloadLength: Length of payload of message
    /// - parameter type: Type of message
    init(payloadLength: UInt8, type: MessageType) {
        let messageSize = Request.HEADER_SIZE + Int(payloadLength)
        data = Data(repeating: 0, count: messageSize)
        
        // Sync Bytes { 0xCA, 0xFE }
        data[0] = 0xCA
        data[1] = 0xFE
        
        // CRC : TODO
        
        // Message type
        data[4] = type.rawValue
        
        // Payload length
        data[5] = payloadLength
    }
}
