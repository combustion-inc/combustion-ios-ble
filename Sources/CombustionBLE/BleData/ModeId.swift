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

public enum ProbeID: UInt8, CaseIterable, Codable {
    case ID1 = 0x00
    case ID2 = 0x01
    case ID3 = 0x02
    case ID4 = 0x03
    case ID5 = 0x04
    case ID6 = 0x05
    case ID7 = 0x06
    case ID8 = 0x07
}

public enum ProbeColor: UInt8, CaseIterable, Codable {
    case color1 = 0x00
    case color2 = 0x01
    case color3 = 0x02
    case color4 = 0x03
    case color5 = 0x04
    case color6 = 0x05
    case color7 = 0x06
    case color8 = 0x07
}

public enum ProbeMode: UInt8, CaseIterable {
    case normal      = 0x00
    case instantRead = 0x01
    case reserved    = 0x02
    case error       = 0x03
}

public enum ProbePowerMode: UInt8, CaseIterable {
    case normal   = 0x00
    case alwaysOn = 0x01
}

public struct ModeId {
    public let id: ProbeID
    public let color: ProbeColor
    public let mode: ProbeMode
    public let powerMode : ProbePowerMode
    
    public init(id: ProbeID, color: ProbeColor, mode: ProbeMode, powerMode: ProbePowerMode) {
        self.id = id
        self.color = color
        self.mode = mode
        self.powerMode = powerMode
    }
}

extension ModeId {
    private enum Constants {
        static let PROBE_ID_MASK: UInt8 = 0x7
        static let PROBE_ID_SHIFT: UInt8 = 5
        static let PROBE_COLOR_MASK: UInt8 = 0x7
        static let PROBE_COLOR_SHIFT: UInt8 = 2
        static let PROBE_MODE_MASK: UInt8 = 0x3
        static let PROBE_POWER_MODE_MASK: UInt8 = 0x4
    }
    
    static func fromByte(_ byte: UInt8) -> ModeId {
        let rawProbeID = (byte  >> Constants.PROBE_ID_SHIFT ) & Constants.PROBE_ID_MASK
        let id = ProbeID(rawValue: rawProbeID) ?? .ID1
        
        let rawProbeColor = (byte >> Constants.PROBE_COLOR_SHIFT) & Constants.PROBE_COLOR_MASK
        let color =  ProbeColor(rawValue: rawProbeColor) ?? .color1
        
        let rawMode = byte & (Constants.PROBE_MODE_MASK)
        let mode = ProbeMode(rawValue: rawMode) ?? .normal
        
        let rawPowerMode = byte & (Constants.PROBE_POWER_MODE_MASK)
        let powerMode = ProbePowerMode(rawValue: rawPowerMode) ?? .normal
        
        return ModeId(id: id, color: color, mode: mode, powerMode: powerMode)
    }
    
    static func defaultValues() -> ModeId {
        return ModeId(id: .ID1, color: .color1, mode: .normal, powerMode: .normal)
    }
}
