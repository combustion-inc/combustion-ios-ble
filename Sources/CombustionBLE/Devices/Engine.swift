//  Engine.swift
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
import Combine

public class Engine: Accessory {
    
    public typealias SerialNumberType = String
    
    public var type: ProductType {
        return .engine
    }
    
    public private(set) var parent: Device?
    
    // device serial number
    @Published public private(set) var serialNumber: String
    
    public var serialNumberString: String {
        return serialNumber
    }
    
    
    /// Current session information
    @Published public internal(set) var sessionInformation: SessionInformation?
    
    public var mostRecentStatus = CurrentValueSubject<DeviceStatus?, Never>(nil)

    @Published public internal(set) var temperatureSetPoint: Double = 0.0

    @Published public internal(set) var controlTemperature: Double = 0.0

    @Published public internal(set) var statusFlags: EngineStatusFlags = .defaultValues()

    @Published public internal(set) var fanStatus: EngineFanStatus = .defaultValues()

    @Published public internal(set) var controlDeviceType: ProductType = .probe

    @Published public internal(set) var knobVoltage: Double = 0.0

    @Published public internal(set) var knobAngle: Double = 0.0

    @Published public internal(set) var chargingFault: EngineChargingFault = .defaultValues()
    
    /// Sequence number range of records on the engine
    @Published public internal(set) var sequenceNumberRange: ClosedRange<UInt32>?
    
    /// Tracks the most recent time a status notification was received.
    @Published public internal(set) var lastStatusNotificationTime = Date()
    
    /// Tracks whether status notification data has become stale.
    @Published public internal(set) var statusNotificationsStale = false
    
    /// Time at which engine 'normal mode' info (raw temperatures etc.) was last updated
    internal var lastNormalMode: Date?
   
    /// Last hop count that updated 'normal mode' info (nil = direct from Engine)
    @Published public internal(set) var lastNormalModeHopCount : HopCount? = nil
    
    /// Stores historical values of temperatures
    public internal(set) var deviceDataLogs: [DeviceDataLog] = []

    @available(*, deprecated, renamed: "deviceDataLogs")
    public var deviceTemperatureLogs: [DeviceDataLog] {
        return deviceDataLogs
    }
    
    /// Tracks what percent of logs on probe have been synced to the app
    @Published public internal(set) var percentOfLogsSynced: Int?
    
    /// Tracks the last time any update recieved for accessory
    @Published public internal(set) var lastUpdateTime: Date = Date()
    
    public var parentSubject = CurrentValueSubject<Device?, Never>(nil)
    
    private var deviceManager = DeviceManager.shared
    
    public var lastUpdateTimePublisher: AnyPublisher<Date, Never> {
        $lastUpdateTime.eraseToAnyPublisher()
    }

    public var sessionInformationPublisher: AnyPublisher<SessionInformation?, Never> {
        $sessionInformation.eraseToAnyPublisher()
    }
    
    public var connectionState: Device.ConnectionState {
        return parent?.connectionState ?? .disconnected
    }
    
    init(parent: MeatNetNode, advertising: any AdvertisingData) {
        self.serialNumber = advertising.serialNumberString
        
        setParent(parent)
        updateWithAdvertising(advertising)
    }
    
    init(parent: MeatNetNode? = nil, status: EngineStatus, hopCount: HopCount?) {
        self.serialNumber = status.serialNumber
        
        setParent(parent)
        updateDeviceStatus(deviceStatus: status, hopCount: hopCount)
    }
    
    public func setParent(_ device: Device?) {
        self.parent = device
        
        if let device = device {
            self.parentSubject.value = device
        }
    }
    
    public func updateWithSessionInformation(_ sessionInfo: SessionInformation) {
        if sessionInformation?.sessionID != sessionInfo.sessionID {
            mostRecentStatus.value = nil
            sessionInformation = sessionInfo
        }
    }
    
    public func updateWithAdvertising(_ advertising: any AdvertisingData) {
        guard let advertisingData = advertising as? EngineAdvertisingData else { return }
        
        updateLastUpdateTime()
       
        if let parent = parent, parent.connectionState != .connected && !deviceManager.isDeviceConnectedToMeatnet(parent) {
            updateTemperatureSetPoint(advertisingData.temperatureSetPoint)
            updateStatusFlags(advertisingData.statusFlags)
        }
    }
    
    /// Updates the Device based on newly-received EngineStatus message. Requests missing records.
    public func updateDeviceStatus(deviceStatus: DeviceStatus, hopCount: HopCount?) {
        guard let deviceStatus = deviceStatus as? EngineStatus else { return }
        
        // Ignore status messages that have a sequence count lower than any previously
        // received status messages
        guard !isOldStatusUpdate(deviceStatus) else { return }
                   
        var updated : Bool = false
        
        if shouldUpdateNormalMode(hopCount: hopCount) {
            // Update sequence number range
            sequenceNumberRange = deviceStatus.minSequenceNumber...deviceStatus.maxSequenceNumber
            
            updateTemperatureSetPoint(deviceStatus.temperatureSetPoint)
            updateControlTemperature(deviceStatus.controlTemperature)
            updateStatusFlags(deviceStatus.statusFlags)
            updateFanStatus(deviceStatus.fanStatus)
            updateControlDeviceType(deviceStatus.controlDeviceType)
            updateKnobVoltage(deviceStatus.knobVoltage)
            updateKnobAngle(deviceStatus.knobAngle)
            updateChargingFault(deviceStatus.chargingFault)
            updateWithSessionInformation(.init(sessionID: deviceStatus.sessionID,
                                               samplePeriod: deviceStatus.samplePeriod))
            
            // Log the temperature data point for "Normal" status updates
            addDataToLog(LoggedEngineDataPoint.fromDeviceStatus(deviceStatus: deviceStatus),
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
            
            if let missingRange = missingRange, let parent = parent as? MeatNetNode {
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
        mostRecentStatus.value = deviceStatus
        
        updateLastUpdateTime()
    }
    
    /// Determines whether to update Normal Mode info based on the hop count of the data.
    /// - param hopCount: Hop Count of information source (nil = direct from Engine)
    private func shouldUpdateNormalMode(hopCount: HopCount?) -> Bool {
        // If hopCount is nil, this is direct from a Engine and we should always update.
        guard let hopCount = hopCount else { return true }
        
        // If we haven't received Normal Mode data for more than the lockout period, we should always update.
        guard let lastNormalMode = lastNormalMode, (Date().timeIntervalSince(lastNormalMode) < Constants.NORMAL_MODE_LOCK_TIMEOUT) else { return true }
        
        // If we're in the lockout period and the last hop count was nil (i.e. direct from an Engine),
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
    private func isOldStatusUpdate(_ deviceStatus: EngineStatus) -> Bool {
        if let currentTemperatureLog = getCurrentTemperatureLog(),
            deviceStatus.sessionID == currentTemperatureLog.sessionInformation.sessionID,
            let max = currentTemperatureLog.dataPoints.last {
            return deviceStatus.maxSequenceNumber < max.sequenceNum
        }
        else {
            // This status belongs to a new session, therefore its not old
            return false
        }
    }
    
    /// Processes an incoming log response (response to a manual request for prior messages)
    func processLogResponse(logResponse: NodeEngineReadLogsResponse) {
        addDataToLog(LoggedEngineDataPoint.fromLogResponse(logResponse: logResponse))
    }
    
    private func addDataToLog(_ dataPoint: LoggedEngineDataPoint, sampledAt: Date? = nil) {
        // Do not store the dataPoint if its sequence number is greater
        // than the engine's max sequence number. This is a safety check
        // for the engine/node sending a record with invalid sequence number
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
            let log = DeviceDataLog(sessionInfo: sessionInformation)
            log.appendDataPoint(dataPoint: dataPoint, sampledAt: sampledAt)
            deviceDataLogs.append(log)
        }
    }
    
    // Find the EngineDeviceLog that matches current session ID
    private func getCurrentTemperatureLog() -> DeviceDataLog? {
        return deviceDataLogs.first(where: { $0.sessionInformation.sessionID == sessionInformation?.sessionID } )
    }
    
    func updateStatusNotificationsStale() {
        statusNotificationsStale = Date().timeIntervalSince(lastStatusNotificationTime) > Constants.STATUS_NOTIFICATION_STALE_TIMEOUT
    }
    
    public func updateLastUpdateTime() {
        guard Date().timeIntervalSince(lastUpdateTime) > Constants.MINIMUM_LAST_UPDATE_CHANGE else { return }
        
        lastUpdateTime = Date()
        (parent as? MeatNetNode)?.updateLastUpdateTime()
    }
}

extension Engine {
    
    private enum Constants {
        
        /// Number of seconds to ignore other lower-priority (higher hop count) sources of information for Normal Mode
        static let NORMAL_MODE_LOCK_TIMEOUT = 5.0
        
        /// Number of seconds after which status notifications should be considered stale.
        static let STATUS_NOTIFICATION_STALE_TIMEOUT = 16.0
        
        /// Minimum number of seconds before lastUpdateTime is updated
        static let MINIMUM_LAST_UPDATE_CHANGE = 1.0
    }
    
    private func updateTemperatureSetPoint(_ temperatureSetPoint: Double) {
        self.temperatureSetPoint = temperatureSetPoint
    }

    private func updateControlTemperature(_ controlTemperature: Double) {
        self.controlTemperature = controlTemperature
    }

    private func updateStatusFlags(_ statusFlags: EngineStatusFlags) {
        self.statusFlags = statusFlags
    }

    private func updateFanStatus(_ fanStatus: EngineFanStatus) {
        self.fanStatus = fanStatus
    }

    private func updateControlDeviceType(_ controlDeviceType: ProductType) {
        self.controlDeviceType = controlDeviceType
    }

    private func updateKnobVoltage(_ knobVoltage: Double) {
        self.knobVoltage = knobVoltage
    }

    private func updateKnobAngle(_ knobAngle: Double) {
        self.knobAngle = knobAngle
    }

    private func updateChargingFault(_ chargingFault: EngineChargingFault) {
        self.chargingFault = chargingFault
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
