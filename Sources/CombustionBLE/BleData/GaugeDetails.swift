//  GaugeDetails.swift
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

public struct GaugeDetails {
    public let sensorPresent: Bool
    public let sensoryOverheating: Bool
    public let lowBattery: Bool
    
    public init(sensorPresent: Bool, sensoryOverheating: Bool, lowBattery: Bool) {
        self.sensorPresent = sensorPresent
        self.sensoryOverheating = sensoryOverheating
        self.lowBattery = lowBattery
    }
}

extension GaugeDetails {
    
    static func fromByte(_ byte: UInt8) -> GaugeDetails {
        let sensorPresent = ((byte >> 0) & 1) != 0
        let sensorOverheating = ((byte >> 1) & 1) != 0
        let lowBattery = ((byte >> 2) & 1) != 0
        
        return .init(sensorPresent: sensorPresent,
                     sensoryOverheating: sensorOverheating,
                     lowBattery: lowBattery)
    }
    
    static func defaultValues() -> GaugeDetails {
        return .init(sensorPresent: false, sensoryOverheating: false, lowBattery: false)
    }
}
