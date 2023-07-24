//  PredictionStatus.swift

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

struct PredictionStatus {
    public let predictionState: PredictionState
    public let predictionMode: PredictionMode
    public let predictionType: PredictionType
    public let predictionSetPointTemperature: Double
    public let heatStartTemperature: Double
    public let predictionValueSeconds: UInt
    public let estimatedCoreTemperature: Double
}
 
extension PredictionStatus {
    static func fromBytes(_ bytes: [UInt8]) -> PredictionStatus {
        let rawPredictionState = bytes[0] & PredictionState.MASK
        let predictionState = PredictionState(rawValue: rawPredictionState) ?? .unknown
        
        let rawPredictionMode = (bytes[0] >> 4) & PredictionMode.MASK
        let predictionMode = PredictionMode(rawValue: rawPredictionMode) ?? .none
        
        let rawPredictionType = (bytes[0] >> 6) & PredictionType.MASK
        let predictionType = PredictionType(rawValue: rawPredictionType) ?? .none
        
        // 10 bit field
        let rawSetPoint = UInt16(bytes[2] & 0x03) << 8 | UInt16(bytes[1])
        let setPoint = Double(rawSetPoint) * 0.1
        
        // 10 bit field
        let rawHeatStart = UInt16(bytes[3] & 0x0F) << 6 | UInt16(bytes[2] & 0xFC) >> 2
        let heatStart = Double(rawHeatStart) * 0.1
        
        // 17 bit field
        let seconds = UInt32(bytes[5] & 0x1F) << 12 | UInt32(bytes[4]) << 4 | UInt32(bytes[3] & 0xF0) >> 4
        
        // 11 bit field
        let rawCore = UInt16(bytes[6]) << 3 | UInt16(bytes[5] & 0xE0) >> 5
        let estimatedCore = (Double(rawCore) * 0.1) - 20.0
        
        return PredictionStatus(predictionState: predictionState,
                                predictionMode: predictionMode,
                                predictionType: predictionType,
                                predictionSetPointTemperature: setPoint,
                                heatStartTemperature: heatStart,
                                predictionValueSeconds: UInt(seconds),
                                estimatedCoreTemperature: estimatedCore)
    }
}
