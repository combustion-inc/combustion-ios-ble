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
public struct ProbeStatus {
    /// Minimum sequence number of records in Probe's memory.
    public let minSequenceNumber: UInt32
    
    /// Maximum sequence number of records in Probe's memory.
    public let maxSequenceNumber: UInt32
    
    /// Current temperatures sent by Probe.
    public let temperatures: ProbeTemperatures
    
    /// ModeId (Probe color, ID, and mode)
    public let modeId: ModeId
    
    /// Battery Status and Virtual Sensors
    public let batteryStatusVirtualSensors: BatteryStatusVirtualSensors
    
    /// Prediction Status
    public let predictionStatus: PredictionStatus
    
    /// Food Safe Data
    public let foodSafeData: FoodSafeData?
    
    /// Food Safe Status
    public let foodSafeStatus: FoodSafeStatus?
    
    /// Overheating sensors
    public let overheatingSensors: OverheatingSensors
    
    public init(minSequenceNumber: UInt32,
                maxSequenceNumber: UInt32,
                temperatures: ProbeTemperatures,
                modeId: ModeId,
                batteryStatusVirtualSensors: BatteryStatusVirtualSensors,
                predictionStatus: PredictionStatus,
                foodSafeData: FoodSafeData?,
                foodSafeStatus: FoodSafeStatus?,
                overheatingSensors: OverheatingSensors) {
        self.minSequenceNumber = minSequenceNumber
        self.maxSequenceNumber = maxSequenceNumber
        self.temperatures = temperatures
        self.modeId = modeId
        self.batteryStatusVirtualSensors = batteryStatusVirtualSensors
        self.predictionStatus = predictionStatus
        self.foodSafeData = foodSafeData
        self.foodSafeStatus = foodSafeStatus
        self.overheatingSensors = overheatingSensors
    }
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
        static let FOOD_SAFE_DATA_RANGE = 30..<40
        static let FOOD_SAFE_STATUS_RANGE = 40..<48
        static let OVERHEAT_BYTE_RANGE = 48..<49
    }
    
    init?(fromData data: Data, overheatRange: Range<Int> = Constants.OVERHEAT_BYTE_RANGE) {
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
        
        // Decode Food Safe Data
        // This field will not exist on old probe firmware
        if data.count >= Constants.FOOD_SAFE_DATA_RANGE.endIndex {
            let data = data.subdata(in: Constants.FOOD_SAFE_DATA_RANGE)
            foodSafeData = FoodSafeData.fromRawData(data: data)
        }
        else {
            foodSafeData = nil
        }
        
        // Decode Food Safe Status
        // This field will not exist on old probe firmware
        if data.count >= Constants.FOOD_SAFE_STATUS_RANGE.endIndex {
            let data = data.subdata(in: Constants.FOOD_SAFE_STATUS_RANGE)
            foodSafeStatus = FoodSafeStatus.fromRawData(data: data)
        }
        else {
            foodSafeStatus = nil
        }
        
        // Decode Over heating flags
        if data.count >= overheatRange.endIndex {
            
            // Sanity check for overheating flags. If none of the temperatures are
            // above previous temperature thresholds, then there are no overheating sensors.
            // This check was added due to a bug in Node (display and booster) firmware versions < 2.2.0
            if !OverheatingSensors.fromTemperatures(temperatures.values).isAnySensorOverheating() {
                overheatingSensors = OverheatingSensors.fromBools([])
            }
            else {
                let byte = data.subdata(in: overheatRange)[0]
                overheatingSensors = OverheatingSensors.fromByte(byte)
            }
        }
        else {
            // If status does not contain flags, then calculate from temperatures
            overheatingSensors = OverheatingSensors.fromTemperatures(temperatures.values)
        }
    }
}
