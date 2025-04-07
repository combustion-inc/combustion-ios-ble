//  LoggedGaugeDataPoint.swift
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

public class LoggedDeviceDataPoint: Equatable {
    public var sequenceNum: UInt32
    
    public init(sequenceNum: UInt32) {
        self.sequenceNum = sequenceNum
    }
    
    public func temperatureForChannelIndex(_ index: Int) -> Double? {
        // override in subclass
        return nil
    }
}

extension LoggedDeviceDataPoint {
    
    public static func fromDeviceStatus(deviceStatus: DeviceStatus) -> LoggedDeviceDataPoint {
        if let deviceStatus = deviceStatus as? GaugeStatus {
            return LoggedGaugeDataPoint(sequenceNum: deviceStatus.maxSequenceNumber,
                                        temperatures: deviceStatus.temperature,
                                        sensorPresent: deviceStatus.status.sensorPresent)
        }
        else {
            return LoggedDeviceDataPoint(sequenceNum: deviceStatus.maxSequenceNumber)
        }
    }
}

extension LoggedDeviceDataPoint: Hashable {
    public static func == (lhs: LoggedDeviceDataPoint, rhs: LoggedDeviceDataPoint) -> Bool {
        return lhs.sequenceNum == rhs.sequenceNum
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(sequenceNum)
    }
}

public class LoggedGaugeDataPoint: LoggedDeviceDataPoint {
    
    public let temperatures: GaugeTemperature
    public let sensorPresent: Bool
    
    public init(sequenceNum: UInt32, temperatures: GaugeTemperature, sensorPresent: Bool) {
        self.temperatures = temperatures
        self.sensorPresent = sensorPresent
        super.init(sequenceNum: sequenceNum)
    }
    
    override public func temperatureForChannelIndex(_ index: Int) -> Double? {
        //gauge only has one temperature sensor, ignore other indexes
        guard index == 0 else { return nil }
        return sensorPresent ? temperatures.value : nil
    }
}

/// Record representing a logged temperature data point retrieved from a probe
extension LoggedGaugeDataPoint {
    
    /// Generates a LoggedProbeDataPoint from a previously-parsed DeviceStatus record.
    /// - parameter ProbeStatus: ProbeStatus instance
    public static func fromDeviceStatus(deviceStatus: GaugeStatus) -> LoggedGaugeDataPoint {
        return LoggedGaugeDataPoint(sequenceNum: deviceStatus.maxSequenceNumber,
                                    temperatures: deviceStatus.temperature,
                                    sensorPresent: deviceStatus.status.sensorPresent)
    }
    
    static func fromLogResponse(logResponse: GaugeLogResponse) -> LoggedGaugeDataPoint {
        return LoggedGaugeDataPoint(sequenceNum: logResponse.sequenceNumber,
                                    temperatures: logResponse.temperatures,
                                    sensorPresent: logResponse.sensorPresent)
    }
    
    static func fromLogResponse(logResponse: NodeGaugeReadLogsResponse) -> LoggedGaugeDataPoint {
        return LoggedGaugeDataPoint(sequenceNum: logResponse.sequenceNumber,
                                    temperatures: logResponse.temperatures,
                                    sensorPresent: logResponse.sensorPresent)
    }
}

extension LoggedGaugeDataPoint {
    
    // Generates fake data for UI previews
    static func withFakeData() -> LoggedGaugeDataPoint {
        // Workaround limit on static variables being restricted to structs/classes
        struct S { static var sequenceNum : UInt32 = 0 }
        S.sequenceNum += 1
        
        let temperatures = GaugeTemperature(value: 50.0)
        
        return LoggedGaugeDataPoint(sequenceNum: S.sequenceNum,
                                    temperatures: temperatures,
                                    sensorPresent: true)
    }
}
