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
    
    @Published public private(set) var batteryStatus: BatteryStatus = .ok
    
    @Published public private(set) var virtualSensors: VirtualSensors?
    @Published public private(set) var predictionStatus: PredictionStatus?
    
    public var coreTemperature: Double? {
        guard let virtualSensors = virtualSensors,
              let currentTemperatures = currentTemperatures else { return nil }
        
        return currentTemperatures.values[Int(virtualSensors.virtualCore.rawValue)]
    }
    
    public var surfaceTemperature: Double? {
        guard let virtualSensors = virtualSensors,
              let currentTemperatures = currentTemperatures else { return nil }
        
        // Surface range is T4 - T7, therefore add 3
        let sensorNumber = Int(virtualSensors.virtualSurface.rawValue) + 3
        return currentTemperatures.values[sensorNumber]
    }
    
    public var ambientTemperature: Double? {
        guard let virtualSensors = virtualSensors,
              let currentTemperatures = currentTemperatures else { return nil }
        
        // Ambient range is T5 - T8, therefore add 4
        let sensorNumber = Int(virtualSensors.virtualAmbient.rawValue) + 4
        return currentTemperatures.values[sensorNumber]
    }
    
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
    
    private var sessionInformation: SessionInformation?
    
    /// Time at which probe instant read was last updated
    internal var lastInstantRead: Date?
    
    init(_ advertising: AdvertisingData, isConnectable: Bool, RSSI: NSNumber, identifier: UUID) {
        serialNumber = advertising.serialNumber
        id = advertising.modeId.id
        color = advertising.modeId.color
        
        super.init(identifier: identifier, RSSI: RSSI)
        
        updateWithAdvertising(advertising, isConnectable: isConnectable, RSSI: RSSI)
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
    
    
    func updateWithAdvertising(_ advertising: AdvertisingData, isConnectable: Bool, RSSI: NSNumber) {
        // Always update probe RSSI and isConnectable flag
        self.rssi = RSSI.intValue
        self.isConnectable = isConnectable
        
        // Only update rest of data if not connected to probe.  Otherwise, rely on status
        // notifications to update data
        if(connectionState != .connected)
        {
            if(advertising.modeId.mode == .normal) {
                currentTemperatures = advertising.temperatures
            }
            else if(advertising.modeId.mode == .instantRead ){
                updateInstantRead(advertising.temperatures.values[0])
            }
            

            id = advertising.modeId.id
            color = advertising.modeId.color
            batteryStatus = advertising.batteryStatusVirtualSensors.batteryStatus
            virtualSensors = advertising.batteryStatusVirtualSensors.virtualSensors
            
            lastUpdateTime = Date()
        }
    }
    
    /// Updates the Device based on newly-received DeviceStatus message. Requests missing records.
    func updateProbeStatus(deviceStatus: ProbeStatus) {
        minSequenceNumber = deviceStatus.minSequenceNumber
        maxSequenceNumber = deviceStatus.maxSequenceNumber
        id = deviceStatus.modeId.id
        color = deviceStatus.modeId.color
        batteryStatus = deviceStatus.batteryStatusVirtualSensors.batteryStatus
        virtualSensors = deviceStatus.batteryStatusVirtualSensors.virtualSensors
        predictionStatus = deviceStatus.predictionStatus
        
        if(deviceStatus.modeId.mode == .normal) {
            currentTemperatures = deviceStatus.temperatures
            
            // Log the temperature data point for "Normal" status updates
            // Log the temperature data point
            addDataToLog(LoggedProbeDataPoint.fromDeviceStatus(deviceStatus: deviceStatus))
        }
        else if(deviceStatus.modeId.mode == .instantRead ){
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
