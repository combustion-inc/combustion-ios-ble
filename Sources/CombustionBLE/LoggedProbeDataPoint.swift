//  LoggedProbeDataPoint.swift

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

public struct LoggedProbeDataPoint: Equatable {
    public let sequenceNum: UInt32
    public let temperatures: ProbeTemperatures
    public let virtualCore: VirtualCoreSensor
    public let virtualSurface: VirtualSurfaceSensor
    public let virtualAmbient: VirtualAmbientSensor
    public let predictionState: PredictionState
    public let predictionMode: PredictionMode
    public let predictionType: PredictionType
    public let predictionSetPointTemperature: Double
    public let predictionValueSeconds: UInt
    public let estimatedCoreTemperature: Double
    
    public init(sequenceNum: UInt32, temperatures: ProbeTemperatures, virtualCore: VirtualCoreSensor, virtualSurface: VirtualSurfaceSensor, virtualAmbient: VirtualAmbientSensor, predictionState: PredictionState, predictionMode: PredictionMode, predictionType: PredictionType, predictionSetPointTemperature: Double, predictionValueSeconds: UInt, estimatedCoreTemperature: Double) {
        self.sequenceNum = sequenceNum
        self.temperatures = temperatures
        self.virtualCore = virtualCore
        self.virtualSurface = virtualSurface
        self.virtualAmbient = virtualAmbient
        self.predictionState = predictionState
        self.predictionMode = predictionMode
        self.predictionType = predictionType
        self.predictionSetPointTemperature = predictionSetPointTemperature
        self.predictionValueSeconds = predictionValueSeconds
        self.estimatedCoreTemperature = estimatedCoreTemperature
    }
}

/// Record representing a logged temperature data point retrieved from a probe
extension LoggedProbeDataPoint {
    
    /// Generates a LoggedProbeDataPoint from a previously-parsed DeviceStatus record.
    /// - parameter ProbeStatus: ProbeStatus instance
    static func fromDeviceStatus(deviceStatus: ProbeStatus) -> LoggedProbeDataPoint {
        return LoggedProbeDataPoint(sequenceNum: deviceStatus.maxSequenceNumber,
                                    temperatures: deviceStatus.temperatures,
                                    virtualCore: deviceStatus.batteryStatusVirtualSensors.virtualSensors.virtualCore,
                                    virtualSurface: deviceStatus.batteryStatusVirtualSensors.virtualSensors.virtualSurface,
                                    virtualAmbient: deviceStatus.batteryStatusVirtualSensors.virtualSensors.virtualAmbient,
                                    predictionState: deviceStatus.predictionStatus.predictionState,
                                    predictionMode: deviceStatus.predictionStatus.predictionMode,
                                    predictionType: deviceStatus.predictionStatus.predictionType,
                                    predictionSetPointTemperature: deviceStatus.predictionStatus.predictionSetPointTemperature,
                                    predictionValueSeconds: deviceStatus.predictionStatus.predictionValueSeconds,
                                    estimatedCoreTemperature: deviceStatus.predictionStatus.estimatedCoreTemperature)
    }
    
    static func fromLogResponse(logResponse: LogResponse) -> LoggedProbeDataPoint {
        return LoggedProbeDataPoint(sequenceNum: logResponse.sequenceNumber,
                                    temperatures: logResponse.temperatures,
                                    virtualCore: logResponse.predictionLog.virtualSensors.virtualCore,
                                    virtualSurface: logResponse.predictionLog.virtualSensors.virtualSurface,
                                    virtualAmbient: logResponse.predictionLog.virtualSensors.virtualAmbient,
                                    predictionState: logResponse.predictionLog.predictionState,
                                    predictionMode: logResponse.predictionLog.predictionMode,
                                    predictionType: logResponse.predictionLog.predictionType,
                                    predictionSetPointTemperature: logResponse.predictionLog.predictionSetPointTemperature,
                                    predictionValueSeconds: UInt(logResponse.predictionLog.predictionValueSeconds),
                                    estimatedCoreTemperature: logResponse.predictionLog.estimatedCoreTemperature)
    }
    
    static func fromLogResponse(logResponse: NodeReadLogsResponse) -> LoggedProbeDataPoint {
        return LoggedProbeDataPoint(sequenceNum: logResponse.sequenceNumber,
                                    temperatures: logResponse.temperatures,
                                    virtualCore: logResponse.predictionLog.virtualSensors.virtualCore,
                                    virtualSurface: logResponse.predictionLog.virtualSensors.virtualSurface,
                                    virtualAmbient: logResponse.predictionLog.virtualSensors.virtualAmbient,
                                    predictionState: logResponse.predictionLog.predictionState,
                                    predictionMode: logResponse.predictionLog.predictionMode,
                                    predictionType: logResponse.predictionLog.predictionType,
                                    predictionSetPointTemperature: logResponse.predictionLog.predictionSetPointTemperature,
                                    predictionValueSeconds: UInt(logResponse.predictionLog.predictionValueSeconds),
                                    estimatedCoreTemperature: logResponse.predictionLog.estimatedCoreTemperature)
    }
}


extension LoggedProbeDataPoint {
    // Generates fake data for UI previews
    static func withFakeData() -> LoggedProbeDataPoint {
        // Workaround limit on static variables being restricted to structs/classes
        struct S { static var sequenceNum : UInt32 = 0 }
        S.sequenceNum += 1
        
        let values : [Double] = [
            50.0,
            60.0,
            70.0,
            80.0,
            100.0,
            200.0,
            300.0,
            400.0
        ]
        let temperatures = ProbeTemperatures (values: values)
        
        return LoggedProbeDataPoint(sequenceNum: S.sequenceNum,
                                    temperatures: temperatures,
                                    virtualCore: .T1,
                                    virtualSurface: .T5,
                                    virtualAmbient: .T8,
                                    predictionState: .cooking,
                                    predictionMode: .removalAndResting,
                                    predictionType: .removal,
                                    predictionSetPointTemperature: 54.4,
                                    predictionValueSeconds: 600,
                                    estimatedCoreTemperature: 30.0)
    }
}

extension LoggedProbeDataPoint: Hashable {
    public static func == (lhs: LoggedProbeDataPoint, rhs: LoggedProbeDataPoint) -> Bool {
        return lhs.sequenceNum == rhs.sequenceNum
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(sequenceNum)
    }
}
