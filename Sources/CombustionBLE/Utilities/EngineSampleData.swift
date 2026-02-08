//  EngineSampleData.swift
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

struct EngineSampleRecord {
    let serialNumber: String
    let sessionId: UInt32
    let samplePeriodMs: UInt16
    let minSequence: UInt32
    let maxSequence: UInt32
    let batteryStatus: EngineBatteryStatus
    let temperatureSetPoint: Double
    let controlTemperature: Double
    let controlDeviceType: ProductType
    let probeSerialNumber: UInt32?
    let nodeSerialNumber: String?
    let statusFlags: EngineStatusFlags
    let fanStatus: EngineFanStatus
    let hopCount: HopCount?
}

enum EngineSampleData {
    static func load() -> [EngineSampleRecord] {
        guard let url = Bundle.module.url(forResource: "EngineSampleData", withExtension: "csv"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        let lines = content.split(whereSeparator: \.isNewline)
        guard let headerLine = lines.first else { return [] }

        let headers = headerLine.split(separator: ",").map { String($0) }
        var headerIndex: [String: Int] = [:]
        for (index, header) in headers.enumerated() {
            headerIndex[header] = index
        }

        func value(_ parts: [Substring], _ name: String) -> String? {
            guard let index = headerIndex[name], index < parts.count else { return nil }
            return String(parts[index])
        }

        var records: [EngineSampleRecord] = []
        for line in lines.dropFirst() {
            let parts = line.split(separator: ",")
            guard !parts.isEmpty else { continue }

            let serialNumber = value(parts, "node_serial_number") ?? "ENGINE"
            let sessionId = UInt32(value(parts, "session_id") ?? "") ?? 0
            let samplePeriodMs = UInt16(value(parts, "sample_period") ?? "") ?? 5000
            let minSequence = UInt32(value(parts, "min_log_sequence") ?? "") ?? 0
            let maxSequence = UInt32(value(parts, "max_log_sequence") ?? "") ?? 0

            let batteryLevelRaw = value(parts, "battery_level") ?? ""
            let batteryStateRaw = value(parts, "battery_state") ?? ""
            let batteryStatus = EngineBatteryStatus(level: parseBatteryLevel(batteryLevelRaw),
                                                    state: parseBatteryState(batteryStateRaw))

            let temperatureSetPoint = Double(value(parts, "temperature_setpoint") ?? "") ?? 0.0
            let controlTemperature = Double(value(parts, "control_temperature") ?? "") ?? 0.0
            let controlDeviceType = parseProductType(value(parts, "control_device_type") ?? "")
            let controlDeviceSerial = value(parts, "control_device_serial") ?? ""

            let appMode = parseBool(value(parts, "app_mode"))
            let controlDeviceConnected = parseBool(value(parts, "control_device_connected"))
            let lidOpen = parseBool(value(parts, "lid_open"))
            let fixedSpeed = parseBool(value(parts, "fixed_speed"))
            let statusFlags = EngineStatusFlags(appMode: appMode,
                                                controlDeviceConnected: controlDeviceConnected,
                                                lidOpen: lidOpen,
                                                fixedSpeed: fixedSpeed)

            let fanStateRaw = value(parts, "fan_state") ?? ""
            let fanStatus = EngineFanStatus(fanState: parseFanState(fanStateRaw),
                                            dutyCycle: UInt8(value(parts, "fan_duty_cycle") ?? "") ?? 0,
                                            commandedSpeed: UInt8(value(parts, "fan_commanded_speed") ?? "") ?? 0,
                                            measuredSpeed: UInt8(value(parts, "fan_measured_speed") ?? "") ?? 0,
                                            fanOffTime: UInt32(value(parts, "fan_off_time") ?? "") ?? 0,
                                            fanOnTime: UInt32(value(parts, "fan_on_time") ?? "") ?? 0)

            let hopCountRaw = value(parts, "hop_count")
            let hopCount = hopCountRaw.flatMap { UInt8($0) }.flatMap { HopCount(rawValue: $0) }

            let probeSerialNumber: UInt32?
            let nodeSerialNumber: String?
            if controlDeviceType == .probe {
                probeSerialNumber = parseSerialNumber(controlDeviceSerial)
                nodeSerialNumber = nil
            } else if controlDeviceType == .gauge {
                probeSerialNumber = nil
                nodeSerialNumber = controlDeviceSerial
            } else {
                probeSerialNumber = nil
                nodeSerialNumber = nil
            }

            records.append(.init(serialNumber: serialNumber,
                                 sessionId: sessionId,
                                 samplePeriodMs: samplePeriodMs,
                                 minSequence: minSequence,
                                 maxSequence: maxSequence,
                                 batteryStatus: batteryStatus,
                                 temperatureSetPoint: temperatureSetPoint,
                                 controlTemperature: controlTemperature,
                                 controlDeviceType: controlDeviceType,
                                 probeSerialNumber: probeSerialNumber,
                                 nodeSerialNumber: nodeSerialNumber,
                                 statusFlags: statusFlags,
                                 fanStatus: fanStatus,
                                 hopCount: hopCount))
        }

        return records
    }

    private static func parseBool(_ raw: String?) -> Bool {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return false }
        return raw == "true" || raw == "1" || raw == "yes"
    }

    private static func parseBatteryLevel(_ raw: String) -> EngineBatteryLevel {
        switch raw.uppercased() {
        case "LOW":
            return .low
        case "CRITICAL":
            return .critical
        default:
            return .ok
        }
    }

    private static func parseBatteryState(_ raw: String) -> EngineBatteryState {
        switch raw.uppercased() {
        case "CHARGING":
            return .charging
        case "FULLY_CHARGED":
            return .fullyCharged
        default:
            return .notCharging
        }
    }

    private static func parseProductType(_ raw: String) -> ProductType {
        switch raw.uppercased() {
        case "PROBE":
            return .probe
        case "GAUGE":
            return .gauge
        case "ENGINE":
            return .engine
        default:
            return .unknown
        }
    }

    private static func parseFanState(_ raw: String) -> EngineFanState {
        switch raw.uppercased() {
        case "FAN_ON":
            return .fanOn
        case "FAN_OFF":
            return .fanOff
        case "POWER_DOWN":
            return .powerDown
        case "PAUSED":
            return .paused
        case "LID_OPEN":
            return .lidOpen
        default:
            if let value = UInt8(raw), let state = EngineFanState(rawValue: value) {
                return state
            }
            return .powerDown
        }
    }

    private static func parseSerialNumber(_ raw: String) -> UInt32? {
        if let value = UInt32(raw) {
            return value
        }
        return UInt32(raw, radix: 16)
    }
}
