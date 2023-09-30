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

public class SimulatedProbe: Probe {
    
    private var fakeSetPoint = 71.0
    private var temperatures: ProbeTemperatures? = nil
    private var batterySensors: BatteryStatusVirtualSensors? = nil
    private var predictionStatus: PredictionStatus? = nil
    
    public init(temperatures: ProbeTemperatures? = nil, 
                batterySensors: BatteryStatusVirtualSensors? = nil,
                predictionStatus: PredictionStatus? = nil,
                probeDataPoints: [LoggedProbeDataPoint]? = nil) {
        self.temperatures = temperatures
        self.batterySensors = batterySensors
        self.predictionStatus = predictionStatus
        
        let advertising = AdvertisingData(fakeSerial: UInt32.random(in: 0 ..< UINT32_MAX),
                                          fakeTemperatures: temperatures ?? ProbeTemperatures.withRandomData(), 
                                          fakeVirtualSensors: batterySensors ?? BatteryStatusVirtualSensors.defaultValues())
        super.init(advertising, isConnectable: true, RSSI: SimulatedProbe.randomeRSSI(), identifier: UUID())
        
        firmareVersion = "v1.2.3"
        hardwareRevision = "v0.31-A1"
        
        // Create timer to update probe with fake advertising packets
        Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
                self?.updateFakeAdvertising()
        }
        
        // Create timer to update probe with fake status notifications
        Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            self?.updateFakeStatus()
        }
        
        self.connectionState = .connected
        
        // Set fake session information
        let fakeSessionInfo = SessionInformation(sessionID: UInt32.random(in: 0..<UInt32.max), samplePeriod: 1000)
        updateWithSessionInformation(fakeSessionInfo)
        
        // Add previous data to temperature logs
        if let probeDataPoints = probeDataPoints {
            let log = ProbeTemperatureLog(sessionInfo: fakeSessionInfo)
            
            for point in probeDataPoints {
                log.appendDataPoint(dataPoint: point)
            }
            
            self.temperatureLogs.append(log)
        }
    }
    
    public override var name: String {
        var nameStr = super.name
        nameStr.removeLast(4)
        return String(format: "SIM-\(nameStr)")
    }
    
    public func setPredictionSetPoint(_ setPoint: Double) {
        fakeSetPoint = setPoint
        updateFakeStatus()
    }
    
    static func randomeRSSI() -> NSNumber {
        return NSNumber(value: Int.random(in: -80 ..< -40))
    }
    
    private func updateFakeAdvertising() {
        let advertising = AdvertisingData(fakeSerial: UInt32.random(in: 0 ..< UINT32_MAX),
                                          fakeTemperatures: temperatures ?? ProbeTemperatures.withRandomData(), 
                                          fakeVirtualSensors: batterySensors ?? BatteryStatusVirtualSensors.defaultValues())
        updateWithAdvertising(advertising, isConnectable: true, RSSI: SimulatedProbe.randomeRSSI(), bleIdentifier: nil)
    }
    
    private func updateFakeStatus() {
        guard connectionState == .connected else { return }
        
        let firstSeq = temperatureLogs.first?.dataPoints.first?.sequenceNum ?? 0

        let lastSequence: UInt32

        if let last = temperatureLogs.first?.dataPoints.last?.sequenceNum {
            lastSequence = last + 1
        }
        else {
            lastSequence = 0
        }
        
        let fakePredictionStatus = PredictionStatus(predictionState: .predicting,
                                                predictionMode: .timeToRemoval,
                                                predictionType: .none,
                                                predictionSetPointTemperature: fakeSetPoint,
                                                heatStartTemperature: 5.0,
                                                predictionValueSeconds: 3540,
                                                estimatedCoreTemperature: 30.0)
        
        let probeStatus = ProbeStatus(minSequenceNumber: firstSeq,
                                      maxSequenceNumber: lastSequence,
                                      temperatures: temperatures ?? ProbeTemperatures.withRandomData(),
                                      modeId: ModeId.defaultValues(),
                                      batteryStatusVirtualSensors: batterySensors ?? BatteryStatusVirtualSensors.defaultValues(),
                                      predictionStatus: predictionStatus ?? fakePredictionStatus)
        
        updateProbeStatus(deviceStatus: probeStatus)
    }
}
