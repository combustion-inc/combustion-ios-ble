//  EngineStatus.swift
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

/// Message containing Engine status information.
public struct EngineStatus: DeviceAccessoryStatus {

    /// Engine serial number
    public let serialNumber: String

    /// Session ID for active session
    public let sessionID: UInt32

    /// Number of milliseconds between each log
    public let samplePeriod: UInt16

    /// Minimum sequence number of records in engine's memory.
    public let minSequenceNumber: UInt32

    /// Maximum sequence number of records in engine's memory.
    public let maxSequenceNumber: UInt32

    /// Battery status (level and charging state)
    public let batteryStatus: EngineBatteryStatus

    /// Current temperature set point (in Celsius)
    public let temperatureSetPoint: Double

    /// Current control temperature (in Celsius)
    public let controlTemperature: Double

    /// Type of control device (probe or gauge)
    public let controlDeviceType: ProductType

    /// Probe serial number, if control device type is probe
    public let probeSerialNumber: UInt32?

    /// Node serial number, if control device type is node (gauge)
    public let nodeSerialNumber: String?

    /// Engine status flags
    public let statusFlags: EngineStatusFlags

    /// Fan status
    public let fanStatus: EngineFanStatus

    /// Controller status.
    public let controllerStatus: EngineControllerStatus

    /// Hop count decoded from the network information byte.
    public let hopCount: HopCount

    /// Raw knob voltage converted to volts.
    public let knobVoltage: Double

    /// Raw knob angle converted to degrees.
    public let knobAngle: Double

    public init(serialNumber: String,
                sessionID: UInt32,
                samplePeriod: UInt16,
                minSequenceNumber: UInt32,
                maxSequenceNumber: UInt32,
                batteryStatus: EngineBatteryStatus,
                temperatureSetPoint: Double,
                controlTemperature: Double,
                controlDeviceType: ProductType,
                probeSerialNumber: UInt32?,
                nodeSerialNumber: String?,
                statusFlags: EngineStatusFlags,
                fanStatus: EngineFanStatus,
                controllerStatus: EngineControllerStatus = .defaultValues(),
                hopCount: HopCount = .hop1,
                knobVoltage: Double = 0.0,
                knobAngle: Double = 0.0) {
        self.serialNumber = serialNumber
        self.sessionID = sessionID
        self.samplePeriod = samplePeriod
        self.minSequenceNumber = minSequenceNumber
        self.maxSequenceNumber = maxSequenceNumber
        self.batteryStatus = batteryStatus
        self.temperatureSetPoint = temperatureSetPoint
        self.controlTemperature = controlTemperature
        self.controlDeviceType = controlDeviceType
        self.probeSerialNumber = probeSerialNumber
        self.nodeSerialNumber = nodeSerialNumber
        self.statusFlags = statusFlags
        self.fanStatus = fanStatus
        self.controllerStatus = controllerStatus
        self.hopCount = hopCount
        self.knobVoltage = knobVoltage
        self.knobAngle = knobAngle
    }
}

extension EngineStatus {
    private enum Constants {
        static let SERIAL_NUMBER_RANGE = 10..<20
        static let SESSION_ID_RANGE = 20..<24
        static let SAMPLE_PERIOD_RANGE = 24..<26
        static let LOG_RANGE = 26..<34
        static let BATTERY_STATUS_RANGE = 34..<37
        static let TEMPERATURE_SET_POINT_RANGE = 37..<39
        static let CONTROL_TEMPERATURE_RANGE = 39..<41
        static let CONTROL_DEVICE_TYPE_RANGE = 41..<42
        static let PROBE_SERIAL_RANGE = 42..<46
        static let NODE_SERIAL_RANGE = 42..<52
        // Note - 2 bytes of padding are here intentionally
        static let STATUS_FLAGS_RANGE = 54..<55
        static let FAN_STATUS_RANGE = 55..<67
        static let CONTROLLER_STATUS_RANGE = 67..<75
        static let NETWORK_INFO_RANGE = 75..<76
        static let KNOB_VOLTAGE_RANGE = 76..<78
        static let KNOB_ANGLE_RANGE = 78..<80

        static let MINIMUM_DATA_LENGTH = 80
    }

    init?(fromData data: Data) {
        guard data.count >= Constants.MINIMUM_DATA_LENGTH else { return nil }

        // Serial Number
        let serialRaw = data.subdata(in: Constants.SERIAL_NUMBER_RANGE)
        self.serialNumber = String(decoding: serialRaw, as: UTF8.self).trimmingCharacters(in: CharacterSet(["\0"]))

        // Session ID
        let sessionIDData = data.subdata(in: Constants.SESSION_ID_RANGE)
        self.sessionID = sessionIDData.withUnsafeBytes { $0.load(as: UInt32.self) }

        // Sample Period
        let samplePeriodData = data.subdata(in: Constants.SAMPLE_PERIOD_RANGE)
        self.samplePeriod = samplePeriodData.withUnsafeBytes { $0.load(as: UInt16.self) }

        // Log Range (8 bytes: min 4 + max 4)
        let logRangeData = data.subdata(in: Constants.LOG_RANGE)
        let logRange: UInt64 = logRangeData.withUnsafeBytes { $0.load(as: UInt64.self) }
        self.minSequenceNumber = UInt32(logRange & 0xFFFFFFFF)
        self.maxSequenceNumber = UInt32(logRange >> 32)

        // Battery Status
        let batteryData = data.subdata(in: Constants.BATTERY_STATUS_RANGE)
        self.batteryStatus = EngineBatteryStatus.fromData(batteryData)

        // Temperature Set Point (13-bit packed, 0.1°C resolution, -20 offset)
        let setPointData = data.subdata(in: Constants.TEMPERATURE_SET_POINT_RANGE)
        let setPointRaw = setPointData.withUnsafeBytes { $0.load(as: UInt16.self) }
        let setPointValue = setPointRaw & 0x1FFF
        self.temperatureSetPoint = Double(setPointValue) * 0.1 - 20.0

        // Control Temperature (13-bit packed, 0.1°C resolution, -20 offset)
        let controlTempData = data.subdata(in: Constants.CONTROL_TEMPERATURE_RANGE)
        let controlTempRaw = controlTempData.withUnsafeBytes { $0.load(as: UInt16.self) }
        let controlTempValue = controlTempRaw & 0x1FFF
        self.controlTemperature = Double(controlTempValue) * 0.1 - 20.0
        
        // Control Device Type
        let controlDeviceTypeByte = data[Constants.CONTROL_DEVICE_TYPE_RANGE.lowerBound]
        self.controlDeviceType = ProductType(rawValue: controlDeviceTypeByte) ?? .unknown

        // Control Device Serial Number (depends on type)
        if self.controlDeviceType == .probe {
            let probeSerialData = data.subdata(in: Constants.PROBE_SERIAL_RANGE)
            self.probeSerialNumber = probeSerialData.withUnsafeBytes { $0.load(as: UInt32.self) }
            self.nodeSerialNumber = nil
        } else if self.controlDeviceType == .gauge {
            let nodeSerialRaw = data.subdata(in: Constants.NODE_SERIAL_RANGE)
            self.nodeSerialNumber = String(decoding: nodeSerialRaw, as: UTF8.self).trimmingCharacters(in: CharacterSet(["\0"]))
            self.probeSerialNumber = nil
        } else {
            self.probeSerialNumber = nil
            self.nodeSerialNumber = nil
        }

        // Engine Status Flags
        let statusFlagsByte = data[Constants.STATUS_FLAGS_RANGE.lowerBound]
        self.statusFlags = EngineStatusFlags.fromByte(statusFlagsByte)

        // Fan Status
        let fanStatusData = data.subdata(in: Constants.FAN_STATUS_RANGE)
        self.fanStatus = EngineFanStatus.fromData(fanStatusData)

        let controllerStatusData = data.subdata(in: Constants.CONTROLLER_STATUS_RANGE)
        self.controllerStatus = EngineControllerStatus.fromData(controllerStatusData)

        // Network Information
        let networkInfoByte = data[Constants.NETWORK_INFO_RANGE.lowerBound]
        self.hopCount = HopCount.from(networkInfoByte: networkInfoByte)

        // Knob Voltage (millivolts encoded as UInt16)
        let knobVoltageData = data.subdata(in: Constants.KNOB_VOLTAGE_RANGE)
        let knobVoltageRaw = knobVoltageData.withUnsafeBytes { $0.load(as: UInt16.self) }
        self.knobVoltage = Double(knobVoltageRaw) / 1000.0

        // Knob Angle (tenths of degrees encoded as UInt16)
        let knobAngleData = data.subdata(in: Constants.KNOB_ANGLE_RANGE)
        let knobAngleRaw = knobAngleData.withUnsafeBytes { $0.load(as: UInt16.self) }
        self.knobAngle = Double(knobAngleRaw) / 10.0
    }
}

extension EngineStatus {
    /// Decodes a 13-bit packed temperature value to Celsius
    static func decodeTemperature(from rawValue: UInt16) -> Double {
        let value = rawValue & 0x1FFF
        return Double(value) * 0.1 - 20.0
    }

    /// Encodes a temperature in Celsius to a 13-bit packed value
    static func encodeTemperature(_ celsius: Double) -> UInt16 {
        let value = Int((celsius + 20.0) / 0.1)
        return UInt16(max(0, min(value, 0x1FFF)))
    }
}
