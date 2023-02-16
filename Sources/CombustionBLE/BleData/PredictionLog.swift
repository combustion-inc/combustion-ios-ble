//  PredictionLog.swift

/*--
MIT License

Copyright (c) 2022 Combustion Inc.

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

struct PredictionLog {
    let virtualSensors: VirtualSensors
    let predictionState: PredictionState
    let predictionMode: PredictionMode
    let predictionType: PredictionType
    let predictionSetPointTemperature: Double
    let predictionValueSeconds: UInt32
    let estimatedCoreTemperature: Double
}

extension PredictionLog {
    static func fromRaw(data: Data) -> PredictionLog {
        let virtualSensors = VirtualSensors.fromByte(data[0])
        
        let rawPrediction = UInt8(data[1] & 0x07) << 1 | UInt8(data[0] & 0x80) >> 7
        let predictionState = PredictionState(rawValue: rawPrediction) ?? .unknown
        
        let rawMode = UInt8(data[1] & PredictionMode.MASK) >> 3
        let predictionMode = PredictionMode(rawValue: rawMode) ?? .none
        
        let rawType = UInt8(data[1] & PredictionType.MASK) >> 5
        let predictionType = PredictionType(rawValue: rawType) ?? .none
        
        // 10 bit field
        let rawSetPoint = UInt16(data[3] & 0x01) << 9 | UInt16(data[2]) << 1 | UInt16(data[1] & 0x80) >> 7
        let predictionSetPointTemperature = Double(rawSetPoint) * 0.1

        // 17 bit field
        let predictionValueSeconds = UInt32(data[5] & 0x03) << 15 | UInt32(data[4]) << 7 | UInt32(data[3] & 0xFE) >> 1

        // 11 bit field
        let rawCore = UInt16(data[6] & 0x1F) << 6 | UInt16(data[5] & 0xFC) >> 2
        let estimatedCoreTemperature = (Double(rawCore) * 0.1) - 20.0
        
        return PredictionLog(virtualSensors: virtualSensors,
                             predictionState: predictionState,
                             predictionMode: predictionMode,
                             predictionType: predictionType,
                             predictionSetPointTemperature: predictionSetPointTemperature,
                             predictionValueSeconds: predictionValueSeconds,
                             estimatedCoreTemperature: estimatedCoreTemperature)
    }
}
