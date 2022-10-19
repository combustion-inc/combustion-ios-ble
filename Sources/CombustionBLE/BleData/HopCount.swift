//  HopCount.swift

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

public enum HopCount: UInt8, CaseIterable {
    case hop1 = 0x00
    case hop2 = 0x01
    case hop3 = 0x02
    case hop4 = 0x03
}

extension HopCount {
    private enum Constants {
        static let HOP_COUNT_MASK: UInt8 = 0x3
        static let HOP_COUNT_SHIFT: UInt8 = 6
    }
    
    static func from(deviceStatusByte: UInt8) -> HopCount {
        let rawHopCount = (deviceStatusByte >> Constants.HOP_COUNT_SHIFT) & Constants.HOP_COUNT_MASK
        return HopCount(rawValue: rawHopCount) ?? .hop1
    }
}
