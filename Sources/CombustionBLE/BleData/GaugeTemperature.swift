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

    /// Parses temperature data from reversed set of bytes
    static func fromReversed(bytes: [UInt8]) -> GaugeTemperature {
        var rawTemps: [UInt16] = []
        
        // Add the temperatures in reverse order (reversed as it's a little-endian packed bitfield)
        rawTemps.insert(UInt16(bytes[0]  & 0xFF) <<  5 | UInt16(bytes[1]  & 0xF8) >> 3, at: 0 )

        let temperatures = rawTemps.map { Double($0) * 0.05 - 20.0 }
        
        return GaugeTemperature(value: temperatures.first ?? 0)
    }


    /// Parses temperature data from raw data buffer
    static func fromRawData(data: Data) -> GaugeTemperature {

        // Reverse the byte order (this is a little-endian packed bitfield)
        var bytes : [UInt8] = []
        for byte in data {
            bytes.insert(byte as UInt8, at: 0)
        }
        
        return fromReversed(bytes: bytes)
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
