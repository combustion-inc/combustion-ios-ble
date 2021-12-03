//
//  LogResponse.swift
//  Needle
//
//  Created by Jesse Johnston on 10/16/20.
//  Copyright © 2021 Combustion Inc. All rights reserved.

//

import Foundation

class LogResponse: Response {
    
    let sequenceNumber: UInt32
    let temperatures: ProbeTemperatures
    
    init(data: Data, success: Bool) {
        let sequenceByteIndex = Response.HEADER_LENGTH
        let sequenceRaw = data.subdata(in: sequenceByteIndex..<(sequenceByteIndex + 4))
        sequenceNumber = sequenceRaw.withUnsafeBytes {
            $0.load(as: UInt32.self)
        }
        
        // Temperatures (8 13-bit) values
        let tempData = data.subdata(in: (Response.HEADER_LENGTH + 4)..<(Response.HEADER_LENGTH + 17))
        temperatures = ProbeTemperatures.fromRawData(data: tempData)
        
        // print("******** Received response!")
        // print("Sequence = \(sequenceNumber) : Temperature = \(temperatures)")

        super.init(success: success)
    }
}
