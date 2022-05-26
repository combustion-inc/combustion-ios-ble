//  ProbeColor.swift

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

public enum ProbeColor: UInt8, CaseIterable {
    case COLOR1 = 0x00
    case COLOR2 = 0x01
    case COLOR3 = 0x02
    case COLOR4 = 0x03
    case COLOR5 = 0x04
    case COLOR6 = 0x05
    case COLOR7 = 0x06
    case COLOR8 = 0x07
    
    private enum Constants {
        static let PRODE_COLOR_MASK: UInt8 = 0x7
        static let PRODE_COLOR_SHIFT: UInt8 = 2
    }
    
    static func fromRawData(data: Data) -> ProbeColor {
        let modeIdColorBytes = [UInt8](data)
        
        let rawProbeColor = (modeIdColorBytes[0] & (Constants.PRODE_COLOR_MASK << Constants.PRODE_COLOR_SHIFT)) >> Constants.PRODE_COLOR_SHIFT
        return ProbeColor(rawValue: rawProbeColor) ?? .COLOR1
    }
}
