//
//  LogRequest.swift
//  Needle
//
//  Created by Jesse Johnston on 10/19/20.
//  Copyright © 2020 Jason Machacek. All rights reserved.
//

import Foundation

class LogRequest: Request {
    static let PAYLOAD_LENGTH: UInt8 = 8
    
    /// Maximum number of log messages allowed per log request
    static let MAX_LOG_MESSAGES: UInt32 = 500
    
    init(minSequence: UInt32, maxSequence: UInt32) {
        super.init(payloadLength: LogRequest.PAYLOAD_LENGTH, type: .Log)
        
        // print("Log Request Range: ", minSequence, maxSequence)
        
        var min = minSequence
        let minData = Data(bytes: &min, count: MemoryLayout.size(ofValue: min))
        self.data[Request.HEADER_SIZE + 0] = minData[0]
        self.data[Request.HEADER_SIZE + 1] = minData[1]
        self.data[Request.HEADER_SIZE + 2] = minData[2]
        self.data[Request.HEADER_SIZE + 3] = minData[3]
        
        var max = maxSequence
        if((maxSequence - minSequence) > LogRequest.MAX_LOG_MESSAGES) {
            // Constrain the number of recoreds to our maximum.
            max = minSequence + LogRequest.MAX_LOG_MESSAGES - 1
        }
        
        // print("Actual Log Request Range: ", minSequence, max)
        let maxData = Data(bytes: &max, count: MemoryLayout.size(ofValue: max))
        self.data[Request.HEADER_SIZE + 4] = maxData[0]
        self.data[Request.HEADER_SIZE + 5] = maxData[1]
        self.data[Request.HEADER_SIZE + 6] = maxData[2]
        self.data[Request.HEADER_SIZE + 7] = maxData[3]
    }
}
