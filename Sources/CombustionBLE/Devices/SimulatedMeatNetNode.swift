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

    private var sequenceNumber: UInt32 = 0
    private let simulatedSessionId: UInt32

    private enum Constants {
        static let defaultSerialNumber = "FAKEENGIN01"
        static let defaultTemperatureSetPoint = 225.0
        static let defaultSamplePeriodMs: UInt16 = 5000
    }

    public init() {
        self.simulatedSessionId = UInt32.random(in: 0..<UInt32.max)

        let advertising = EngineAdvertisingData(fakeSerial: Constants.defaultSerialNumber,
                                                fakeTemperatureSetPoint: Constants.defaultTemperatureSetPoint)
        super.init(advertising, isConnectable: true, RSSI: SimulatedProbe.randomeRSSI(), identifier: UUID())

        self.accessory = Engine(parent: self, advertising: advertising)
        self.dfuType = .engine

        firmareVersion = "v1.0.0"
        hardwareRevision = "v0.1-A1"

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateFakeAdvertising()
        }

        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateFakeStatus()
        }

        self.connectionState = .connected

        let fakeSessionInfo = SessionInformation(sessionID: simulatedSessionId, samplePeriod: Constants.defaultSamplePeriodMs)
        (accessory as? Engine)?.updateWithSessionInformation(fakeSessionInfo)
    }

    public override var name: String {
        var nameStr = super.name
        nameStr.removeLast(4)
        return String(format: "SIM-\(nameStr)")
    }

    private func updateFakeAdvertising() {
        let advertising = EngineAdvertisingData(fakeSerial: Constants.defaultSerialNumber,
                                                fakeTemperatureSetPoint: Constants.defaultTemperatureSetPoint)
        updateWithAdvertising(advertising, isConnectable: true, RSSI: SimulatedProbe.randomeRSSI())
        accessory?.updateWithAdvertising(advertising)
    }

    private func updateFakeStatus() {
        guard let accessory = accessory as? Engine else { return }
        guard connectionState == .connected else { return }

        let sequence = sequenceNumber
        sequenceNumber += 1

        let engineStatus = EngineStatus(serialNumber: accessory.serialNumber,
                                        sessionID: simulatedSessionId,
                                        samplePeriod: Constants.defaultSamplePeriodMs,
                                        minSequenceNumber: sequence,
                                        maxSequenceNumber: sequence,
                                        batteryStatus: .init(level: .ok, state: .notCharging, voltage: 12.0),
                                        temperatureSetPoint: Constants.defaultTemperatureSetPoint,
                                        controlTemperature: -20,
                                        controlDeviceType: .unknown,
                                        probeSerialNumber: nil,
                                        nodeSerialNumber: nil,
                                        statusFlags: EngineStatusFlags(appMode: false,
                                                                       controlDeviceConnected: false,
                                                                       lidOpen: false,
                                                                       fixedSpeed: false),
                                        fanStatus: EngineFanStatus(fanState: .fanOff,
                                                                   dutyCycle: 0,
                                                                   commandedSpeed: 0,
                                                                   measuredSpeed: 0,
                                                                   fanOffTime: UInt32(Constants.defaultSamplePeriodMs),
                                                                   fanOnTime: 0),
                                        controllerStatus: EngineControllerStatus(state: .idle,
                                                                                 responseCoefficient: 0.0,
                                                                                 cyclesCompleted: UInt8(sequence % 255),
                                                                                 flags: .init(reachedSetpoint: true,
                                                                                              maintenanceMode: false),
                                                                                 smoothedTemperature: Constants.defaultTemperatureSetPoint,
                                                                                 timeToPeakSeconds: 0,
                                                                                 driftRate: 0.0),
                                        hopCount: .hop1,
                                        knobVoltage: 1.65,
                                        knobAngle: min(359.9, max(0.0, (Constants.defaultTemperatureSetPoint / 575.0) * 359.9)))

        accessory.updateDeviceStatus(deviceStatus: engineStatus)
    }
}
