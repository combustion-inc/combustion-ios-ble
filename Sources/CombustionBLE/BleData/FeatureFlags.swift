//  FeatureFlags.swift

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

public struct FeatureFlags: Equatable {
    
    let wifi: Bool
    
    static let WIFI_MASK: UInt8 = 0x0001
}

extension FeatureFlags {

    /// Parses feature flag data from reversed set of bytes
    static func fromReversed(bytes: [UInt8]) -> FeatureFlags {
        let wifi = (bytes[0] & FeatureFlags.WIFI_MASK) == 1
        
        return FeatureFlags(wifi: wifi)
    }


    /// Parses feature flag data from raw data buffer
    static func fromRawData(data: Data) -> FeatureFlags {

        // Reverse the byte order (this is a little-endian packed bitfield)
        var bytes : [UInt8] = []
        for byte in data {
            bytes.insert(byte as UInt8, at: 0)
        }
        
        return fromReversed(bytes: bytes)
    }
}
