//  SimulatedProbe.swift
//  Simulated Probe

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

class SimulatedProbe: Probe {
    init() {
        let advertising = AdvertisingData(fakeSerial: UInt32.random(in: 0 ..< UINT32_MAX),
                                          fakeTemperatures: ProbeTemperatures.withRandomData())
        super.init(advertising, RSSI: SimulatedProbe.randomeRSSI(), identifier: UUID())
        
        firmareVersion = "v1.2.3"
        
        // Create timer to update probe with fake advertising packets
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.updateFakeAdvertising()
        }
        
        // Create timer to update probe with fake status notifications
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateFakeStatus()
        }
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
        let advertising = AdvertisingData(fakeSerial: UInt32.random(in: 0 ..< UINT32_MAX),
                                          fakeTemperatures: ProbeTemperatures.withRandomData())
        updateWithAdvertising(advertising, RSSI: SimulatedProbe.randomeRSSI())
    }
    
    private func updateFakeStatus() {
        guard connectionState == .connected else { return }
        
        let firstSeq = temperatureLog.dataPoints.first?.sequenceNum ?? 0
        
        let lastSequence: UInt32
        if let last = temperatureLog.dataPoints.last?.sequenceNum {
            lastSequence = last + 1
        }
        else {
            lastSequence = 0
        }
        
        let deviceStatus = DeviceStatus(minSequenceNumber: firstSeq,
                                        maxSequenceNumber: lastSequence,
                                        temperatures: ProbeTemperatures.withRandomData(),
                                        id: .ID1,
                                        color: .COLOR1)
        
        updateProbeStatus(deviceStatus: deviceStatus)
    }
}