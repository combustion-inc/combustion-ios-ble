//  Probe.swift
//  Representation of a Probe Device

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

/// Struct containing info about a Probe device.
open class Probe : Device {
    
    /// Probe serial number
    @Published public private(set) var serialNumber: UInt32
        
    /// Returns serial number formatted as a string
    public var serialNumberString : String {
        return String(format: "%08X", serialNumber)
    }
    
    @Published public internal(set) var currentTemperatures: ProbeTemperatures?
    
    /// Filtered Instant Read reading in Celsius.
    @Published public internal(set) var instantReadCelsius: Double?
    
    /// Filtered Instant Read reading in Fahrenheit.
    @Published public internal(set) var instantReadFahrenheit: Double?
    
    /// Deprecated. Legacy value - raw, unfiltered instant read reading.
    @available(*, deprecated)
    @Published public private(set) var instantReadTemperature: Double?
    
    /// Deprecated. Legacy value - use sequenceNumberRange instead.
    @available(*, deprecated)
    @Published public internal(set) var minSequenceNumber: UInt32?
    
    /// Deprecated. Legacy value - use sequenceNumberRange instead.
    @available(*, deprecated)
    @Published public internal(set) var maxSequenceNumber: UInt32?
    
    /// Sequence number range of records on the probe
    @Published public internal(set) var sequenceNumberRange: ClosedRange<UInt32>? {
        didSet {
            minSequenceNumber = sequenceNumberRange?.lowerBound
            maxSequenceNumber = sequenceNumberRange?.upperBound
        }
    }
    
    /// Tracks what percent of logs on probe have been synced to the app
    @Published public internal(set) var percentOfLogsSynced: Int?
    
    @Published public internal(set) var id: ProbeID
    @Published public internal(set) var color: ProbeColor
    
    @Published public internal(set) var batteryStatus: BatteryStatus = .ok
    
    @Published public internal(set) var virtualSensors: VirtualSensors?
    
    @Published public internal(set) var predictionInfo: PredictionInfo?
    
    @Published public internal(set) var foodSafeData: FoodSafeData?
    
    @Published public internal(set) var foodSafeStatus: FoodSafeStatus?
    
    public struct VirtualTemperatures {
        public let coreTemperature: Double
        public let surfaceTemperature: Double
        public let ambientTemperature: Double
    }
    
    @Published public internal(set) var virtualTemperatures: VirtualTemperatures?
    
    public var hasActivePrediction: Bool {
        guard let info = predictionInfo else { return false }
        
        return info.predictionMode != .none
    }
    
    /// Stores historical values of probe temperatures
    public internal(set) var temperatureLogs: [ProbeTemperatureLog] = []
    
    /// Pretty-formatted device name
    public var name: String {
        return serialNumberString
    }
    
    /// Integer representation of device MAC address
    public var macAddress: UInt64 {
        return (UInt64(serialNumber) * 10000 + 6912) | 0xC00000000000
    }
    
    /// String representation of device MAC address
    public var macAddressString: String {
        return String(format: "%012llX", macAddress)
    }
    
    /// Whether or not probe is overheating
    @Published public internal(set) var overheating: Bool = false
    
    /// Array of sensor indexes that are overheating
    @Published public internal(set) var overheatingSensors: [Int] = []
    
    /// Overheating thresholds for each sensor (in degrees C)
    public static let OVERHEATING_THRESHOLDS: [Double] = [
        105.0, // T1
        105.0, // T2
        115.0, // T3
        125.0, // T4
        300.0, // T5
        300.0, // T6
        300.0, // T7
        300.0, // T8
    ]
    
    /// Tracks the most recent time a status notification was received.
    @Published public internal(set) var lastStatusNotificationTime = Date()
    
    /// Tracks whether status notification data has become stale.
    @Published public internal(set) var statusNotificationsStale = false
    
    /// Current session information
    @Published public internal(set) var sessionInformation: SessionInformation?
    
    /// Time at which probe instant read was last updated
    internal var lastInstantRead: Date?
   
    /// Last hop count that updated Instant Read (nil = direct from Probe)
    @Published public internal(set) var lastInstantReadHopCount : HopCount? = nil
     
    /// Time at which probe 'normal mode' info (raw temperatures etc.) was last updated
    internal var lastNormalMode: Date?
   
    /// Last hop count that updated 'normal mode' info (nil = direct from Probe)
    @Published public internal(set) var lastNormalModeHopCount : HopCount? = nil

    private var predictionManager: PredictionManager
    private var instantReadFilter: InstantReadFilter
    private var deviceManager = DeviceManager.shared
    
    /// Timer for periodically requesting session information
    private var sessionRequestTimer = Timer()
   
    init(_ advertising: AdvertisingData, isConnectable: Bool?, RSSI: NSNumber?, identifier: UUID?) {
        predictionManager = PredictionManager()
        instantReadFilter = InstantReadFilter()
        
        serialNumber = advertising.serialNumber
        id = advertising.modeId.id
        color = advertising.modeId.color
        
        super.init(uniqueIdentifier: String(advertising.serialNumber), bleIdentifier: identifier, RSSI: RSSI)
        
        updateWithAdvertising(advertising, isConnectable: isConnectable, RSSI: RSSI, bleIdentifier: identifier)
        
        predictionManager.delegate = self
        
        // Start timer to re-request session information every 5 seconds
        sessionRequestTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true, block: { [weak self] _ in
            self?.requestSessionInformation()
        })
    }
    
    override func updateConnectionState(_ state: ConnectionState) {
        // Clear session information on disconnect, since probe may have reset
        if (state == .disconnected) {
            sessionInformation = nil
        }
        
        super.updateConnectionState(state)
    }
    
    func updateStatusNotificationsStale() {
        statusNotificationsStale = Date().timeIntervalSince(lastStatusNotificationTime) > Constants.STATUS_NOTIFICATION_STALE_TIMEOUT
    }
    
    /// Updates whether the device is stale. Called on a timer interval by DeviceManager.
    override func updateDeviceStale() {
        // Clear instantReadTemperature if its been longer than timeout since last update
        if let lastInstantRead = lastInstantRead, Date().timeIntervalSince(lastInstantRead) > Constants.INSTANT_READ_STALE_TIMEOUT {
            instantReadCelsius = nil
            instantReadFahrenheit = nil
            instantReadTemperature = nil
        }
        
        // Update whether status notifications are stale
        updateStatusNotificationsStale()
        
        super.updateDeviceStale()
    }
}
    
extension Probe {
    
    private enum Constants {
        /// Instant read is considered stale after 5 seconds
        static let INSTANT_READ_STALE_TIMEOUT = 5.0
          
        /// Number of seconds to ignore other lower-priority (higher hop count) sources of information for Instant Read
        static let INSTANT_READ_LOCK_TIMEOUT = 1.0
        
        /// Number of seconds to ignore other lower-priority (higher hop count) sources of information for Normal Mode
        static let NORMAL_MODE_LOCK_TIMEOUT = 5.0
        
        /// Number of seconds after which status notifications should be considered stale.
        static let STATUS_NOTIFICATION_STALE_TIMEOUT = 16.0
    }
    
    /// Updates this Probe with data from an advertisement message.
    /// - param advertising: Advertising data either directly from the Probe, or related via a MeatNet Node
    /// - param isConnectable: Whether Probe is connectable (not present if via Node)
    /// - param RSSI: Signal strength (not present if via Node)
    /// - param bleIdentifier: BLE UUID (not present if via Node)
    func updateWithAdvertising(_ advertising: AdvertisingData, isConnectable: Bool?, RSSI: NSNumber?, bleIdentifier: UUID?) {
        // Always update probe RSSI and isConnectable flag
        if let RSSI = RSSI {
            self.rssi = RSSI.intValue
        }
        if let isConnectable = isConnectable {
            self.isConnectable = isConnectable
        }
        if let bleIdentifier = bleIdentifier {
            self.bleIdentifier = bleIdentifier.uuidString
        }
        
        // Only update rest of data if not connected to probe (directly or through meatnet).
        // Otherwise, rely on status notifications to update data
        if(connectionState != .connected && !deviceManager.isProbeConnectedToMeatnet(self)) {
            if(advertising.modeId.mode == .normal) {
                // If we should update normal mode, do so, but since this is Advertising info
                // and does not contain Prediction information, DO NOT lock it out. We want to
                // ensure the Prediction info gets updated over a Status notification if one
                // comes in.
                if(shouldUpdateNormalMode(hopCount: advertising.hopCount)) {
                    // Update ID, Color, Battery status
                    updateIdColorBattery(probeId: advertising.modeId.id,
                                         probeColor: advertising.modeId.color,
                                         probeBatteryStatus: advertising.batteryStatusVirtualSensors.batteryStatus)
                    
                    // Update temperatures, virtual sensors, and check for overheating
                    updateTemperatures(temperatures: advertising.temperatures,
                                       virtualSensors: advertising.batteryStatusVirtualSensors.virtualSensors)
                    
                    lastUpdateTime = Date()
                }
            }
            else if(advertising.modeId.mode == .instantRead) {
                // Update Instant Read temperature, providing hop count information to prioritize it.
                if(updateInstantRead(advertising.temperatures.values[0],
                                     probeId: advertising.modeId.id,
                                     probeColor: advertising.modeId.color,
                                     probeBatteryStatus: advertising.batteryStatusVirtualSensors.batteryStatus,
                                     hopCount: (advertising.type == .probe) ? nil : advertising.hopCount)) {
                    
                    lastUpdateTime = Date()
                }
            }
        }
    }
    
    /// Requests any missing data.
    private func requestMissingData() {
        if sessionInformation == nil {
            deviceManager.readSessionInfo(probe: self)
        }
        
        if firmareVersion == nil {
            // Request the firmware version
            deviceManager.readFirmwareVersion(probe: self)
        }
        
        if hardwareRevision == nil {
            // Request the hardware version
            deviceManager.readHardwareVersion(probe: self)
        }
        
        if manufacturingLot == nil || sku == nil {
            // Request the model info
            deviceManager.readModelInfoForProbe(self)
        }
    }
    
    /// Updates the Device based on newly-received ProbeStatus message. Requests missing records.
    func updateProbeStatus(deviceStatus: ProbeStatus, hopCount: HopCount? = nil) {
        // Ignore status messages that have a sequence count lower than any previously
        // received status messages
        guard !isOldStatusUpdate(deviceStatus) else { return }
                   
        var updated : Bool = false
        
        if(deviceStatus.modeId.mode == .normal) {
            if(shouldUpdateNormalMode(hopCount: hopCount)) {
                // Update ID, Color, Battery status
                updateIdColorBattery(probeId: deviceStatus.modeId.id,
                                     probeColor: deviceStatus.modeId.color,
                                     probeBatteryStatus: deviceStatus.batteryStatusVirtualSensors.batteryStatus)
                
                // Update sequence number range
                sequenceNumberRange = deviceStatus.minSequenceNumber...deviceStatus.maxSequenceNumber
         
                // Update prediction status
                predictionManager.updatePredictionStatus(deviceStatus.predictionStatus,
                                                         sequenceNumber: deviceStatus.maxSequenceNumber)
                
                // Update temperatures, virtual sensors, and check for overheating
                updateTemperatures(temperatures: deviceStatus.temperatures,
                                   virtualSensors: deviceStatus.batteryStatusVirtualSensors.virtualSensors)
                
                // Update Food Safety data
                foodSafeData = deviceStatus.foodSafeData
                foodSafeStatus = deviceStatus.foodSafeStatus
                
                // Log the temperature data point for "Normal" status updates
                addDataToLog(LoggedProbeDataPoint.fromDeviceStatus(deviceStatus: deviceStatus))
                
                // Update normal mode update info for hop count lockout
                lastNormalMode = Date()
                lastNormalModeHopCount = hopCount
                
                // Track that info was updated
                updated = true
            }
        }
        else if(deviceStatus.modeId.mode == .instantRead ){
            // Update Instant Read temperature, including hop count information.
            updated = updateInstantRead(deviceStatus.temperatures.values[0],
                                        probeId: deviceStatus.modeId.id,
                                        probeColor: deviceStatus.modeId.color,
                                        probeBatteryStatus: deviceStatus.batteryStatusVirtualSensors.batteryStatus,
                                        hopCount: hopCount)
            if updated {
                // Also update sequence numbers if Instant Read was updated
                sequenceNumberRange = deviceStatus.minSequenceNumber...deviceStatus.maxSequenceNumber
            }
        }
        
        // Request any other missing data (firmware version etc.)
        requestMissingData()
        
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
                deviceManager.requestLogsFrom(self,
                                                     minSequence: missingRange.lowerBound,
                                                     maxSequence: missingRange.upperBound)
            }
        }

        // Update most recent status notification time
        lastStatusNotificationTime = Date()
        // Update whether status notifications are stale
        updateStatusNotificationsStale()
        
        // Update time of most recent update of any type
        lastUpdateTime = Date()
    }
    
    func updateWithSessionInformation(_ sessionInformation: SessionInformation) {
        self.sessionInformation = sessionInformation
    }
    
    /// Processes an incoming log response (response to a manual request for prior messages)
    func processLogResponse(logResponse: LogResponse) {
        addDataToLog(LoggedProbeDataPoint.fromLogResponse(logResponse: logResponse))
    }
    
    /// Processes an incoming node log response (response to a manual request for prior messages)
    func processLogResponse(logResponse: NodeReadLogsResponse) {
        addDataToLog(LoggedProbeDataPoint.fromLogResponse(logResponse: logResponse))
    }
    
    /// Checks if the probe is currently exceeding any temperature thresholds.
    private func checkOverheating() {
        guard let currentTemperatures = currentTemperatures else { return }
        
        var anyOverTemp = false
        
        var overheatingSensorList : [Int] = []
            
        // Check T1-T8
        for i in 0...7 {
            if currentTemperatures.values[i] >= Probe.OVERHEATING_THRESHOLDS[i] {
                anyOverTemp = true
                overheatingSensorList.append(i)
            }
        }
        
        // Update observable variables
        self.overheating = anyOverTemp
        self.overheatingSensors = overheatingSensorList
    }
    
    private func addDataToLog(_ dataPoint: LoggedProbeDataPoint) {
        // Do not store the dataPoint if its sequence number is greater
        // than the probe's max sequence number. This is a safety check
        // for the probe/node sending a record with invalid sequence number
        if let sequenceNumberRange = sequenceNumberRange,
           dataPoint.sequenceNum > sequenceNumberRange.upperBound {
            return
        }
        
        if let current = getCurrentTemperatureLog() {
            // Append data to temperature log for current session
            current.appendDataPoint(dataPoint: dataPoint)
        }
        else if let sessionInformation = sessionInformation {
            // Create a new Temperature log for session and append data
            let log = ProbeTemperatureLog(sessionInfo: sessionInformation)
            log.appendDataPoint(dataPoint: dataPoint)
            temperatureLogs.append(log)
        }
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
    
    // Find the ProbeTemperatureLog that matches current session ID
    private func getCurrentTemperatureLog() -> ProbeTemperatureLog? {
        return temperatureLogs.first(where: { $0.sessionInformation.sessionID == sessionInformation?.sessionID } )
    }
    
    
    /// Determins whether the device status has sequence number less than current maximum
    /// - param deviceStatus: Device status to check
    private func isOldStatusUpdate(_ deviceStatus: ProbeStatus) -> Bool {
        if let currentTemperatureLog = getCurrentTemperatureLog(), let max = currentTemperatureLog.dataPoints.last {
            return deviceStatus.maxSequenceNumber < max.sequenceNum
        }
        else {
            // This status belongs to a new session, therefore its not old
            return false
        }
    }
    
    /// Determines whether to update Instant Read based on the hop count of the data.
    /// - param hopCount: Hop Count of information source (nil = direct from Probe)
    private func shouldUpdateInstantRead(hopCount: HopCount?) -> Bool {
        // If hopCount is nil, this is direct from a Probe and we should always update.
        guard let hopCount = hopCount else { return true }
        
        // If we haven't received Instant Read data for more than the lockout period, we should always update.
        guard let lastInstantRead = lastInstantRead, (Date().timeIntervalSince(lastInstantRead) < Constants.INSTANT_READ_LOCK_TIMEOUT) else { return true }
        
        // If we're in the lockout period and the last hop count was nil (i.e. direct from a Probe),
        // we should NOT update.
        guard let lastInstantReadHopCount = lastInstantReadHopCount else { return false }
        
        // Compare hop counts and see if we should update.
        if hopCount.rawValue <= lastInstantReadHopCount.rawValue {
            // This hop count is equal or better priority than the last, so update.
            return true
        } else {
            // This hop is lower priority than the last, so do not update.
            return false
        }
    }
    
    
    /// Determines whether to update Normal Mode info based on the hop count of the data.
    /// - param hopCount: Hop Count of information source (nil = direct from Probe)
    private func shouldUpdateNormalMode(hopCount: HopCount?) -> Bool {
        // If hopCount is nil, this is direct from a Probe and we should always update.
        guard let hopCount = hopCount else { return true }
        
        // If we haven't received Normal Mode data for more than the lockout period, we should always update.
        guard let lastNormalMode = lastNormalMode, (Date().timeIntervalSince(lastNormalMode) < Constants.NORMAL_MODE_LOCK_TIMEOUT) else { return true }
        
        // If we're in the lockout period and the last hop count was nil (i.e. direct from a Probe),
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
    
    
    /// Updates the Instant Read temperature. May be ignored if hop count is too high.
    /// - param instantReadValue: New value of Instant Read temperature.
    /// - param probeId: Probe ID included with message
    /// - param probeColor: Probe Color included with message
    /// - param probeBatteryStatus: Probe Battery Status included with message
    /// - param hopCount: Hop Count of information source (nil = direct from Probe)
    /// - return true if updated, false if not
    private func updateInstantRead(_ instantReadValue: Double,
                                   probeId: ProbeID,
                                   probeColor: ProbeColor,
                                   probeBatteryStatus: BatteryStatus,
                                   hopCount: HopCount? = nil) -> Bool {
        if(shouldUpdateInstantRead(hopCount: hopCount)) {
            // Update hop count
            lastInstantRead = Date()
            lastInstantReadHopCount = hopCount
            // Update Instant Read filter
            instantReadFilter.addReading(temperatureInCelsius: instantReadValue)
            // Update legacy instant read value
            instantReadTemperature = instantReadValue
            // Update filtered Celsius value
            instantReadCelsius = instantReadFilter.values?.0
            // Update filtered Fahrenheit value
            instantReadFahrenheit = instantReadFilter.values?.1
            
            // Update ID, Color, Battery status
            updateIdColorBattery(probeId: probeId, probeColor: probeColor, probeBatteryStatus: probeBatteryStatus)
            
            return true
            
        } else {
//            print("NOT updating instant read, date=\(Date()), hopCount=\(String(describing: hopCount))")
            return false
        }
    }
    
    /// Updates the ID, Color, and battery status
    /// - param probeId: New Probe ID
    /// - param probeColor: New Probe Color
    /// - param probeBatteryStatus: New Probe Battery Status
    private func updateIdColorBattery(probeId: ProbeID, probeColor: ProbeColor, probeBatteryStatus: BatteryStatus) {
        id = probeId
        color = probeColor
        batteryStatus = probeBatteryStatus
    }
    
    private func updateTemperatures(temperatures: ProbeTemperatures, virtualSensors: VirtualSensors) {
        self.currentTemperatures = temperatures
        self.virtualSensors = virtualSensors
        
        // Update Virtual temperatures
        let core = virtualSensors.virtualCore.temperatureFrom(temperatures)
        let surface = virtualSensors.virtualSurface.temperatureFrom(temperatures)
        let ambient = virtualSensors.virtualAmbient.temperatureFrom(temperatures)
        
        virtualTemperatures = VirtualTemperatures(coreTemperature: core,
                                                  surfaceTemperature: surface,
                                                  ambientTemperature: ambient)
        
        // Check if the probe is overheating
        checkOverheating()
    }
    
    private func requestSessionInformation() {
        deviceManager.readSessionInfo(probe: self)
    }
}

extension Probe: PredictionManagerDelegate {
    func publishPredictionInfo(info: PredictionInfo?) {
        self.predictionInfo = info
    }
}
