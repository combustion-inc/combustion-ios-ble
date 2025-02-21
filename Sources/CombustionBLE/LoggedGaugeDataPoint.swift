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

public struct LoggedGaugeDataPoint: Equatable {
    
    public let sequenceNum: UInt32
    public let temperatures: GaugeTemperature
    
    public init(sequenceNum: UInt32, temperatures: GaugeTemperature) {
        self.sequenceNum = sequenceNum
        self.temperatures = temperatures
    }
}

/// Record representing a logged temperature data point retrieved from a probe
extension LoggedGaugeDataPoint {
    
    /// Generates a LoggedProbeDataPoint from a previously-parsed DeviceStatus record.
    /// - parameter ProbeStatus: ProbeStatus instance
    public static func fromDeviceStatus(deviceStatus: GaugeStatus) -> LoggedGaugeDataPoint {
        return LoggedGaugeDataPoint(sequenceNum: deviceStatus.maxSequenceNumber,
                                    temperatures: deviceStatus.temperature)
    }
    
    static func fromLogResponse(logResponse: GaugeLogResponse) -> LoggedGaugeDataPoint {
        return LoggedGaugeDataPoint(sequenceNum: logResponse.sequenceNumber,
                                    temperatures: logResponse.temperatures)
    }
    
    static func fromLogResponse(logResponse: NodeGaugeReadLogsResponse) -> LoggedGaugeDataPoint {
        return LoggedGaugeDataPoint(sequenceNum: logResponse.sequenceNumber,
                                    temperatures: logResponse.temperatures)
    }
}

extension LoggedGaugeDataPoint: Hashable {
    public static func == (lhs: LoggedGaugeDataPoint, rhs: LoggedGaugeDataPoint) -> Bool {
        return lhs.sequenceNum == rhs.sequenceNum
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(sequenceNum)
    }
}
