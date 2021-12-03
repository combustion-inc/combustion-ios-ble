//
//  Device.swift
//  Representation of a Probe Device
//
//  Created by Jason Machacek on 2/5/20.
//  Copyright © 2020 Jason Machacek. All rights reserved.
//

import Foundation

/// Struct containing info about a thermometer device.
struct Device {
    /// Enumeration representing the various connection states of the device
    enum ConnectionState : CaseIterable {
        case disconnected, connecting, connected, failed
    }
    
    // String representation of device identifier (UUID)
    private(set) var id: String
    
    private(set) var serialNumber: UInt32
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var rssi : Int = Int.min
    private(set) var batteryLevel : Float = 0.0
    private(set) var currentTemperatures: ProbeTemperatures?
    private(set) var status: DeviceStatus?
    
    /// Tracks whether the app should attempt to maintain a connection to the probe.
    private(set) var maintainingConnection = false
    
    /// Tracks whether the data has gone stale (no new data in some time)
    private(set) var stale = false
    
    /// Tracks whether all logs on probe have been synced to the app
    private(set) var logsUpToDate = false
    
    private var lastUpdateTime = Date()
    
    // TODO persist the name somewhere, and make it settable
    var name: String { 
        return String(format: "%4X", serialNumber)
    }
       
    /// Stores historical values of probe temperatures
    private(set) var temperatureLog : ProbeTemperatureLog = ProbeTemperatureLog()
}
    
extension Device {
    
    private enum Constants {
        /// Go stale after this many seconds of no Bluetooth activity
        static let STALE_TIMEOUT = 15.0
    }
    
    init(_ advertising: AdvertisingData, RSSI: NSNumber, id: UUID) {
        self.serialNumber = advertising.serialNumber
        self.id = id.uuidString
        updateWithAdvertising(advertising, RSSI: RSSI)
    }
    
    /// Attempt to connect to the device.
    mutating func connect() {
        // Mark that we should maintain a connection to this device.
        // TODO - this doesn't seem to be propagating back to the UI??
        maintainingConnection = true
        
        if(connectionState != .connected) {
            DeviceManager.shared.connectToDevice(self)
        }
        
        // Update the DeviceManager's record for this device
        DeviceManager.shared.devices[self.id] = self
    }
    
    /// Mark that app should no longer attempt to maintain a connection to this device.
    mutating func disconnect() {
        // No longer attempt to maintain a connection to this device
        maintainingConnection = false
        
        // Disconnect if connected
        DeviceManager.shared.disconnectFromDevice(self)
        
        // Update the DeviceManager's record for this device
        DeviceManager.shared.devices[self.id] = self
    }
    
    mutating func updateConnectionState(_ state: ConnectionState) {
        connectionState = state
        
        // If we were disconnected and we should be maintaining a connection, attempt to reconnect.
        if(maintainingConnection && (connectionState == .disconnected || connectionState == .failed)) {
            DeviceManager.shared.connectToDevice(self)
        }
    }
    
    mutating func updateWithAdvertising(_ advertising: AdvertisingData, RSSI: NSNumber) {
        currentTemperatures = advertising.temperatures
        rssi = RSSI.intValue
        
        lastUpdateTime = Date()
    }
    
    mutating func updateDeviceStale() {
        stale = Date().timeIntervalSince(lastUpdateTime) > Constants.STALE_TIMEOUT
    }
    
    /// Updates the Device based on newly-received DeviceStatus message. Requests missing records.
    mutating func updateDeviceStatus(deviceStatus: DeviceStatus) {
        status = deviceStatus
        
        // Log the temperature data point
        temperatureLog.appendDataPoint(dataPoint:
                                        LoggedProbeDataPoint.fromDeviceStatus(deviceStatus:
                                                                                deviceStatus))
        
        // Check for missing records
        if let missingSequence = temperatureLog.firstMissingIndex(sequenceRangeStart: deviceStatus.minSequenceNumber,
                                                                  sequenceRangeEnd: deviceStatus.maxSequenceNumber) {
            // Track that the app is not up to date with the probe
            logsUpToDate = false
            
            // Request missing records
            DeviceManager.shared.requestLogsFrom(self,
                                                 minSequence: missingSequence,
                                                 maxSequence: deviceStatus.maxSequenceNumber)
            print("Requesting missing records starting with \(missingSequence)")
        } else {
            // If there were no gaps, mark that the logs are up to date
            logsUpToDate = true
        }
        
        print("Updating status! Temperature log size: \(temperatureLog.dataPoints.count)")
        
        lastUpdateTime = Date()
    }
    
    /// Processes an incoming log response (response to a manual request for prior messages)
    mutating func processLogResponse(logResponse: LogResponse) {
        temperatureLog.insertDataPoint(newDataPoint:
                                        LoggedProbeDataPoint.fromLogResponse(logResponse:
                                                                                logResponse))
    }
    
    
    ///////////////////////
    // Current value functions
    ///////////////////////
    
    /// Gets the current temperature of the sensor at the specified index.
    /// - param index: Index of temperature value (0-7)
    /// - param celsius: True for celsius, false for fahrenheit
    /// - returns: Requested temperature value
    func currentTemperature(index: Int, celsius: Bool) -> Double? {
        var result : Double?
        result = currentTemperatures?.values[index]
        if result != nil && celsius == false {
            // Convert to fahrenheit
            result = fahrenheit(celsius: result!)
        }
                    
        return result
    }

    /// Returns core temperature in Celcius
    func coreTempCelcius() -> Double {
        // TODO update this calculation
        guard let currentTemperatures = currentTemperatures else { return 0.0 }
        // For now default to the minimum of all sensors.
        return currentTemperatures.values.min() ?? 0.0
    }
    
    /// Returns surface temperature in Celcius
    func surfaceTempCelcius() -> Double {
        // TODO update this calculation
        guard let currentTemperatures = currentTemperatures else { return 0.0 }
        // For now default to the highest temperature < 100C
        return currentTemperatures.values.filter({ $0 < 100.0 }).sorted().last ?? currentTemperatures.values[0]
    }
    
    /// Returns ambient temperature in Celcius
    func ambientTempCelcius() -> Double {
        // TODO update this calculation
        // For now default to the last handle sensor for the core temp.
        guard let currentTemperatures = currentTemperatures else { return 0.0 }
        return currentTemperatures.values[7]
    }
    

    ///////////////////////
    // Average functions
    ///////////////////////

    /// Returns core average in Celcius
    func coreAverageCelcius() -> Double {
        // TODO update this calculation
        return 0.0
    }
    
    /// Returns surface average in Celcius
    func surfaceAverageCelcius() -> Double {
        // TODO update this calculation
        return 0.0
    }
    
    /// Returns ambient average in Celcius
    func ambientAverageCelcius() -> Double {
        // TODO update this calculation
        return 0.0
    }
    

    ///////////////////////
    // Maximum functions
    ///////////////////////

    /// Returns core maximum in Celcius
    func coreMaximumCelcius() -> Double {
        // TODO update this calculation
        return 0.0
    }
    
    /// Returns surface maximum in Celcius
    func surfaceMaximumCelcius() -> Double {
        // TODO update this calculation
        return 0.0
    }
    
    /// Returns ambient maximum in Celcius
    func ambientMaximumCelcius() -> Double {
        // TODO update this calculation
        return 0.0
    }
    

    ///////////////////////
    // Minimum functions
    ///////////////////////
    
    /// Returns core minimum in Celcius
    func coreMinimumCelcius() -> Double {
        // TODO update this calculation
        return 0.0
    }
    
    /// Returns surface minimum in Celcius
    func surfaceMinimumCelcius() -> Double {
        // TODO update this calculation
        return 0.0
    }
    
    /// Returns ambient minimum in Celcius
    func ambientMinimumCelcius() -> Double {
        // TODO update this calculation
        return 0.0
    }
    
    
    ///////////////////////
    // Relative Humidity functions
    ///////////////////////
    
    /// Returns relative humidity, if it could be calculated
    func relativeHumidity() -> Double {
        /*
        (1) Solve for E_d = 6.112 * e ^ ((17.502 * Ambient_Temp) / (240.97 + Ambient_Temp))
        (2) Solve for E_w = 6.112 * e ^ ((17.502 * Surface_Temp) / (240.92 + Surface_Temp))
        (3) Solve for Humidity = (E_w - N * (1 + 0.00115 * Surface_Temp) * (Ambient - Surface)) / E_d * 100
        */
        let E_d = 6.112 * pow(M_E, ((17.502 * ambientTempCelcius()) / (240.97 + ambientTempCelcius())))
        let N = 0.6687451584
        let E_w = 6.112 * pow(M_E, ((17.502 * surfaceTempCelcius()) / (240.92 + surfaceTempCelcius())))
        let rh = (E_w - N * (1 + 0.00115 * surfaceTempCelcius()) * (ambientTempCelcius() - surfaceTempCelcius()) / E_d * 100)
        
        // TODO - need to fix this equation
        
        return rh
    }
}

extension Device: Hashable {    
    static func == (lhs: Device, rhs: Device) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
