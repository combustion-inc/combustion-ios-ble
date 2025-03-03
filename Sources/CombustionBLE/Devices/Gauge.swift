//  Gauge.swift
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

public class GrillGauge: Accessory {
    
    public internal(set) var parent: MeatNetNode
    
    // device serial number
    @Published public private(set) var serialNumber: UInt32
    
    /// Returns serial number formatted as a string
    public var serialNumberString : String {
        return String(format: "%08X", serialNumber)
    }
    
    @Published public internal(set) var currentTemperature: GaugeTemperature?
    
    /// Current session information
    @Published public internal(set) var sessionInformation: SessionInformation?
    
    @Published public internal(set) var mostRecentStatus: GaugeStatus?
    
    /// Whether or not gauge is overheating
    @Published public internal(set) var overheating: Bool = false
    
    /// Array of sensor indexes that are overheating
    @Published public internal(set) var overheatingSensors: [Int] = []
    
    /// Sequence number range of records on the gauge
    @Published public internal(set) var sequenceNumberRange: ClosedRange<UInt32>?
    
    /// Tracks the most recent time a status notification was received.
    @Published public internal(set) var lastStatusNotificationTime = Date()
    
    /// Tracks whether status notification data has become stale.
    @Published public internal(set) var statusNotificationsStale = false
    
    /// Time at which gauge 'normal mode' info (raw temperatures etc.) was last updated
    internal var lastNormalMode: Date?
   
    /// Last hop count that updated 'normal mode' info (nil = direct from Gauge)
    @Published public internal(set) var lastNormalModeHopCount : HopCount? = nil
    
    /// Stores historical values of temperatures
    public internal(set) var temperatureLogs: [GaugeTemperatureLog] = []
    
    /// Tracks what percent of logs on probe have been synced to the app
    @Published public internal(set) var percentOfLogsSynced: Int?
    
    private var deviceManager = DeviceManager.shared
    
    init(parent: MeatNetNode, advertising: AdvertisingData) {
        self.parent = parent
        self.serialNumber = advertising.serialNumber
        
        updateWithAdvertising(advertising)
    }
    
    func updateWithSessionInformation(_ sessionInfo: SessionInformation) {
        if(sessionInformation?.sessionID != sessionInfo.sessionID) {
            // Recent probe status when session ID changes
            mostRecentStatus = nil
            
            sessionInformation = sessionInfo
        }
    }
    
    public func updateWithAdvertising(_ advertising: AdvertisingData) {
        guard let advertisingData = advertising as? GaugeAdvertisingData else { return }
        
        parent.updateLastUpdateTime()
        
        if(parent.connectionState != .connected && !deviceManager.isDeviceConnectedToMeatnet(parent)) {
            updateTemperatures(temperature: advertisingData.temperatures)
        }
    }
    
    /// Updates the Device based on newly-received GaugeStatus message. Requests missing records.
    public func updateDeviceStatus(deviceStatus: DeviceStatus, hopCount: HopCount?) {
        guard let deviceStatus = deviceStatus as? GaugeStatus else { return }
        
        // Ignore status messages that have a sequence count lower than any previously
        // received status messages
        guard !isOldStatusUpdate(deviceStatus) else { return }
                   
        var updated : Bool = false
        
        if(shouldUpdateNormalMode(hopCount: hopCount)) {
            // Update sequence number range
            sequenceNumberRange = deviceStatus.minSequenceNumber...deviceStatus.maxSequenceNumber
            
            updateTemperatures(temperature: deviceStatus.temperature)
            
            // Overheating sensors
            overheatingSensors = deviceStatus.overheatingSensors.sensorIndexes
            overheating = !overheatingSensors.isEmpty
            
            // Log the temperature data point for "Normal" status updates
            addDataToLog(LoggedGaugeDataPoint.fromDeviceStatus(deviceStatus: deviceStatus),
                         sampledAt: Date())
            
            // Update normal mode update info for hop count lockout
            lastNormalMode = Date()
            lastNormalModeHopCount = hopCount
            
            // Track that info was updated
            updated = true
        }
        
        // Check for missing records
        if updated, let current = getCurrentTemperatureLog() {
            
            // Update the percent of logs that have been transfered from the device
            updateLogPercent()
            
            // Save the first missing range of sequence numbers.
            // Don't request the current sequence number as it should come via status notifications.
            let missingRange = current.missingRange(sequenceRangeStart: deviceStatus.minSequenceNumber,
                                                    sequenceRangeEnd: deviceStatus.maxSequenceNumber)
            
            if let missingRange = missingRange {
                // Request missing records
                deviceManager.requestLogsFrom(parent,
                                              minSequence: missingRange.lowerBound,
                                              maxSequence: missingRange.upperBound)
            }
        }

        // Update most recent status notification time
        lastStatusNotificationTime = Date()
        
        // Update whether status notifications are stale
        updateStatusNotificationsStale()
        
        // Publish most recent status
        mostRecentStatus = deviceStatus
    }
    
    /// Determines whether to update Normal Mode info based on the hop count of the data.
    /// - param hopCount: Hop Count of information source (nil = direct from Gauge)
    private func shouldUpdateNormalMode(hopCount: HopCount?) -> Bool {
        // If hopCount is nil, this is direct from a Gauge and we should always update.
        guard let hopCount = hopCount else { return true }
        
        // If we haven't received Normal Mode data for more than the lockout period, we should always update.
        guard let lastNormalMode = lastNormalMode, (Date().timeIntervalSince(lastNormalMode) < Constants.NORMAL_MODE_LOCK_TIMEOUT) else { return true }
        
        // If we're in the lockout period and the last hop count was nil (i.e. direct from a Gauge),
        // we should NOT update.
        guard let lastNormalModeHopCount = lastNormalModeHopCount else { return false }
        
        // Compare hop counts and see if we should update.
        if hopCount.rawValue <= lastNormalModeHopCount.rawValue {
            // This hop count is equal or better priority than the last, so update.
            return true
        } else {
            // This hop is lower priority than the last, so do not update.
            return false
        }
    }
    
    /// Determins whether the device status has sequence number less than current maximum
    /// - param deviceStatus: Device status to check
    private func isOldStatusUpdate(_ deviceStatus: GaugeStatus) -> Bool {
        if let currentTemperatureLog = getCurrentTemperatureLog(), let max = currentTemperatureLog.dataPoints.last {
            return deviceStatus.maxSequenceNumber < max.sequenceNum
        }
        else {
            // This status belongs to a new session, therefore its not old
            return false
        }
    }
    
    /// Processes an incoming log response (response to a manual request for prior messages)
    func processLogResponse(logResponse: GaugeLogResponse) {
        addDataToLog(LoggedGaugeDataPoint.fromLogResponse(logResponse: logResponse))
    }
    
    /// Processes an incoming node log response (response to a manual request for prior messages)
    func processLogResponse(logResponse: NodeGaugeReadLogsResponse) {
        addDataToLog(LoggedGaugeDataPoint.fromLogResponse(logResponse: logResponse))
    }
    
    private func addDataToLog(_ dataPoint: LoggedGaugeDataPoint, sampledAt: Date? = nil) {
        // Do not store the dataPoint if its sequence number is greater
        // than the gauges's max sequence number. This is a safety check
        // for the gauge/node sending a record with invalid sequence number
        if let sequenceNumberRange = sequenceNumberRange,
           dataPoint.sequenceNum > sequenceNumberRange.upperBound {
            return
        }
        
        if let current = getCurrentTemperatureLog() {
            // Append data to temperature log for current session
            current.appendDataPoint(dataPoint: dataPoint, sampledAt: sampledAt)
        }
        else if let sessionInformation = sessionInformation {
            // Create a new Temperature log for session and append data
            let log = GaugeTemperatureLog(sessionInfo: sessionInformation)
            log.appendDataPoint(dataPoint: dataPoint, sampledAt: sampledAt)
            temperatureLogs.append(log)
        }
    }
    
    // Find the GaugeTemperatureLog that matches current session ID
    private func getCurrentTemperatureLog() -> GaugeTemperatureLog? {
        return temperatureLogs.first(where: { $0.sessionInformation.sessionID == sessionInformation?.sessionID } )
    }
    
    func updateStatusNotificationsStale() {
        statusNotificationsStale = Date().timeIntervalSince(lastStatusNotificationTime) > Constants.STATUS_NOTIFICATION_STALE_TIMEOUT
    }
}

extension GrillGauge {
    
    private enum Constants {
        
        /// Number of seconds to ignore other lower-priority (higher hop count) sources of information for Normal Mode
        static let NORMAL_MODE_LOCK_TIMEOUT = 5.0
        
        /// Number of seconds after which status notifications should be considered stale.
        static let STATUS_NOTIFICATION_STALE_TIMEOUT = 16.0
        
        /// Minimum number of seconds before lastUpdateTime is updated
        static let MINIMUM_LAST_UPDATE_CHANGE = 1.0
    }
    
    private func updateTemperatures(temperature: GaugeTemperature) {
        self.currentTemperature = temperature
    }
    
    private func updateLogPercent() {
        guard let sequenceNumberRange = sequenceNumberRange,
              let currentLog = getCurrentTemperatureLog() else { return }
        
        let numberLogsFromProbe = currentLog.logsInRange(sequenceNumbers: sequenceNumberRange)
        let numberLogsOnProbe = Int(sequenceNumberRange.upperBound - sequenceNumberRange.lowerBound + 1)
        
        if(numberLogsOnProbe == numberLogsFromProbe) {
            percentOfLogsSynced = 100
        } else {
            percentOfLogsSynced = Int(Double(numberLogsFromProbe) / Double(numberLogsOnProbe) * 100)
        }
    }
}
