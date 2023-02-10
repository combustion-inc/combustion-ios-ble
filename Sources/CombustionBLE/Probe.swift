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
public class Probe : Device {
    
    /// Probe serial number
    @Published public private(set) var serialNumber: UInt32
        
    /// Returns serial number formatted as a string
    public var serialNumberString : String {
        return String(format: "%08X", serialNumber)
    }
    
    @Published public private(set) var currentTemperatures: ProbeTemperatures? {
        didSet {
            updateVirtualTemperatures()
        }
    }
    
    @Published public private(set) var instantReadTemperature: Double?
    
    @Published public private(set) var minSequenceNumber: UInt32?
    @Published public private(set) var maxSequenceNumber: UInt32?
    
    /// Tracks whether all logs on probe have been synced to the app
    @Published public private(set) var logsUpToDate = false
    
    @Published public private(set) var id: ProbeID
    @Published public private(set) var color: ProbeColor
    
    @Published public private(set) var batteryStatus: BatteryStatus = .ok
    
    @Published public private(set) var virtualSensors: VirtualSensors? {
        didSet {
            updateVirtualTemperatures()
        }
    }
    
    @Published public private(set) var predictionInfo: PredictionInfo?
    
    public struct VirtualTemperatures {
        public let coreTemperature: Double
        public let surfaceTemperature: Double
        public let ambientTemperature: Double
    }
    
    @Published public private(set) var virtualTemperatures: VirtualTemperatures?
    
    public var hasActivePrediction: Bool {
        guard let info = predictionInfo else { return false }
        
        return info.predictionMode != .none
    }
    
    /// Stores historical values of probe temperatures
    public private(set) var temperatureLogs: [ProbeTemperatureLog] = []
    
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
    @Published public private(set) var overheating: Bool = false
    
    /// Array of sensor indexes that are overheating
    @Published public private(set) var overheatingSensors: [Int] = []
    
    /// Tracks the most recent time a status notification was received.
    @Published public internal(set) var lastStatusNotificationTime = Date()
    
    /// Tracks whether status notification data has become stale.
    @Published public private(set) var statusNotificationsStale = false
    
    
    private var sessionInformation: SessionInformation?
    
    /// Time at which probe instant read was last updated
    internal var lastInstantRead: Date?
   
    /// Last hop count that updated Instant Read (nil = direct from Probe)
    internal var lastInstantReadHopCount : HopCount? = nil
     
    
    /// Time at which probe 'normal mode' info (raw temperatures etc.) was last updated
    internal var lastNormalMode: Date?
   
    /// Last hop count that updated 'normal mode' info (nil = direct from Probe)
    internal var lastNormalModeHopCount : HopCount? = nil

    private var predictionManager: PredictionManager
   
    init(_ advertising: AdvertisingData, isConnectable: Bool?, RSSI: NSNumber?, identifier: UUID?) {
        predictionManager = PredictionManager()
        
        serialNumber = advertising.serialNumber
        id = advertising.modeId.id
        color = advertising.modeId.color
        
        super.init(uniqueIdentifier: String(advertising.serialNumber), bleIdentifier: identifier, RSSI: RSSI)
        
        updateWithAdvertising(advertising, isConnectable: isConnectable, RSSI: RSSI, bleIdentifier: identifier)
        
        predictionManager.delegate = self
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
        if let lastInstantRead = lastInstantRead,
           Date().timeIntervalSince(lastInstantRead) > Constants.INSTANT_READ_STALE_TIMEOUT {
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
        
        
        /// Overheating thresholds (in degrees C) for T1 and T2
        static let OVERHEATING_T1_T2_THRESHOLD = 105.0
        /// Overheating thresholds (in degrees C) for T3
        static let OVERHEATING_T3_THRESHOLD = 115.0
        /// Overheating thresholds (in degrees C) for T4
        static let OVERHEATING_T4_THRESHOLD = 125.0
        /// Overheating thresholds (in degrees C) for T5-T8
        static let OVERHEATING_T5_T8_THRESHOLD = 300.0
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
        
        // Only update rest of data if not connected to probe.  Otherwise, rely on status
        // notifications to update data
        if(connectionState != .connected)
        {
            if(advertising.modeId.mode == .normal) {
                // If we should update normal mode, do so, but since this is Advertising info
                // and does not contain Prediction information, DO NOT lock it out. We want to
                // ensure the Prediction info gets updated over a Status notification if one
                // comes in.
                if(shouldUpdateNormalMode(hopCount: advertising.hopCount)) {
                    currentTemperatures = advertising.temperatures
                    
                    id = advertising.modeId.id
                    color = advertising.modeId.color
                    batteryStatus = advertising.batteryStatusVirtualSensors.batteryStatus
                    virtualSensors = advertising.batteryStatusVirtualSensors.virtualSensors
                    
                    // Check if the probe is overheating
                    checkOverheating()
                    
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
    
    /// Updates the Device based on newly-received DeviceStatus message. Requests missing records.
    func updateProbeStatus(deviceStatus: ProbeStatus, hopCount: HopCount? = nil) {
                   
        var updated : Bool = false
        
        if(deviceStatus.modeId.mode == .normal) {
            if(shouldUpdateNormalMode(hopCount: hopCount)) {
                // Update ID, Color, Battery Status
                id = deviceStatus.modeId.id
                color = deviceStatus.modeId.color
                batteryStatus = deviceStatus.batteryStatusVirtualSensors.batteryStatus
                
                // Update sequence numbers
                minSequenceNumber = deviceStatus.minSequenceNumber
                maxSequenceNumber = deviceStatus.maxSequenceNumber
         
                // Prediction status and Virtual Sensors are only transmitted in "Normal" status updates
                predictionManager.updatePredictionStatus(deviceStatus.predictionStatus,
                                                         sequenceNumber: deviceStatus.maxSequenceNumber)
                virtualSensors = deviceStatus.batteryStatusVirtualSensors.virtualSensors
                
                // Log the temperature data point for "Normal" status updates
                currentTemperatures = deviceStatus.temperatures
                addDataToLog(LoggedProbeDataPoint.fromDeviceStatus(deviceStatus: deviceStatus))
                
                // Check if the probe is overheating
                checkOverheating()
                
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
                minSequenceNumber = deviceStatus.minSequenceNumber
                maxSequenceNumber = deviceStatus.maxSequenceNumber
            }
        }
        
        // Check for missing records
        if updated, let current = getCurrentTemperatureLog() {
            if let missingSequence = current.firstMissingIndex(sequenceRangeStart: deviceStatus.minSequenceNumber,
                                                               sequenceRangeEnd: deviceStatus.maxSequenceNumber) {
                
                // Track that the app is not up to date with the probe
                logsUpToDate = false
                
                // Request missing records
                DeviceManager.shared.requestLogsFrom(self,
                                                     minSequence: missingSequence,
                                                     maxSequence: deviceStatus.maxSequenceNumber)
            } else {
                // If there were no gaps, mark that the logs are up to date
                logsUpToDate = true
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
    
    /// Checks if the probe is currently exceeding any temperature thresholds.
    func checkOverheating() {
        guard let currentTemperatures = currentTemperatures else { return }
        
        var anyOverTemp = false
        
        var overheatingSensorList : [Int] = []
            
        // Check T1-T2
        for i in 1...2 {
            if currentTemperatures.values[i] >= Constants.OVERHEATING_T1_T2_THRESHOLD {
                anyOverTemp = true
                overheatingSensorList.append(i)
            }
        }
        
        // Check T3
        if currentTemperatures.values[2] >= Constants.OVERHEATING_T3_THRESHOLD {
            anyOverTemp = true
            overheatingSensorList.append(2)
        }
        
        // Check T4
        if currentTemperatures.values[3] >= Constants.OVERHEATING_T4_THRESHOLD {
            anyOverTemp = true
            overheatingSensorList.append(3)
        }
        
        // Check T5-T8
        for i in 4...7 {
            if currentTemperatures.values[i] >= Constants.OVERHEATING_T5_T8_THRESHOLD {
                anyOverTemp = true
                overheatingSensorList.append(i)
            }
        }
        
        // Update observable variables
        self.overheating = anyOverTemp
        self.overheatingSensors = overheatingSensorList
    }
    
    private func addDataToLog(_ dataPoint: LoggedProbeDataPoint) {
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
    
    // Find the ProbeTemperatureLog that matches current session ID
    private func getCurrentTemperatureLog() -> ProbeTemperatureLog? {
        return temperatureLogs.first(where: { $0.sessionInformation.sessionID == sessionInformation?.sessionID } )
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
//            print("Updating instant read, date=\(Date()), hopCount=\(String(describing: hopCount))")
            lastInstantRead = Date()
            lastInstantReadHopCount = hopCount
            instantReadTemperature = instantReadValue
            id = probeId
            color = probeColor
            batteryStatus = probeBatteryStatus
            
            return true
            
        } else {
//            print("NOT updating instant read, date=\(Date()), hopCount=\(String(describing: hopCount))")
            return false
        }
    }
    
    private func updateVirtualTemperatures() {
        guard let virtualSensors = virtualSensors,
              let currentTemperatures = currentTemperatures else {
            self.virtualTemperatures = nil
            return
        }
        
        let core = virtualSensors.virtualCore.temperatureFrom(currentTemperatures)
        let surface = virtualSensors.virtualSurface.temperatureFrom(currentTemperatures)
        let ambient = virtualSensors.virtualAmbient.temperatureFrom(currentTemperatures)
        
        virtualTemperatures = VirtualTemperatures(coreTemperature: core,
                                                  surfaceTemperature: surface,
                                                  ambientTemperature: ambient)
    }
}

extension Probe: PredictionManagerDelegate {
    func publishPredictionInfo(info: PredictionInfo?) {
        self.predictionInfo = info
    }
}
