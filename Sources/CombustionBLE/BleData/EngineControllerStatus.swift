//  EngineControllerStatus.swift
/*--
MIT License

Copyright (c) 2026 Combustion Inc.

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

public enum EngineControllerState: UInt8, Codable {
    case idle = 0
    case startup = 1
    case probe = 2
    case observe = 3
    case rest = 4
}

public struct EngineControllerFlags: Equatable, Codable {
    public let reachedSetpoint: Bool
    public let maintenanceMode: Bool

    public init(reachedSetpoint: Bool, maintenanceMode: Bool) {
        self.reachedSetpoint = reachedSetpoint
        self.maintenanceMode = maintenanceMode
    }
}

extension EngineControllerFlags {
    static func fromByte(_ byte: UInt8) -> EngineControllerFlags {
        .init(reachedSetpoint: (byte & 0x01) != 0,
              maintenanceMode: (byte & 0x02) != 0)
    }

    static func defaultValues() -> EngineControllerFlags {
        .init(reachedSetpoint: false, maintenanceMode: false)
    }
}

public struct EngineControllerStatus: Equatable, Codable {
    public let state: EngineControllerState
    public let responseCoefficient: Double
    public let cyclesCompleted: UInt8
    public let flags: EngineControllerFlags
    public let smoothedTemperature: Double
    public let timeToPeakSeconds: UInt8
    public let driftRate: Double

    public init(state: EngineControllerState,
                responseCoefficient: Double,
                cyclesCompleted: UInt8,
                flags: EngineControllerFlags,
                smoothedTemperature: Double,
                timeToPeakSeconds: UInt8,
                driftRate: Double) {
        self.state = state
        self.responseCoefficient = responseCoefficient
        self.cyclesCompleted = cyclesCompleted
        self.flags = flags
        self.smoothedTemperature = smoothedTemperature
        self.timeToPeakSeconds = timeToPeakSeconds
        self.driftRate = driftRate
    }
}

extension EngineControllerStatus {
    private enum Constants {
        static let DATA_LENGTH = 8
    }

    static func fromData(_ data: Data) -> EngineControllerStatus {
        guard data.count >= Constants.DATA_LENGTH else { return defaultValues() }

        let state = EngineControllerState(rawValue: data[data.startIndex]) ?? .idle
        let responseCoefficient = Double(data[data.startIndex + 1]) / 500.0
        let cyclesCompleted = data[data.startIndex + 2]
        let flags = EngineControllerFlags.fromByte(data[data.startIndex + 3])

        let smoothedTemperatureData = data.subdata(in: (data.startIndex + 4)..<(data.startIndex + 6))
        let smoothedTemperatureRaw = smoothedTemperatureData.withUnsafeBytes { $0.load(as: UInt16.self) }
        let smoothedTemperature = Double(smoothedTemperatureRaw) / 10.0

        let timeToPeakSeconds = data[data.startIndex + 6]
        let driftRateRaw = Int8(bitPattern: data[data.startIndex + 7])
        let driftRate = Double(driftRateRaw) / 1000.0

        return .init(state: state,
                     responseCoefficient: responseCoefficient,
                     cyclesCompleted: cyclesCompleted,
                     flags: flags,
                     smoothedTemperature: smoothedTemperature,
                     timeToPeakSeconds: timeToPeakSeconds,
                     driftRate: driftRate)
    }

    public static func defaultValues() -> EngineControllerStatus {
        .init(state: .idle,
              responseCoefficient: 0.0,
              cyclesCompleted: 0,
              flags: .defaultValues(),
              smoothedTemperature: 0.0,
              timeToPeakSeconds: 0,
              driftRate: 0.0)
    }
}
