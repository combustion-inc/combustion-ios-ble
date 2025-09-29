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
                
        let highAlarm = AlarmStatus.fromByte(highAlarmData.byteSwapped)
        let lowAlarm = AlarmStatus.fromByte(lowAlarmData.byteSwapped)

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
    
    /// Parses an array of AlarmStatus values from a raw data buffer.
    static func arrayFromRawData(data: Data) -> [AlarmStatus] {
        guard data.count >= 2, data.count % 2 == 0 else { return [] }

        var result: [AlarmStatus] = []
        result.reserveCapacity(data.count / 2)

        var i = data.startIndex
        while i < data.endIndex {
            let value = (UInt16(data[i]) << 8) | UInt16(data[i+1])
            let raw = UInt16(bigEndian: value)

            result.append(AlarmStatus.fromByte(raw))
            i = data.index(i, offsetBy: 2)
        }

        return result
    }
}

extension HighLowAlarmStatus {
    
    func toRawData() -> [UInt8] {
        let highBytes = highAlarmStatus.toBytes()
        let lowBytes = lowAlarmStatus.toBytes()
        return highBytes + lowBytes
    }
}

extension AlarmStatus {
    
    func toBytes() -> [UInt8] {
        var bytes = (alarmTemperature ?? 0).toRawDataEnd()
        var flagBits = bytes[0]

        if set {
            flagBits |= 1 << 0
        }
        if tripped {
            flagBits |= 1 << 1
        }
        if alarming {
            flagBits |= 1 << 2
        }

        bytes[0] = flagBits
        return bytes
    }
    
}

fileprivate extension Double {
    
    func toRawDataEnd() -> [UInt8] {
        // Convert temperature to 13-bit raw value
        let raw13 = Int(((self + 20.0) / 0.1).rounded())
            .clamped(to: 0...0x1FFF)

        // Shift left to place raw13 into bits 3–15 (leave bits 0–2 as 0)
        let raw16 = UInt16(raw13 << 3)

        // Split into little-endian bytes
        let lowByte = UInt8(raw16 & 0x00FF)
        let highByte = UInt8((raw16 >> 8) & 0x00FF)

        return [lowByte, highByte]
    }
}

fileprivate extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}
