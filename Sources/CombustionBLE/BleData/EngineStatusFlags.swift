//  EngineStatusFlags.swift
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

/// Engine status flags parsed from a single byte
public struct EngineStatusFlags: Equatable {
    /// True if temperature set point is controlled by app, false if by dial
    public let appMode: Bool
    /// True if Engine can see its control device (probe or gauge)
    public let controlDeviceConnected: Bool
    /// True if lid is detected as open
    public let lidOpen: Bool
    /// True if fan is running at fixed speed (vs. a setpoint)
    public let fixedSpeed: Bool

    public init(appMode: Bool, controlDeviceConnected: Bool, lidOpen: Bool, fixedSpeed: Bool) {
        self.appMode = appMode
        self.controlDeviceConnected = controlDeviceConnected
        self.lidOpen = lidOpen
        self.fixedSpeed = fixedSpeed
    }
}

extension EngineStatusFlags {

    static func fromByte(_ byte: UInt8) -> EngineStatusFlags {
        let appMode = ((byte >> 0) & 1) != 0
        let controlDeviceConnected = ((byte >> 1) & 1) != 0
        let lidOpen = ((byte >> 2) & 1) != 0
        let fixedSpeed = ((byte >> 3) & 1) != 0

        return .init(appMode: appMode,
                     controlDeviceConnected: controlDeviceConnected,
                     lidOpen: lidOpen,
                     fixedSpeed: fixedSpeed)
    }

    static func defaultValues() -> EngineStatusFlags {
        return .init(appMode: false, controlDeviceConnected: false, lidOpen: false, fixedSpeed: false)
    }
}
