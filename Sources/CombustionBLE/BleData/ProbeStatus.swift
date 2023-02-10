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
struct ProbeStatus {
    /// Minimum sequence number of records in Probe's memory.
    let minSequenceNumber: UInt32
    /// Maximum sequence number of records in Probe's memory.
    let maxSequenceNumber: UInt32
    /// Current temperatures sent by Probe.
    let temperatures: ProbeTemperatures
    // ModeId (Probe color, ID, and mode)
    let modeId: ModeId
    /// Battery Status and Virtual Sensors
    let batteryStatusVirtualSensors: BatteryStatusVirtualSensors
    // Prediction Status
    let predictionStatus: PredictionStatus
}

extension ProbeStatus {
    private enum Constants {
        // Locations of data in status packet
        static let MIN_SEQ_RANGE = 0..<4
        static let MAX_SEQ_RANGE = 4..<8
        static let TEMPERATURE_RANGE = 8..<21
        static let MODE_COLOR_ID_RANGE = 21..<22
        static let DEVICE_STATUS_RANGE = 22..<23
        static let PREDICTION_STATUS_RANGE = 23..<30
    }
    
    init?(fromData data: Data) {
        guard data.count >= Constants.PREDICTION_STATUS_RANGE.endIndex else { return nil }
        
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
        
        // Decode ModeId byte
        let byte = data.subdata(in: Constants.MODE_COLOR_ID_RANGE)[0]
        modeId = ModeId.fromByte(byte)
        
        // Decode battery status & virutal sensors
        let batteryByte = data.subdata(in: Constants.DEVICE_STATUS_RANGE)[0]
        batteryStatusVirtualSensors = BatteryStatusVirtualSensors.fromByte(batteryByte)
        
        // Decode Prediction Status
        let bytes = [UInt8](data.subdata(in: Constants.PREDICTION_STATUS_RANGE))
        predictionStatus = PredictionStatus.fromBytes(bytes)
    }
}
