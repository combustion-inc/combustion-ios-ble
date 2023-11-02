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

struct FoodSafeData {
    let mode: FoodSafeMode
    let protein: Protein
    let form: Form
    let serving: Serving
    let selectedThresholdReferenceTemperature: Double
    let zValue: Double
    let referenceTemperature: Double
    let dValueAtRt: Double
}

extension FoodSafeData {
    /// Parses Food Safe data from raw data buffer
    static func fromRawData(data: Data) -> FoodSafeData? {
        guard data.count >= 9 else { return nil }
        
        // Food Safe Mode - 3 bits
        let rawMode = data[0] & FoodSafeMode.MASK
        let mode = FoodSafeMode(rawValue: rawMode) ?? .simplified
        
        // Protein - 6 bits
        let rawProtein = ((data[0] & 0xF8) >> 3) | ((data[1] & 0x01) << 5)
        let protein = Protein(rawValue: rawProtein) ?? ._default
        
        // Form - 4 bits
        let rawForm = (data[1] >> 1) & Form.MASK
        let form = Form(rawValue: rawForm) ?? .intactCut
        
        // Serving - 3 bits
        let rawServing = (data[1] >> 5) & Serving.MASK
        let serving = Serving(rawValue: rawServing) ?? .servedImmediately
        
        // Selected Threshold Reference Temperature - 13 bits
        let rawSelectedThresholdReferenceTemperature = UInt16(data[2]) | ((UInt16(data[3]) & 0x1F) << 8)
        let selectedThresholdReferenceTemperature = Double(rawSelectedThresholdReferenceTemperature) * 0.05
        
        // Z Value - 13 bits
        let rawZValue = ((UInt16(data[3]) & 0xE0) >> 5) | (UInt16(data[4]) << 3) | ((UInt16(data[5]) & 0x03) << 11)
        let zValue = Double(rawZValue) * 0.05
        
        // Reference Temperature - 13 bits
        let rawReferenceTemperature = ((UInt16(data[5]) & 0xFC) >> 2) | ((UInt16(data[6]) & 0x7F) << 6)
        let referenceTemperature = Double(rawReferenceTemperature) * 0.05
        
        // D-value at RT - 13 bits
        let rawDValueAtRt = ((UInt16(data[6]) & 0x80) >> 7) | (UInt16(data[7]) << 1) | ((UInt16(data[8]) & 0x0F) << 9)
        let dValueAtRt = Double(rawDValueAtRt) * 0.05
        
        return FoodSafeData(mode: mode, 
                            protein: protein, 
                            form: form, 
                            serving: serving,
                            selectedThresholdReferenceTemperature: selectedThresholdReferenceTemperature,
                            zValue: zValue,
                            referenceTemperature: referenceTemperature,
                            dValueAtRt: dValueAtRt
        )
    }
}
