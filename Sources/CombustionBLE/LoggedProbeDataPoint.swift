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

public class LoggedProbeDataPoint: LoggedDeviceDataPoint {
    
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
    
    public override var deviceType: LoggedDeviceDataPointType {
        return .probe
    }
    
    public init(sequenceNum: UInt32, temperatures: ProbeTemperatures, virtualCore: VirtualCoreSensor, virtualSurface: VirtualSurfaceSensor, virtualAmbient: VirtualAmbientSensor, predictionState: PredictionState, predictionMode: PredictionMode, predictionType: PredictionType, predictionSetPointTemperature: Double, predictionValueSeconds: UInt, estimatedCoreTemperature: Double) {
        
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
        
        super.init(sequenceNum: sequenceNum)
    }
    
    override public func temperatureForChannelIndex(_ index: Int) -> Double? {
        return temperatures.values[index]
    }
    
    // MARK: - Codable
    
    private enum CodingKeys: String, CodingKey {
        case temperatures
        case virtualCore
        case virtualSurface
        case virtualAmbient
        case predictionState
        case predictionMode
        case predictionType
        case predictionSetPointTemperature
        case predictionValueSeconds
        case estimatedCoreTemperature
    }
    
    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(temperatures, forKey: .temperatures)
        try container.encode(virtualCore, forKey: .virtualCore)
        try container.encode(virtualSurface, forKey: .virtualSurface)
        try container.encode(virtualAmbient, forKey: .virtualAmbient)
        try container.encode(predictionState, forKey: .predictionState)
        try container.encode(predictionMode, forKey: .predictionMode)
        try container.encode(predictionType, forKey: .predictionType)
        try container.encode(predictionSetPointTemperature, forKey: .predictionSetPointTemperature)
        try container.encode(predictionValueSeconds, forKey: .predictionValueSeconds)
        try container.encode(estimatedCoreTemperature, forKey: .estimatedCoreTemperature)
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.temperatures = try container.decode(ProbeTemperatures.self, forKey: .temperatures)
        self.virtualCore = try container.decode(VirtualCoreSensor.self, forKey: .virtualCore)
        self.virtualSurface = try container.decode(VirtualSurfaceSensor.self, forKey: .virtualSurface)
        self.virtualAmbient = try container.decode(VirtualAmbientSensor.self, forKey: .virtualAmbient)
        self.predictionState = try container.decode(PredictionState.self, forKey: .predictionState)
        self.predictionMode = try container.decode(PredictionMode.self, forKey: .predictionMode)
        self.predictionType = try container.decode(PredictionType.self, forKey: .predictionType)
        self.predictionSetPointTemperature = try container.decode(Double.self, forKey: .predictionSetPointTemperature)
        self.predictionValueSeconds = try container.decode(UInt.self, forKey: .predictionValueSeconds)
        self.estimatedCoreTemperature = try container.decode(Double.self, forKey: .estimatedCoreTemperature)
        try super.init(from: decoder)
    }
}

/// Record representing a logged temperature data point retrieved from a probe
extension LoggedProbeDataPoint {
    
    /// Generates a LoggedProbeDataPoint from a previously-parsed DeviceStatus record.
    /// - parameter ProbeStatus: ProbeStatus instance
    public static func fromDeviceStatus(deviceStatus: ProbeStatus) -> LoggedProbeDataPoint {
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
