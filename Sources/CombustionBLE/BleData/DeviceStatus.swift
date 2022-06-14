//  DeviceStatus.swift

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

/// Message containing Probe status information.
public struct DeviceStatus {
    /// Minimum sequence number of records in Probe's memory.
    public let minSequenceNumber: UInt32
    /// Maximum sequence number of records in Probe's memory.
    public let maxSequenceNumber: UInt32
    /// Current temperatures sent by Probe.
    public let temperatures: ProbeTemperatures
    /// Prode ID
    public let id: ProbeID
    /// Probe Color
    public let color: ProbeColor
    /// Probe mode
    public let mode: ProbeMode
    /// Battery Status
    public let batteryStatus: BatteryStatus
    
    private enum Constants {
        // Locations of data in status packet
        static let MIN_SEQ_RANGE = 0..<4
        static let MAX_SEQ_RANGE = 4..<8
        static let TEMPERATURE_RANGE = 8..<21
        static let MODE_COLOR_ID_RANGE = 21..<22
        static let BATTERY_STATUS_RANGE = 22..<23
    }
}

extension DeviceStatus {
    init?(fromData data: Data) {
        guard data.count >= 21 else { return nil }
        
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
        temperatures = ProbeTemperatures.fromRawData(data: tempData)
        
        // Decode Probe ID and Color if its present in the advertising packet
        if(data.count >= 22) {
            let modeIdColorData  = data.subdata(in: Constants.MODE_COLOR_ID_RANGE)
            id = ProbeID.fromRawData(data: modeIdColorData)
            color = ProbeColor.fromRawData(data: modeIdColorData)
            mode = ProbeMode.fromRawData(data: modeIdColorData)
        }
        else {
            id = .ID1
            color = .COLOR1
            mode = .Normal
        }
        
        // Decode battery status if its present in the advertising packet
        if(data.count >= 23) {
            let statusData  = data.subdata(in: Constants.BATTERY_STATUS_RANGE)
            batteryStatus = BatteryStatus.fromRawData(data: statusData)
        }
        else {
            batteryStatus = .OK
        }
    }
}
