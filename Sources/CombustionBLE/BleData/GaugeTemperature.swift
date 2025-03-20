//  GaugeTemperature.swift
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

/// Contains most recent gauge temperatures, in celcius.
public struct GaugeTemperature: Equatable {

    // ambient sensor
    public let value: Double?
    
    public init(value: Double?) {
        self.value = value
    }
}

extension GaugeTemperature {

    /// Parses temperature data from raw data buffer
    static func fromRawData(data: Data) -> GaugeTemperature {
        guard data.count >= 2 else { return .init(value: nil) } // Ensure at least 2 bytes are available
            
        let rawValue = data.withUnsafeBytes { $0.load(as: UInt16.self) }
        let temperature = rawValue & 0x1FFF // Extract the lower 13 bits
        
        let realisedTemperature = Double(temperature) * 0.05 - 20.0
        
        return .init(value: realisedTemperature)
    }
}

extension GaugeTemperature {
    // Generates fake data for UI previews
    static func withFakeData() -> GaugeTemperature {
        return GaugeTemperature(value: 50.0)
    }
    
    // Generates randome data for Simulated Gauge
    static func withRandomData() -> GaugeTemperature {
        return GaugeTemperature(value: Double.random(in: 45.0 ..< 60.0))
    }
}
