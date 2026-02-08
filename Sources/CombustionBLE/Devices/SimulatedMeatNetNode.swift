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
    private let samplePeriodSeconds: TimeInterval
    private let controlDeviceTypeOverride: ProductType?
    private let controlDeviceSerialOverride: String?

    public init(controlDeviceTypeOverride: ProductType? = nil,
                controlDeviceSerialOverride: String? = nil) {
        self.controlDeviceTypeOverride = controlDeviceTypeOverride
        self.controlDeviceSerialOverride = controlDeviceSerialOverride
        let initialRecord = SimulatedEngine.sampleData.first
        let serialNumber = initialRecord?.serialNumber ?? "FAKEENGIN01"
        let setPoint = initialRecord?.temperatureSetPoint ?? 225.0
        self.samplePeriodSeconds = TimeInterval(initialRecord?.samplePeriodMs ?? 5000) / 1000.0

        let advertising = EngineAdvertisingData(fakeSerial: serialNumber,
                                                fakeTemperatureSetPoint: setPoint)
        super.init(advertising, isConnectable: true, RSSI: SimulatedProbe.randomeRSSI(), identifier: UUID())

        self.accessory = Engine(parent: self, advertising: advertising)
        self.dfuType = .engine

        firmareVersion = "v1.0.0"
        hardwareRevision = "v0.1-A1"

        Timer.scheduledTimer(withTimeInterval: samplePeriodSeconds, repeats: true) { [weak self] _ in
            self?.advanceSample()
        }

        self.connectionState = .connected

        let sessionId = initialRecord?.sessionId ?? UInt32.random(in: 0..<UInt32.max)
        let samplePeriod = initialRecord?.samplePeriodMs ?? 5000
        let fakeSessionInfo = SessionInformation(sessionID: sessionId, samplePeriod: samplePeriod)
        (accessory as? Engine)?.updateWithSessionInformation(fakeSessionInfo)
    }

    public override var name: String {
        var nameStr = super.name
        nameStr.removeLast(4)
        return String(format: "SIM-\(nameStr)")
    }

    private func advanceSample() {
        guard !SimulatedEngine.sampleData.isEmpty else { return }
        guard let accessory = accessory as? Engine else { return }
        guard connectionState == .connected else { return }

        let record = SimulatedEngine.sampleData[sampleIndex]
        sampleIndex = (sampleIndex + 1) % SimulatedEngine.sampleData.count

        let advertising = EngineAdvertisingData(fakeSerial: record.serialNumber,
                                                fakeTemperatureSetPoint: record.temperatureSetPoint)
        updateWithAdvertising(advertising, isConnectable: true, RSSI: SimulatedProbe.randomeRSSI())
        accessory.updateWithAdvertising(advertising)

        let controlDeviceType = controlDeviceTypeOverride ?? record.controlDeviceType
        let (probeSerialNumber, nodeSerialNumber) = resolveControlDeviceSerials(type: controlDeviceType,
                                                                                 record: record)

        let engineStatus = EngineStatus(serialNumber: record.serialNumber,
                                        sessionID: record.sessionId,
                                        samplePeriod: record.samplePeriodMs,
                                        minSequenceNumber: record.minSequence,
                                        maxSequenceNumber: record.maxSequence,
                                        batteryStatus: record.batteryStatus,
                                        temperatureSetPoint: record.temperatureSetPoint,
                                        controlTemperature: record.controlTemperature,
                                        controlDeviceType: controlDeviceType,
                                        probeSerialNumber: probeSerialNumber,
                                        nodeSerialNumber: nodeSerialNumber,
                                        statusFlags: record.statusFlags,
                                        fanStatus: record.fanStatus)

        accessory.updateDeviceStatus(deviceStatus: engineStatus)
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
