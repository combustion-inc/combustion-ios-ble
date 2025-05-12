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
        
        let firstSeq = accessory.deviceTemperatureLogs.first?.dataPoints.first?.sequenceNum ?? 0

        let lastSequence: UInt32

        if let last = accessory.deviceTemperatureLogs.first?.dataPoints.last?.sequenceNum {
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
                                       batteryPercentage: 98,
                                       samplePeriod: 5000,
                                       newRecordFlag: false)
        
        accessory.updateDeviceStatus(deviceStatus: gaugeStatus)
    }
}

