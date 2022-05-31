//  ProbeID.swift

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

public enum ProbeID: UInt8, CaseIterable {
    case ID1 = 0x00
    case ID2 = 0x01
    case ID3 = 0x02
    case ID4 = 0x03
    case ID5 = 0x04
    case ID6 = 0x05
    case ID7 = 0x06
    case ID8 = 0x07
    
    private enum Constants {
        static let PRODE_ID_MASK: UInt8 = 0x7
        static let PRODE_ID_SHIFT: UInt8 = 5
    }
    
    static func fromRawData(data: Data) -> ProbeID {
        let modeIdColorBytes = [UInt8](data)
        
        let rawProbeID = (modeIdColorBytes[0] & (Constants.PRODE_ID_MASK << Constants.PRODE_ID_SHIFT)) >> Constants.PRODE_ID_SHIFT
        return ProbeID(rawValue: rawProbeID) ?? .ID1
    }
}
