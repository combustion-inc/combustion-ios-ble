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
}

/// Record representing a logged temperature data point retrieved from a probe
extension LoggedProbeDataPoint {
    
    /// Generates a LoggedProbeDataPoint from a previously-parsed DeviceStatus record.
    /// - parameter deviceStatus: DeviceStatus instance
    static func fromDeviceStatus(deviceStatus: DeviceStatus) -> LoggedProbeDataPoint {
        return LoggedProbeDataPoint(sequenceNum: deviceStatus.maxSequenceNumber,
                                    temperatures: deviceStatus.temperatures)
    }
    
    static func fromLogResponse(logResponse: LogResponse) -> LoggedProbeDataPoint {
        return LoggedProbeDataPoint(sequenceNum: logResponse.sequenceNumber,
                                    temperatures: logResponse.temperatures)
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
        return LoggedProbeDataPoint(sequenceNum: S.sequenceNum, temperatures: temperatures)
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
