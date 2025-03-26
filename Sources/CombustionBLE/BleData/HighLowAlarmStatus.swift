//  HighLowAlarmStatus.swift
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

public struct HighLowAlarmStatus: Equatable {
    public let highAlarmStatus: AlarmStatus
    public let lowAlarmStatus: AlarmStatus
    
    public init(highAlarmStatus: AlarmStatus, lowAlarmStatus: AlarmStatus) {
        self.highAlarmStatus = highAlarmStatus
        self.lowAlarmStatus = lowAlarmStatus
    }
}

extension HighLowAlarmStatus {
    
    static func fromData(_ data: Data) -> HighLowAlarmStatus {
        guard data.count == 4 else { return defaultValues() }
                
        let rawValue = UInt32(bigEndian: data.withUnsafeBytes { $0.load(as: UInt32.self) })
        let highAlarmData = UInt16((rawValue >> 16) & 0xFFFF)
        let lowAlarmData = UInt16(rawValue & 0xFFFF)
                
        let highAlarm = AlarmStatus.fromByte(highAlarmData)
        let lowAlarm = AlarmStatus.fromByte(lowAlarmData)
                
        return HighLowAlarmStatus(highAlarmStatus: highAlarm, lowAlarmStatus: lowAlarm)
    }
    
    static func defaultValues() -> HighLowAlarmStatus {
        return .init(highAlarmStatus: .init(set: false, tripped: false, alarming: false, alarmTemperature: nil),
                     lowAlarmStatus: .init(set: false, tripped: false, alarming: false, alarmTemperature: nil))
    }
}

public struct AlarmStatus: Equatable, Hashable {
    
    public let set: Bool
    public let tripped: Bool
    public let alarming: Bool
    public let alarmTemperature: Double?
    
    public init(set: Bool, tripped: Bool, alarming: Bool, alarmTemperature: Double?) {
        self.set = set
        self.tripped = tripped
        self.alarming = alarming
        self.alarmTemperature = alarmTemperature
    }
    
    static func fromByte(_ rawValue: UInt16) -> AlarmStatus {
        let set = (rawValue & (1 << 0)) != 0
        let tripped = (rawValue & (1 << 1)) != 0
        let alarming = (rawValue & (1 << 2)) != 0
        
        let tempRaw = (rawValue >> 3) & 0x1FFF // Extract 13-bit temperature field
        let alarmTemperature: Double? = tempRaw > 0 ? Double(tempRaw) * 0.1 - 20.0 : nil
        
        return AlarmStatus(set: set, tripped: tripped, alarming: alarming, alarmTemperature: alarmTemperature)
    }
}
