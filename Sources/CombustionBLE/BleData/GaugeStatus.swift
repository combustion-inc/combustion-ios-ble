//  GaugeStatus.swift
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

/// Message containing Gauge status information.
public struct GaugeStatus: DeviceStatus {
    
    /// gauge serial number
    public let serialNumber: String
    
    /// session ID for active session
    public let sessionID: UInt32
    
    /// Minimum sequence number of records in gauges memory.
    public let minSequenceNumber: UInt32
    
    /// Maximum sequence number of records in gauges memory.
    public let maxSequenceNumber: UInt32
    
    /// Current temperature sent by Gauge.
    public let temperature: GaugeTemperature
    
    /// high low alarm status for ambient temperature
    public let highLowAlarmStatus: HighLowAlarmStatus
    
    /// gauge details, sensorPresent, sensoryOverheating, lowBattery
    public let status: GaugeDetails
    
    /// Number of milliseconds between each log
    public let samplePeriod: UInt16
    
    /// true if data corresponds to a new log record, false if not
    public let newRecordFlag: Bool
    
    public init(serialNumber: String,
                sessionID: UInt32,
                minSequenceNumber: UInt32,
                maxSequenceNumber: UInt32,
                temperature: GaugeTemperature,
                alarmStatus: HighLowAlarmStatus,
                status: GaugeDetails,
                samplePeriod: UInt16,
                newRecordFlag: Bool) {
        self.serialNumber = serialNumber
        self.sessionID = sessionID
        self.minSequenceNumber = minSequenceNumber
        self.maxSequenceNumber = maxSequenceNumber
        self.temperature = temperature
        self.highLowAlarmStatus = alarmStatus
        self.status = status
        self.samplePeriod = samplePeriod
        self.newRecordFlag = newRecordFlag
    }
}

extension GaugeStatus {
    private enum Constants {
        // Locations of data in status packet
        static let SERIAL_NUMBER_RANGE = 10..<20
        static let SESSION_ID_RANGE = 20..<24
        static let SAMPLE_PERIOD_RANGE = 24..<26
        static let TEMPERATURE_RANGE = 26..<28
        static let GAUGE_STATUS_RANGE = 28..<29
        static let LOG_RANGE = 29..<37
        static let RESERVED_RANGE = 37..<38
        static let HIGH_LOW_ALARM_RANGE = 38..<42
        static let NEW_RECORD_FLAG_RANGE = 42..<43
    }
    
    init?(fromData data: Data) {
        guard data.count >= Constants.NEW_RECORD_FLAG_RANGE.endIndex else { return nil }
        
        let sequenceByteIndex = NodeRequest.HEADER_LENGTH
        
        // Serial Number
        
        let serialRaw = data.subdata(in: Constants.SERIAL_NUMBER_RANGE)
        let serialNumberString = String(decoding: serialRaw, as: UTF8.self).trimmingCharacters(in: CharacterSet(["\0"]))
        self.serialNumber = serialNumberString
        
        // Session ID
        let sessionIDData = data.subdata(in: Constants.SESSION_ID_RANGE)
        self.sessionID = sessionIDData.withUnsafeBytes { pointer in
            pointer.load(as: UInt32.self)
        }
        
        // Sample Period
        let samplePeriodData = data.subdata(in: Constants.SAMPLE_PERIOD_RANGE)
        self.samplePeriod = samplePeriodData.withUnsafeBytes { $0.load(as: UInt16.self) }
        
        // Log Sequence
        let logRangeData = data.subdata(in: Constants.LOG_RANGE)
        let logRange: UInt64 = logRangeData.withUnsafeBytes { $0.load(as: UInt64.self) }
        
        self.minSequenceNumber = UInt32(logRange & 0xFFFFFFFF)
        self.maxSequenceNumber = UInt32(logRange >> 32)
        
        // Temperature
        let tempData = data.subdata(in: Constants.TEMPERATURE_RANGE)
        self.temperature = GaugeTemperature.fromRawData(data: tempData)
        
        // High Low Alarms
        let hiLoAlarmData = data.subdata(in: Constants.HIGH_LOW_ALARM_RANGE)
        self.highLowAlarmStatus = HighLowAlarmStatus.fromData(hiLoAlarmData)
        
        // Status
        self.status = GaugeDetails.fromByte(data.subdata(in: Constants.GAUGE_STATUS_RANGE)[0])
        
        // New Record Flag
        let newRecordFlagData = data.subdata(in: Constants.NEW_RECORD_FLAG_RANGE)
        self.newRecordFlag =  newRecordFlagData.withUnsafeBytes { $0.load(as: Bool.self) }
    }
}
