//  VirtualSensors.swift

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

public enum VirtualCoreSensor: UInt8 {
    case T1 = 0x00
    case T2 = 0x01
    case T3 = 0x02
    case T4 = 0x03
    case T5 = 0x04
    case T6 = 0x05
    
    static let MASK: UInt8 = 0x7
    
    public func temperatureFrom(_ temperatures: ProbeTemperatures) -> Double {
        return temperatureFrom(temperatures.values)
    }
    
    public func temperatureFrom(_ temperatures: [Double]) -> Double {
        return temperatures[Int(self.rawValue)]
    }
}

public enum VirtualSurfaceSensor: UInt8 {
    case T4 = 0x00
    case T5 = 0x01
    case T6 = 0x02
    case T7 = 0x03
    
    static let MASK: UInt8 = 0x3
    
    public func temperatureFrom(_ temperatures: ProbeTemperatures) -> Double {
        return temperatureFrom(temperatures.values)
    }
    
    public func temperatureFrom(_ temperatures: [Double]) -> Double {
        // Surface range is T4 - T7, therefore add 3
        let surfaceSensorNumber = Int(self.rawValue) + 3
        return temperatures[surfaceSensorNumber]
    }
}

public enum VirtualAmbientSensor: UInt8 {
    case T5 = 0x00
    case T6 = 0x01
    case T7 = 0x02
    case T8 = 0x03
    
    static let MASK: UInt8 = 0x3
    
    public func temperatureFrom(_ temperatures: ProbeTemperatures) -> Double {
        return temperatureFrom(temperatures.values)
    }
    
    public func temperatureFrom(_ temperatures: [Double]) -> Double {
        // Ambient range is T5 - T8, therefore add 4
        let ambientSensorNumber = Int(self.rawValue) + 4
        return temperatures[ambientSensorNumber]
    }
}

public struct VirtualSensors: Equatable {
    public let virtualCore: VirtualCoreSensor
    public let virtualSurface: VirtualSurfaceSensor
    public let virtualAmbient: VirtualAmbientSensor
    
    public init(virtualCore: VirtualCoreSensor, 
                virtualSurface: VirtualSurfaceSensor,
                virtualAmbient: VirtualAmbientSensor) {
        self.virtualCore = virtualCore
        self.virtualSurface = virtualSurface
        self.virtualAmbient = virtualAmbient
    }
}

extension VirtualSensors {
    private enum Constants {
        static let VIRTUAL_SURFACE_SHIFT: UInt8 = 3
        static let VIRTUAL_AMBIENT_SHIFT: UInt8 = 5
    }
    
    static func fromByte(_ byte: UInt8) -> VirtualSensors {
        let rawVirtualCore = (byte) & VirtualCoreSensor.MASK
        let virtualCore = VirtualCoreSensor(rawValue: rawVirtualCore) ?? .T1
        
        let rawVirtualSurface = (byte >> Constants.VIRTUAL_SURFACE_SHIFT) & VirtualSurfaceSensor.MASK
        let virtualSurface =  VirtualSurfaceSensor(rawValue: rawVirtualSurface) ?? .T4
        
        let rawVirtualAmbient = (byte >> Constants.VIRTUAL_AMBIENT_SHIFT) & VirtualAmbientSensor.MASK
        let virtualAmbient = VirtualAmbientSensor(rawValue: rawVirtualAmbient) ?? .T5
        
        return VirtualSensors(virtualCore: virtualCore, virtualSurface: virtualSurface, virtualAmbient: virtualAmbient)
    }
}
