//  LoggedEngineDataPoint.swift
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

public class LoggedEngineDataPoint: LoggedDeviceDataPoint {

    public let temperatureSetPoint: Double?
    public let controlTemperature: Double?
    public let statusFlags: EngineStatusFlags
    public let fanStatus: EngineFanStatus

    public override var deviceType: LoggedDeviceDataPointType {
        return .engine
    }

    public init(sequenceNum: UInt32,
                temperatureSetPoint: Double?,
                controlTemperature: Double?,
                statusFlags: EngineStatusFlags,
                fanStatus: EngineFanStatus) {
        self.temperatureSetPoint = temperatureSetPoint
        self.controlTemperature = controlTemperature
        self.statusFlags = statusFlags
        self.fanStatus = fanStatus
        super.init(sequenceNum: sequenceNum)
    }

    public convenience init(sequenceNum: UInt32,
                            temperatureSetPoint: Double?,
                            controlTemperature: Double?,
                            fanStatus: EngineFanStatus) {
        self.init(sequenceNum: sequenceNum,
                  temperatureSetPoint: temperatureSetPoint,
                  controlTemperature: controlTemperature,
                  statusFlags: .defaultValues(),
                  fanStatus: fanStatus)
    }

    override public func temperatureForChannelIndex(_ index: Int) -> Double? {
        if index == 0 {
            return controlTemperature
        }
        else if index == 1 {
            return statusFlags.fixedSpeed ? nil : temperatureSetPoint
        }
        else {
            return nil
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case temperatureSetPoint
        case controlTemperature
        case statusFlags
        case fanStatus
    }

    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(temperatureSetPoint, forKey: .temperatureSetPoint)
        try container.encode(controlTemperature, forKey: .controlTemperature)
        try container.encode(statusFlags, forKey: .statusFlags)
        try container.encode(fanStatus, forKey: .fanStatus)
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.temperatureSetPoint = try container.decodeIfPresent(Double.self, forKey: .temperatureSetPoint)
        self.controlTemperature = try container.decodeIfPresent(Double.self, forKey: .controlTemperature)
        self.statusFlags = try container.decodeIfPresent(EngineStatusFlags.self, forKey: .statusFlags) ?? .defaultValues()
        self.fanStatus = try container.decode(EngineFanStatus.self, forKey: .fanStatus)
        try super.init(from: decoder)
    }
}

extension LoggedEngineDataPoint {

    public static func fromDeviceStatus(deviceStatus: EngineStatus) -> LoggedEngineDataPoint {
        return LoggedEngineDataPoint(sequenceNum: deviceStatus.maxSequenceNumber,
                                     temperatureSetPoint: deviceStatus.temperatureSetPoint,
                                     controlTemperature: deviceStatus.controlTemperature,
                                     statusFlags: deviceStatus.statusFlags,
                                     fanStatus: deviceStatus.fanStatus)
    }

    static func fromLogResponse(logResponse: NodeEngineReadLogsResponse, status: EngineStatus?) -> LoggedEngineDataPoint {
        let temperatureSetPoint = status?.temperatureSetPoint ?? 0.0
        let controlTemperature = status?.controlTemperature ?? 0.0
        let statusFlags = status?.statusFlags ?? .defaultValues()
        let fanStatus = status?.fanStatus ?? EngineFanStatus.defaultValues()

        return LoggedEngineDataPoint(sequenceNum: logResponse.sequenceNumber,
                                     temperatureSetPoint: temperatureSetPoint,
                                     controlTemperature: controlTemperature,
                                     statusFlags: statusFlags,
                                     fanStatus: fanStatus)
    }

    static func fromLogResponse(logResponse: NodeEngineReadLogsResponse) -> LoggedEngineDataPoint {
        return LoggedEngineDataPoint(sequenceNum: logResponse.sequenceNumber,
                                     temperatureSetPoint: logResponse.temperatureSetPoint,
                                     controlTemperature: logResponse.controlTemperature,
                                     statusFlags: logResponse.statusFlags,
                                     fanStatus: logResponse.fanStatus)
    }
}
