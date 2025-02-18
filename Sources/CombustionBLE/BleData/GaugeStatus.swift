//  GaugeStatus.swift
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

/// Message containing Gauge status information.
public struct GaugeStatus {
    /// Minimum sequence number of records in Probe's memory.
    public let minSequenceNumber: UInt32
    
    /// Maximum sequence number of records in Probe's memory.
    public let maxSequenceNumber: UInt32
    
    /// Current temperature sent by Gauge.
    public let temperature: GaugeTemperature
    
    /// ModeId (Gauge color, ID, and mode)
    public let modeId: ModeId
    
    /// Battery Status and Virtual Sensors
    public let batteryStatusVirtualSensors: BatteryStatusVirtualSensors
    
    /// Overheating sensors
    public let overheatingSensors: OverheatingSensors
    
    public init(minSequenceNumber: UInt32,
                maxSequenceNumber: UInt32,
                temperature: GaugeTemperature,
                modeId: ModeId,
                batteryStatusVirtualSensors: BatteryStatusVirtualSensors,
                overheatingSensors: OverheatingSensors) {
        self.minSequenceNumber = minSequenceNumber
        self.maxSequenceNumber = maxSequenceNumber
        self.temperature = temperature
        self.modeId = modeId
        self.batteryStatusVirtualSensors = batteryStatusVirtualSensors
        self.overheatingSensors = overheatingSensors
    }
}

extension GaugeStatus {
    private enum Constants {
        // Locations of data in status packet
        static let MIN_SEQ_RANGE = 0..<4
        static let MAX_SEQ_RANGE = 4..<8
        static let TEMPERATURE_RANGE = 8..<21
        static let MODE_COLOR_ID_RANGE = 21..<22
        static let DEVICE_STATUS_RANGE = 22..<23
        static let OVERHEAT_BYTE_RANGE = 48..<49
    }
    
    init?(fromData data: Data) {
        guard data.count >= Constants.OVERHEAT_BYTE_RANGE.endIndex else { return nil }
        
        let minRaw = data.subdata(in: Constants.MIN_SEQ_RANGE)
        minSequenceNumber = minRaw.withUnsafeBytes {
            $0.load(as: UInt32.self)
        }
        
        let maxRaw = data.subdata(in: Constants.MAX_SEQ_RANGE)
        maxSequenceNumber = maxRaw.withUnsafeBytes {
            $0.load(as: UInt32.self)
        }
        
        // Temperatures (8 13-bit) values
        let tempData = data.subdata(in: Constants.TEMPERATURE_RANGE)
        temperature = GaugeTemperature.fromRawData(data: tempData)
        
        // Decode ModeId byte
        let byte = data.subdata(in: Constants.MODE_COLOR_ID_RANGE)[0]
        modeId = ModeId.fromByte(byte)
        
        // Decode battery status & virutal sensors
        let batteryByte = data.subdata(in: Constants.DEVICE_STATUS_RANGE)[0]
        batteryStatusVirtualSensors = BatteryStatusVirtualSensors.fromByte(batteryByte)
        
        // Decode Over heating flags
        let overheatingByte = data.subdata(in: Constants.OVERHEAT_BYTE_RANGE)[0]
        overheatingSensors = OverheatingSensors.fromByte(overheatingByte)
    }
}
