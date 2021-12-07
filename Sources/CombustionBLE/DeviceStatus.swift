//
//  DeviceStatus.swift
//  Needle
//
//  Created by Jesse Johnston on 10/19/20.
//  Copyright © 2021 Combustion Inc. All rights reserved.
//

import Foundation

/// Message containing Probe status information.
public struct DeviceStatus {
    /// Minimum sequence number of records in Probe's memory.
    public let minSequenceNumber: UInt32
    /// Maximum sequence number of records in Probe's memory.
    public let maxSequenceNumber: UInt32
    /// Current temperatures sent by Probe.
    public let temperatures: ProbeTemperatures
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
