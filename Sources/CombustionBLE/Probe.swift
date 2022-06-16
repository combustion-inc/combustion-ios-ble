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
    
    @Published public private(set) var currentTemperatures: ProbeTemperatures?
    @Published public private(set) var instantReadTemperature: Double?
    
    @Published public private(set) var minSequenceNumber: UInt32?
    @Published public private(set) var maxSequenceNumber: UInt32?
    
    /// Tracks whether all logs on probe have been synced to the app
    @Published public private(set) var logsUpToDate = false
    
    @Published public private(set) var id: ProbeID
    @Published public private(set) var color: ProbeColor
    
    @Published public private(set) var batteryStatus: BatteryStatus
    
    private var sessionInformation: SessionInformation?
    
    /// Stores historical values of probe temperatures
    public private(set) var temperatureLogs: [ProbeTemperatureLog] = []
    
    /// Pretty-formatted device name
    public var name: String {
        return String(format: "%08X", serialNumber)
    }
    
    /// Integer representation of device MAC address
    public var macAddress: UInt64 {
        return (UInt64(serialNumber) * 10000 + 6912) | 0xC00000000000
    }
    
    /// String representation of device MAC address
    public var macAddressString: String {
        return String(format: "%012llX", macAddress)
    }
    
    /// Time at which probe instant read was last updated
    internal var lastInstantRead: Date?
    
    public init(_ advertising: AdvertisingData, RSSI: NSNumber, identifier: UUID) {
        serialNumber = advertising.serialNumber
        id = advertising.id
        color = advertising.color
        batteryStatus = advertising.batteryStatus
        
        super.init(identifier: identifier, RSSI: RSSI)
        
        updateWithAdvertising(advertising, RSSI: RSSI)
    }
    
    override func updateConnectionState(_ state: ConnectionState) {
        // Clear session information on disconnect, since probe may have reset
        if (state == .disconnected) {
            sessionInformation = nil
        }
        
        super.updateConnectionState(state)
    }
    
    override func updateDeviceStale() {
        // Clear instantReadTemperature if its been longer than timeout since last update
        if let lastInstantRead = lastInstantRead,
           Date().timeIntervalSince(lastInstantRead) > Constants.INSTANT_READ_STALE_TIMEOUT {
            instantReadTemperature = nil
        }
        
        super.updateDeviceStale()
    }
}
    
extension Probe {
    
    private enum Constants {
        /// Instant read is considered stale after 5 seconds
        static let INSTANT_READ_STALE_TIMEOUT = 5.0
    }
    
    
    func updateWithAdvertising(_ advertising: AdvertisingData, RSSI: NSNumber) {
        if(advertising.mode == .Normal) {
            currentTemperatures = advertising.temperatures
        }
        else if(advertising.mode == .InstantRead ){
            updateInstantRead(advertising.temperatures.values[0])
        }
        
        rssi = RSSI.intValue
        
        id = advertising.id
        color = advertising.color
        batteryStatus = advertising.batteryStatus
        
        lastUpdateTime = Date()
    }
    
    /// Updates the Device based on newly-received DeviceStatus message. Requests missing records.
    func updateProbeStatus(deviceStatus: DeviceStatus) {
        minSequenceNumber = deviceStatus.minSequenceNumber
        maxSequenceNumber = deviceStatus.maxSequenceNumber
        id = deviceStatus.id
        color = deviceStatus.color
        batteryStatus = deviceStatus.batteryStatus
        
        if(deviceStatus.mode == .Normal) {
            currentTemperatures = deviceStatus.temperatures
            
            // Log the temperature data point for "Normal" status updates
            // Log the temperature data point
            addDataToLog(LoggedProbeDataPoint.fromDeviceStatus(deviceStatus: deviceStatus))
        }
        else if(deviceStatus.mode == .InstantRead ){
            updateInstantRead(deviceStatus.temperatures.values[0])
        }
        
        // Check for missing records
        if let current = getCurrentTemperatureLog() {
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

        
        lastUpdateTime = Date()
    }
    
    func updateWithSessionInformation(_ sessionInformation: SessionInformation) {
        self.sessionInformation = sessionInformation
    }
    
    /// Processes an incoming log response (response to a manual request for prior messages)
    func processLogResponse(logResponse: LogResponse) {
        addDataToLog(LoggedProbeDataPoint.fromLogResponse(logResponse: logResponse))
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
    
    private func updateInstantRead(_ instantReadValue: Double) {
        lastInstantRead = Date()
        instantReadTemperature = instantReadValue
    }
    
    
    ///////////////////////
    // Current value functions
    ///////////////////////
    
    /// Converts the specified temperature to Celsius or Fahrenheit
    /// - param celsius: True for celsius, false for fahrenheit
    /// - returns: Requested temperature value
    static public func temperatureInCelsius(_ temperature: Double?, celsius: Bool) -> Double? {
        guard let temperature = temperature else { return nil }
        
        if !celsius {
            // Convert to fahrenheit
            return fahrenheit(celsius: temperature)
        }
                    
        return temperature
    }
}
