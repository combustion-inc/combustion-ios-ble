//  EngineFanStatus.swift
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

/// Fan state for Engine
public enum EngineFanState: UInt8, Codable {
    case powerDown = 0
    case paused = 1
    case lidOpen = 2
    case fanOff = 3
    case fanOn = 4
}

/// Engine fan status parsed from 12 bytes
public struct EngineFanStatus: Equatable, Codable {
    /// Current fan state
    public let fanState: EngineFanState
    /// Duty cycle (0-100 percentage)
    public let dutyCycle: UInt8
    /// Commanded speed (0-100 percentage)
    public let commandedSpeed: UInt8
    /// Measured speed (0-100 percentage)
    public let measuredSpeed: UInt8
    /// Fan off time in time window (milliseconds)
    public let fanOffTime: UInt32
    /// Fan on time in time window (milliseconds)
    public let fanOnTime: UInt32

    public init(fanState: EngineFanState,
                dutyCycle: UInt8,
                commandedSpeed: UInt8,
                measuredSpeed: UInt8,
                fanOffTime: UInt32,
                fanOnTime: UInt32) {
        self.fanState = fanState
        self.dutyCycle = dutyCycle
        self.commandedSpeed = commandedSpeed
        self.measuredSpeed = measuredSpeed
        self.fanOffTime = fanOffTime
        self.fanOnTime = fanOnTime
    }
}

extension EngineFanStatus {

    private enum Constants {
        static let DATA_LENGTH = 12
        static let FAN_STATE_OFFSET = 0
        static let DUTY_CYCLE_OFFSET = 1
        static let COMMANDED_SPEED_OFFSET = 2
        static let MEASURED_SPEED_OFFSET = 3
        static let FAN_OFF_TIME_OFFSET = 4
        static let FAN_ON_TIME_OFFSET = 8
    }

    static func fromData(_ data: Data) -> EngineFanStatus {
        guard data.count >= Constants.DATA_LENGTH else { return defaultValues() }

        let fanStateByte = data[data.startIndex + Constants.FAN_STATE_OFFSET]
        let fanState = EngineFanState(rawValue: fanStateByte) ?? .powerDown

        let dutyCycle = data[data.startIndex + Constants.DUTY_CYCLE_OFFSET]
        let commandedSpeed = data[data.startIndex + Constants.COMMANDED_SPEED_OFFSET]
        let measuredSpeed = data[data.startIndex + Constants.MEASURED_SPEED_OFFSET]

        let fanOffTimeData = data.subdata(in: (data.startIndex + Constants.FAN_OFF_TIME_OFFSET)..<(data.startIndex + Constants.FAN_ON_TIME_OFFSET))
        let fanOffTime = fanOffTimeData.withUnsafeBytes { $0.load(as: UInt32.self) }

        let fanOnTimeData = data.subdata(in: (data.startIndex + Constants.FAN_ON_TIME_OFFSET)..<(data.startIndex + Constants.DATA_LENGTH))
        let fanOnTime = fanOnTimeData.withUnsafeBytes { $0.load(as: UInt32.self) }

        return .init(fanState: fanState,
                     dutyCycle: dutyCycle,
                     commandedSpeed: commandedSpeed,
                     measuredSpeed: measuredSpeed,
                     fanOffTime: fanOffTime,
                     fanOnTime: fanOnTime)
    }

    static func defaultValues() -> EngineFanStatus {
        return .init(fanState: .powerDown,
                     dutyCycle: 0,
                     commandedSpeed: 0,
                     measuredSpeed: 0,
                     fanOffTime: 0,
                     fanOnTime: 0)
    }
}
