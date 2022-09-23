//  ModeId.swift

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

public enum ProbeID: UInt8, CaseIterable {
    case ID1 = 0x00
    case ID2 = 0x01
    case ID3 = 0x02
    case ID4 = 0x03
    case ID5 = 0x04
    case ID6 = 0x05
    case ID7 = 0x06
    case ID8 = 0x07
}

public enum ProbeColor: UInt8, CaseIterable {
    case COLOR1 = 0x00
    case COLOR2 = 0x01
    case COLOR3 = 0x02
    case COLOR4 = 0x03
    case COLOR5 = 0x04
    case COLOR6 = 0x05
    case COLOR7 = 0x06
    case COLOR8 = 0x07
}

public enum ProbeMode: UInt8, CaseIterable {
    case Normal      = 0x00
    case InstantRead = 0x01
    case Reserved    = 0x02
    case Error       = 0x03
}

class ModeId {
    let id: ProbeID
    let color: ProbeColor
    let mode: ProbeMode
    
    private enum Constants {
        static let PRODE_ID_MASK: UInt8 = 0x7
        static let PRODE_ID_SHIFT: UInt8 = 5
        static let PRODE_COLOR_MASK: UInt8 = 0x7
        static let PRODE_COLOR_SHIFT: UInt8 = 2
        static let PRODE_MODE_MASK: UInt8 = 0x3
    }
    
    init() {
        id = .ID1
        color = .COLOR1
        mode = .Normal
    }
    
    init(id: ProbeID, color: ProbeColor, mode: ProbeMode) {
        self.id = id
        self.color = color
        self.mode = mode
    }
    
    static func fromByte(_ byte: UInt8) -> ModeId {
        let rawProbeID = (byte  >> Constants.PRODE_ID_SHIFT ) & Constants.PRODE_ID_MASK
        let id = ProbeID(rawValue: rawProbeID) ?? .ID1
        
        let rawProbeColor = (byte >> Constants.PRODE_COLOR_SHIFT) & Constants.PRODE_COLOR_MASK
        let color =  ProbeColor(rawValue: rawProbeColor) ?? .COLOR1
        
        let rawMode = byte & (Constants.PRODE_MODE_MASK)
        let mode = ProbeMode(rawValue: rawMode) ?? .Normal
        
        return ModeId(id: id, color: color, mode: mode)
    }
}
