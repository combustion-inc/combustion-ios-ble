//  BatteryStatusVirtualSensors.swift

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

/// Enumeration of Battery status
public enum BatteryStatus: UInt8 {
    case ok = 0x00
    case low = 0x01
    
    static let MASK: UInt8 = 0x3
}

struct BatteryStatusVirtualSensors {
    let batteryStatus: BatteryStatus
    let virtualSensors: VirtualSensors
}

extension BatteryStatusVirtualSensors {
    
    private enum Constants {
        static let VIRTUAL_SENSORS_SHIFT: UInt8 = 2
    }
    
    static func fromByte(_ byte: UInt8) -> BatteryStatusVirtualSensors {
        let rawStatus = (byte & (BatteryStatus.MASK))
        let battery = BatteryStatus(rawValue: rawStatus) ?? .ok
        let virtualSensors = VirtualSensors.fromByte(byte >> Constants.VIRTUAL_SENSORS_SHIFT)
        
        return BatteryStatusVirtualSensors(batteryStatus: battery, virtualSensors: virtualSensors)
    }
    
    static func defaultValues() -> BatteryStatusVirtualSensors {
        return BatteryStatusVirtualSensors(batteryStatus: .ok,
                                           virtualSensors:  VirtualSensors(virtualCore: .T1, virtualSurface: .T4, virtualAmbient: .T5))
    }
}
