//
//  LoggedProbeDataPoint.swift
//  Needle
//
//  Created by Jason Machacek on 10/21/21
//  Copyright © 2021 Combustion Inc. All rights reserved.
//

import Foundation

struct LoggedProbeDataPoint: Equatable {
    let sequenceNum: UInt32
    let temperatures: ProbeTemperatures
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
    static func == (lhs: LoggedProbeDataPoint, rhs: LoggedProbeDataPoint) -> Bool {
        return lhs.sequenceNum == rhs.sequenceNum
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(sequenceNum)
    }
}
