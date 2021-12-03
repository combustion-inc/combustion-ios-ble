//
//  DeviceStatus.swift
//  Needle
//
//  Created by Jesse Johnston on 10/19/20.
//  Copyright © 2020 Jason Machacek. All rights reserved.
//

import Foundation

struct DeviceStatus {
    let minSequenceNumber: UInt32
    let maxSequenceNumber: UInt32
    let temperatures: ProbeTemperatures
}

extension DeviceStatus {
    init?(fromData data: Data) {
        guard data.count >= 21 else { return nil }
        
        let minRaw = data.subdata(in: 0..<4)
        minSequenceNumber = minRaw.withUnsafeBytes {
            $0.load(as: UInt32.self)
        }
        
        let maxRaw = data.subdata(in: 4..<8)
        maxSequenceNumber = maxRaw.withUnsafeBytes {
            $0.load(as: UInt32.self)
        }
        
        // Temperatures (8 13-bit) values
        let tempData = data.subdata(in: 8..<21)
        temperatures = ProbeTemperatures.fromRawData(data: tempData)
    }
}
