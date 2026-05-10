//  EngineBatteryStatus.swift
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

/// Battery level for Engine
public enum EngineBatteryLevel: UInt8 {
    case ok = 0
    case low = 1
    case critical = 2
}

/// Battery charging state for Engine
public enum EngineBatteryState: UInt8 {
    case notCharging = 0
    case charging = 1
    case fullyCharged = 2
}

/// Engine battery status parsed from 3 bytes.
public struct EngineBatteryStatus: Equatable {
    public let level: EngineBatteryLevel
    public let state: EngineBatteryState
    public let voltage: Double

    public init(level: EngineBatteryLevel, state: EngineBatteryState, voltage: Double = 0.0) {
        self.level = level
        self.state = state
        self.voltage = voltage
    }
}

extension EngineBatteryStatus {

    static func fromData(_ data: Data) -> EngineBatteryStatus {
        guard data.count >= 3 else { return defaultValues() }

        let levelByte = data[data.startIndex]
        let stateByte = data[data.startIndex + 1]

        let level = EngineBatteryLevel(rawValue: levelByte) ?? .ok
        let state = EngineBatteryState(rawValue: stateByte) ?? .notCharging
        let voltage = Double(data[data.startIndex + 2]) / 10.0

        return .init(level: level, state: state, voltage: voltage)
    }

    static func defaultValues() -> EngineBatteryStatus {
        return .init(level: .ok, state: .notCharging, voltage: 0.0)
    }
}
