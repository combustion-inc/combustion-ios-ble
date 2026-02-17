//
//  SimulatedMeatNetNode.swift
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

public class SimulatedGauge: MeatNetNode {
    
    public init() {
        let advertising = GaugeAdvertisingData(fakeSerial: "FAKEGAUGE01",
                                               fakeTemperatures: GaugeTemperature.withRandomData())
        super.init(advertising, isConnectable: true, RSSI: SimulatedProbe.randomeRSSI(), identifier: UUID())
        
        self.accessory = GrillGauge(parent: self, advertising: advertising)
        self.dfuType = .gauge
                
        firmareVersion = "v3.0.0"
        hardwareRevision = "v0.31-A1"
        
        // Create timer to update probe with fake advertising packets
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.updateFakeAdvertising()
        }
        
        // Create timer to update probe with fake status notifications
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateFakeStatus()
        }
        
        self.connectionState = .connected
        
        // Set fake session information
        let fakeSessionInfo = SessionInformation(sessionID: UInt32.random(in: 0..<UInt32.max), samplePeriod: 5000)
        (accessory as? GrillGauge)?.updateWithSessionInformation(fakeSessionInfo)
    }
    
    public override var name: String {
        var nameStr = super.name
        nameStr.removeLast(4)
        return String(format: "SIM-\(nameStr)")
    }
    
    static func randomeRSSI() -> NSNumber {
        return NSNumber(value: Int.random(in: -80 ..< -40))
    }
    
    private func updateFakeAdvertising() {
        let advertising = GaugeAdvertisingData(fakeSerial: "FAKEGAUGE01",
                                          fakeTemperatures: GaugeTemperature.withRandomData())

        updateWithAdvertising(advertising, isConnectable: true, RSSI: SimulatedProbe.randomeRSSI())
        accessory?.updateWithAdvertising(advertising)
    }
    
    private func updateFakeStatus() {
        guard let accessory = accessory as? GrillGauge else { return }
        guard connectionState == .connected else { return }
        
        let firstSeq = accessory.deviceDataLogs.first?.dataPoints.first?.sequenceNum ?? 0

        let lastSequence: UInt32

        if let last = accessory.deviceDataLogs.first?.dataPoints.last?.sequenceNum {
            lastSequence = last + 1
        }
        else {
            lastSequence = 0
        }
        
        let gaugeStatus = GaugeStatus( serialNumber: accessory.serialNumber,
                                       sessionID: 1,
                                       minSequenceNumber: firstSeq,
                                       maxSequenceNumber: lastSequence,
                                       temperature: GaugeTemperature.withRandomData(),
                                       alarmStatus: .defaultValues(),
                                       status: .defaultValues(),
                                       samplePeriod: 5000,
                                       newRecordFlag: false)
        
        accessory.updateDeviceStatus(deviceStatus: gaugeStatus)
    }
}

public class SimulatedEngine: MeatNetNode {

    private static let sampleData: [EngineSampleRecord] = EngineSampleData.load()
    private var sampleIndex = 0
    private var basicSequenceNumber: UInt32 = 0
    private var basicFanDutyCycle: UInt8 = 0
    private var basicFanTicksRemaining = 0
    private let samplePeriodSeconds: TimeInterval
    private let simulatedSessionId: UInt32
    private var controlDeviceTypeOverride: ProductType?
    private var controlDeviceSerialOverride: String?
    private var temperatureSetPointOverride: Double?
    private let basicStatusOnly: Bool

    private enum Constants {
        static let defaultSerialNumber = "FAKEENGIN01"
        static let defaultTemperatureSetPoint = 225.0
        static let defaultSamplePeriodMs: UInt16 = 5000
    }

    private struct BasicFanPhase {
        let dutyCycle: UInt8
        let durationRange: ClosedRange<Int>
    }

    public init(controlDeviceTypeOverride: ProductType? = nil,
                controlDeviceSerialOverride: String? = nil) {
        self.controlDeviceTypeOverride = controlDeviceTypeOverride
        self.controlDeviceSerialOverride = controlDeviceSerialOverride
        self.basicStatusOnly = controlDeviceTypeOverride == nil
        let initialRecord = basicStatusOnly ? nil : SimulatedEngine.sampleData.first
        self.simulatedSessionId = UInt32.random(in: 0..<UInt32.max)
        let serialNumber = Constants.defaultSerialNumber
        let setPoint = initialRecord?.temperatureSetPoint ?? Constants.defaultTemperatureSetPoint
        let samplePeriodMs = basicStatusOnly ? Constants.defaultSamplePeriodMs : (initialRecord?.samplePeriodMs ?? Constants.defaultSamplePeriodMs)
        self.samplePeriodSeconds = TimeInterval(samplePeriodMs) / 1000.0

        let advertising = EngineAdvertisingData(fakeSerial: serialNumber,
                                                fakeTemperatureSetPoint: setPoint)
        super.init(advertising, isConnectable: true, RSSI: SimulatedProbe.randomeRSSI(), identifier: UUID())

        self.accessory = Engine(parent: self, advertising: advertising)
        self.dfuType = .engine

        firmareVersion = "v1.0.0"
        hardwareRevision = "v0.1-A1"

        Timer.scheduledTimer(withTimeInterval: samplePeriodSeconds, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.basicStatusOnly {
                self.publishBasicStatus()
            }
            else {
                self.advanceSample()
            }
        }

        self.connectionState = .connected

        let samplePeriod = initialRecord?.samplePeriodMs ?? Constants.defaultSamplePeriodMs
        let fakeSessionInfo = SessionInformation(sessionID: simulatedSessionId, samplePeriod: samplePeriod)
        (accessory as? Engine)?.updateWithSessionInformation(fakeSessionInfo)
    }

    public override var name: String {
        var nameStr = super.name
        nameStr.removeLast(4)
        return String(format: "SIM-\(nameStr)")
    }

    public func setSimulatedControlDevice(probeSerialNumber: UInt32) {
        controlDeviceTypeOverride = .probe
        controlDeviceSerialOverride = "\(probeSerialNumber)"
        basicFanTicksRemaining = 0

        if basicStatusOnly {
            publishBasicStatus()
        }
    }

    public func setSimulatedControlDevice(gaugeSerialNumber: String) {
        controlDeviceTypeOverride = .gauge
        controlDeviceSerialOverride = gaugeSerialNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        basicFanTicksRemaining = 0

        if basicStatusOnly {
            publishBasicStatus()
        }
    }

    public func setSimulatedTargetTemperature(_ temperatureCelsius: Double) {
        temperatureSetPointOverride = temperatureCelsius

        if basicStatusOnly {
            publishBasicStatus()
        }
    }

    private func advanceSample() {
        guard !SimulatedEngine.sampleData.isEmpty else { return }
        guard let accessory = accessory as? Engine else { return }
        guard connectionState == .connected else { return }

        let record = SimulatedEngine.sampleData[sampleIndex]
        sampleIndex = (sampleIndex + 1) % SimulatedEngine.sampleData.count

        let temperatureSetPoint = temperatureSetPointOverride ?? record.temperatureSetPoint
        let advertising = EngineAdvertisingData(fakeSerial: record.serialNumber,
                                                fakeTemperatureSetPoint: temperatureSetPoint)
        updateWithAdvertising(advertising, isConnectable: true, RSSI: SimulatedProbe.randomeRSSI())
        accessory.updateWithAdvertising(advertising)

        let controlDeviceType = controlDeviceTypeOverride ?? record.controlDeviceType
        let (probeSerialNumber, nodeSerialNumber) = resolveControlDeviceSerials(type: controlDeviceType,
                                                                                 record: record)

        let engineStatus = EngineStatus(serialNumber: accessory.serialNumber,
                                        sessionID: simulatedSessionId,
                                        samplePeriod: record.samplePeriodMs,
                                        minSequenceNumber: record.minSequence,
                                        maxSequenceNumber: record.maxSequence,
                                        batteryStatus: record.batteryStatus,
                                        temperatureSetPoint: temperatureSetPoint,
                                        controlTemperature: resolvedControlTemperature(controlDeviceType: controlDeviceType,
                                                                                      probeSerialNumber: probeSerialNumber,
                                                                                      nodeSerialNumber: nodeSerialNumber),
                                        controlDeviceType: controlDeviceType,
                                        probeSerialNumber: probeSerialNumber,
                                        nodeSerialNumber: nodeSerialNumber,
                                        statusFlags: record.statusFlags,
                                        fanStatus: record.fanStatus)

        accessory.updateDeviceStatus(deviceStatus: engineStatus)
    }

    private func publishBasicStatus() {
        guard let accessory = accessory as? Engine else { return }
        guard connectionState == .connected else { return }

        let sequence = basicSequenceNumber
        basicSequenceNumber += 1
        let basicControlDevice = resolveBasicControlDevice()

        let temperatureSetPoint = temperatureSetPointOverride ?? Constants.defaultTemperatureSetPoint
        let engineStatus = EngineStatus(serialNumber: accessory.serialNumber,
                                        sessionID: simulatedSessionId,
                                        samplePeriod: Constants.defaultSamplePeriodMs,
                                        minSequenceNumber: sequence,
                                        maxSequenceNumber: sequence,
                                        batteryStatus: EngineBatteryStatus.defaultValues(),
                                        temperatureSetPoint: temperatureSetPoint,
                                        controlTemperature: resolvedControlTemperature(controlDeviceType: basicControlDevice.type,
                                                                                      probeSerialNumber: basicControlDevice.probeSerialNumber,
                                                                                      nodeSerialNumber: basicControlDevice.nodeSerialNumber),
                                        controlDeviceType: basicControlDevice.type,
                                        probeSerialNumber: basicControlDevice.probeSerialNumber,
                                        nodeSerialNumber: basicControlDevice.nodeSerialNumber,
                                        statusFlags: EngineStatusFlags(appMode: false,
                                                                       controlDeviceConnected: basicControlDevice.type != .unknown,
                                                                       lidOpen: false,
                                                                       fixedSpeed: false),
                                        fanStatus: resolveBasicFanStatus(controlDeviceConnected: basicControlDevice.type != .unknown))

        accessory.updateDeviceStatus(deviceStatus: engineStatus)
    }

    private func resolvedControlTemperature(controlDeviceType: ProductType,
                                            probeSerialNumber: UInt32?,
                                            nodeSerialNumber: String?) -> Double {
        guard probeSerialNumber != nil || (nodeSerialNumber?.isEmpty == false) else {
            return -20
        }

        return ambientTemperatureForControlDevice(type: controlDeviceType,
                                                  probeSerialNumber: probeSerialNumber,
                                                  nodeSerialNumber: nodeSerialNumber) ?? -20
    }

    private func ambientTemperatureForControlDevice(type: ProductType,
                                                    probeSerialNumber: UInt32?,
                                                    nodeSerialNumber: String?) -> Double? {
        let deviceManager = DeviceManager.shared

        switch type {
        case .probe:
            guard let probeSerialNumber,
                  let probe = deviceManager.devices[Probe.serialNumberToString(probeSerialNumber)] as? Probe else {
                return nil
            }
            return probe.virtualTemperatures?.ambientTemperature
        case .gauge:
            guard let nodeSerialNumber,
                  let gauge = deviceManager.accessories[nodeSerialNumber] as? GrillGauge else {
                return nil
            }
            return gauge.currentTemperature?.value
        default:
            return nil
        }
    }

    private func resolveBasicFanStatus(controlDeviceConnected: Bool) -> EngineFanStatus {
        guard controlDeviceConnected else {
            basicFanDutyCycle = 0
            basicFanTicksRemaining = 0
            return EngineFanStatus(fanState: .fanOff,
                                   dutyCycle: 0,
                                   commandedSpeed: 0,
                                   measuredSpeed: 0,
                                   fanOffTime: UInt32(Constants.defaultSamplePeriodMs),
                                   fanOnTime: 0)
        }

        if basicFanTicksRemaining <= 0 {
            let phases: [BasicFanPhase] = [
                .init(dutyCycle: 0, durationRange: 2...6),
                .init(dutyCycle: 35, durationRange: 3...7),
                .init(dutyCycle: 98, durationRange: 2...5)
            ]

            var selected = phases.randomElement() ?? phases[0]
            if selected.dutyCycle == basicFanDutyCycle,
               let alternative = phases.filter({ $0.dutyCycle != basicFanDutyCycle }).randomElement() {
                selected = alternative
            }

            basicFanDutyCycle = selected.dutyCycle
            basicFanTicksRemaining = Int.random(in: selected.durationRange)
        }

        basicFanTicksRemaining = max(0, basicFanTicksRemaining - 1)

        if basicFanDutyCycle == 0 {
            return EngineFanStatus(fanState: .fanOff,
                                   dutyCycle: 0,
                                   commandedSpeed: 0,
                                   measuredSpeed: 0,
                                   fanOffTime: UInt32(Constants.defaultSamplePeriodMs),
                                   fanOnTime: 0)
        }

        let commandedSpeed = basicFanDutyCycle
        let measuredSpeed = UInt8(max(0, min(100, Int(commandedSpeed) + Int.random(in: -4...4))))

        return EngineFanStatus(fanState: .fanOn,
                               dutyCycle: basicFanDutyCycle,
                               commandedSpeed: commandedSpeed,
                               measuredSpeed: measuredSpeed,
                               fanOffTime: 0,
                               fanOnTime: UInt32(Constants.defaultSamplePeriodMs))
    }

    private func resolveBasicControlDevice() -> (type: ProductType, probeSerialNumber: UInt32?, nodeSerialNumber: String?) {
        switch controlDeviceTypeOverride {
        case .probe:
            guard let serial = controlDeviceSerialOverride,
                  let probeSerial = Self.parseProbeSerialNumber(serial) else {
                return (.unknown, nil, nil)
            }
            return (.probe, probeSerial, nil)
        case .gauge:
            guard let serial = controlDeviceSerialOverride,
                  !serial.isEmpty else {
                return (.unknown, nil, nil)
            }
            return (.gauge, nil, serial)
        default:
            return (.unknown, nil, nil)
        }
    }

    private func resolveControlDeviceSerials(type: ProductType,
                                             record: EngineSampleRecord) -> (UInt32?, String?) {
        switch type {
        case .probe:
            let probeSerial = controlDeviceSerialOverride.flatMap(Self.parseProbeSerialNumber) ??
                              record.probeSerialNumber
            return (probeSerial, nil)
        case .gauge:
            let nodeSerial = controlDeviceSerialOverride ?? record.nodeSerialNumber
            return (nil, nodeSerial)
        default:
            return (nil, nil)
        }
    }

    private static func parseProbeSerialNumber(_ serial: String) -> UInt32? {
        let trimmed = serial.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = UInt32(trimmed) {
            return value
        }
        return UInt32(trimmed, radix: 16)
    }
}
