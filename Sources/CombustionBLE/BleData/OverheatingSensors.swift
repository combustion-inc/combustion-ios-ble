/*--
MIT License

Copyright (c) 2024 Combustion Inc.

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

public struct OverheatingSensors: Codable, Equatable {
    public let sensorIndexes: [Int]
    
    public init(sensorIndexes: [Int]) {
        self.sensorIndexes = sensorIndexes
    }
}

extension OverheatingSensors {
    public func isAnySensorOverheating() -> Bool {
        return !sensorIndexes.isEmpty
    }
}

extension OverheatingSensors {
    
    /// Overheating thresholds for each sensor (in degrees C)
    private static let OVERHEATING_THRESHOLDS: [Double] = [
        105.0, // T1
        105.0, // T2
        115.0, // T3
        125.0, // T4
        315.56, // T5
        315.56, // T6
        315.56, // T7
        315.56, // T8
    ]

    static func fromByte(_ byte: UInt8) -> OverheatingSensors {
        var sensorIndexes = [Int]()
        for i in 0..<8 {
            if (byte & (1 << i)) != 0 {
                sensorIndexes.append(i)
            }
        }
        
        return OverheatingSensors(sensorIndexes: sensorIndexes)
    }
    
    public func toInt() -> Int {
        var mask: UInt8 = 0
        for index in sensorIndexes {
            mask = mask | (1 << index)
        }
        
        return Int(mask)
    }
    
    public static func fromBools(_ flags: [Bool]?) -> OverheatingSensors {
        guard let flags else { return OverheatingSensors(sensorIndexes: [])}
        
        var sensorIndexes : [Int] = []
            
        // Check T1-T8
        for (index, flag) in flags.enumerated() {
            if flag {
                sensorIndexes.append(index)
            }
        }
        
        return OverheatingSensors(sensorIndexes: sensorIndexes)
    }
    
    /// Find overheating sensors by comparing against threshold for each temperature
    static func fromTemperatures(_ temperatures: [Double]) -> OverheatingSensors{
        var sensorIndexes : [Int] = []
            
        // Check T1-T8
        for i in 0...7 {
            if temperatures[i] >= OVERHEATING_THRESHOLDS[i] {
                sensorIndexes.append(i)
            }
        }
        
        return OverheatingSensors(sensorIndexes: sensorIndexes)
    }
}
