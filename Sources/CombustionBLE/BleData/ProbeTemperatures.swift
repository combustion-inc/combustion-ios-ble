//  ProbeTemperatures.swift

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

/// Contains most recent probe temperatures, in Celcius.
public struct ProbeTemperatures: Equatable {
    /// Array of probe temperatures.
    /// Index 0 is the tip sensor, 7 is the handle (ambient) sensor.
    public let values: [Double]
    
    public init(values: [Double]) {
        self.values = values
    }
}

extension ProbeTemperatures {

    /// Parses temperature data from reversed set of bytes
    static func fromReversed(bytes: [UInt8]) -> ProbeTemperatures {
        var rawTemps: [UInt16] = []
        
        // Add the temperatures in reverse order (reversed as it's a little-endian packed bitfield)
        rawTemps.insert(UInt16(bytes[0]  & 0xFF) <<  5 | UInt16(bytes[1]  & 0xF8) >> 3, at: 0 )
        rawTemps.insert(UInt16(bytes[1]  & 0x07) << 10 | UInt16(bytes[2]  & 0xFF) << 2 | UInt16(bytes[3]  & 0xC0) >> 6, at: 0 )
        rawTemps.insert(UInt16(bytes[3]  & 0x3F) <<  7 | UInt16(bytes[4]  & 0xFE) >> 1, at: 0 )
        rawTemps.insert(UInt16(bytes[4]  & 0x01) << 12 | UInt16(bytes[5]  & 0xFF) << 4 | UInt16(bytes[6]  & 0xF0) >> 4, at: 0 )
        rawTemps.insert(UInt16(bytes[6]  & 0x0F) <<  9 | UInt16(bytes[7]  & 0xFF) << 1 | UInt16(bytes[8]  & 0x80) >> 7, at: 0 )
        rawTemps.insert(UInt16(bytes[8]  & 0x7F) <<  6 | UInt16(bytes[9]  & 0xFC) >> 2, at: 0 )
        rawTemps.insert(UInt16(bytes[9]  & 0x03) << 11 | UInt16(bytes[10] & 0xFF) << 3 | UInt16(bytes[11] & 0xE0) >> 5, at: 0 )
        rawTemps.insert(UInt16(bytes[11] & 0x1F) <<  8 | UInt16(bytes[12] & 0xFF) >> 0, at: 0 )

        let temperatures = rawTemps.map { Double($0) * 0.05 - 20.0 }
        return ProbeTemperatures(values: temperatures)
    }


    /// Parses temperature data from raw data buffer
    static func fromRawData(data: Data) -> ProbeTemperatures {

        // Reverse the byte order (this is a little-endian packed bitfield)
        var bytes : [UInt8] = []
        for byte in data {
            bytes.insert(byte as UInt8, at: 0)
        }
        
        return fromReversed(bytes: bytes)
    }
}


extension ProbeTemperatures {
    // Generates fake data for UI previews
    static func withFakeData() -> ProbeTemperatures {
        let temperatures : [Double] = [
            50.0,
            60.0,
            70.0,
            80.0,
            100.0,
            200.0,
            300.0,
            400.0
        ]
        return ProbeTemperatures(values: temperatures)
    }
    
    // Generates randome data for Simulated Probe
    static func withRandomData() -> ProbeTemperatures {
        let temperatures : [Double] = [
            Double.random(in: 45.0 ..< 60.0),
            Double.random(in: 45.0 ..< 60.0),
            Double.random(in: 45.0 ..< 60.0),
            Double.random(in: 45.0 ..< 60.0),
            Double.random(in: 45.0 ..< 60.0),
            Double.random(in: 45.0 ..< 60.0),
            Double.random(in: 45.0 ..< 60.0),
            Double.random(in: 45.0 ..< 60.0),
        ]
        return ProbeTemperatures(values: temperatures)
    }
}
