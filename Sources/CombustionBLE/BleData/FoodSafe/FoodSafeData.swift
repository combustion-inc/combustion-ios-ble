//  FoodSafeData.swift

/*--
MIT License

Copyright (c) 2023 Combustion Inc.

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

public struct FoodSafeData: Equatable {
    public let mode: FoodModeProductServing
    
    public let selectedThresholdReferenceTemperature: Double
    public let zValue: Double
    public let referenceTemperature: Double
    public let dValueAtRt: Double
    public let targetLogReduction: Double
    
    public init(mode: FoodModeProductServing, selectedThresholdReferenceTemperature: Double, zValue: Double, referenceTemperature: Double, dValueAtRt: Double, targetLogReduction: Double) {
        self.mode = mode
        self.selectedThresholdReferenceTemperature = selectedThresholdReferenceTemperature
        self.zValue = zValue
        self.referenceTemperature = referenceTemperature
        self.dValueAtRt = dValueAtRt
        self.targetLogReduction = targetLogReduction
    }
}

extension FoodSafeData {
    private func toPacked(_ value: Double) -> UInt16 {
        let count = (value / 0.05).rounded()
        return UInt16(count) & 0x1FFF
    }
    
    static private func fromPacked(_ rawValue: UInt16) -> Double {
        let value = Double(rawValue) * 0.05
        let rounded = (value * 100).rounded() / 100
        return rounded
    }
    
    private enum Constants {
        static let RAW_DATA_SIZE = 10
        static let RAW_MODE_RANGE = 0..<2
    }
    
    func toRawData() -> Data {
        var data = Data(count: Constants.RAW_DATA_SIZE)
        
        let rawSelectedThreshold = toPacked(selectedThresholdReferenceTemperature)
        let rawZValue = toPacked(zValue)
        let rawReferenceTemperature = toPacked(referenceTemperature)
        let rawDValueAtRt = toPacked(dValueAtRt)
        let rawLogReduction = UInt8(targetLogReduction / 0.1)
    
        let rawModeData = mode.toRaw()
        
        data[0] = rawModeData[0]
        
        data[1] = rawModeData[1]
        
        data[2] = UInt8(rawSelectedThreshold & 0x00FF)

        data[3] = UInt8((rawSelectedThreshold & 0x1F00) >> 8) | UInt8((rawZValue & 0x07) << 5)

        data[4] = UInt8((rawZValue & 0x07F8) >> 3)

        data[5] = UInt8((rawZValue & 0x1800) >> 11) | UInt8((rawReferenceTemperature & 0x003F) << 2)

        data[6] = UInt8((rawReferenceTemperature & 0x1FC0) >> 6) | UInt8((rawDValueAtRt & 0x01) << 7)

        data[7] = UInt8((rawDValueAtRt & 0x01FE) >> 1)

        data[8] = UInt8((rawDValueAtRt & 0x1E00) >> 9) | UInt8((rawLogReduction & 0x0F) << 4)
        
        data[9] = UInt8((rawLogReduction & 0xF0) >> 4)
        
        return data
    }
    
    /// Parses Food Safe data from raw data buffer
    static func fromRawData(data: Data) -> FoodSafeData? {
        guard data.count >= Constants.RAW_DATA_SIZE else { return nil }
        
        let rawModeData = data.subdata(in: Constants.RAW_MODE_RANGE)
        guard let mode = FoodModeProductServing.fromRaw(data: rawModeData) else { return nil }
        
        // Selected Threshold Reference Temperature - 13 bits
        let rawSelectedThresholdReferenceTemperature = UInt16(data[2]) | ((UInt16(data[3]) & 0x1F) << 8)
        let selectedThresholdReferenceTemperature = Double(rawSelectedThresholdReferenceTemperature) * 0.05
        
        // Z Value - 13 bits
        let rawZValue = ((UInt16(data[3]) & 0xE0) >> 5) | (UInt16(data[4]) << 3) | ((UInt16(data[5]) & 0x03) << 11)
        let zValue = fromPacked(rawZValue)
        
        // Reference Temperature - 13 bits
        let rawReferenceTemperature = ((UInt16(data[5]) & 0xFC) >> 2) | ((UInt16(data[6]) & 0x7F) << 6)
        let referenceTemperature = fromPacked(rawReferenceTemperature)
        
        // D-value at RT - 13 bits
        let rawDValueAtRt = ((UInt16(data[6]) & 0x80) >> 7) | (UInt16(data[7]) << 1) | ((UInt16(data[8]) & 0x0F) << 9)
        let dValueAtRt = fromPacked(rawDValueAtRt)
        
        // Log Reduction - 8 bits
        let rawLogReduction = ((data[8] & 0xF0) >> 4) | ((data[9] & 0x0F) << 4)
        let logReduction = Double(rawLogReduction) * 0.1
        
        return FoodSafeData(mode: mode,
                            selectedThresholdReferenceTemperature: selectedThresholdReferenceTemperature,
                            zValue: zValue,
                            referenceTemperature: referenceTemperature,
                            dValueAtRt: dValueAtRt, 
                            targetLogReduction: logReduction
        )
    }
}
