//
//  Device.swift
//  Representation of a Probe Device
//
//  Created by Jason Machacek on 2/5/20.
//  Copyright © 2021 Combustion Inc. All rights reserved.
//

import Foundation

/// Struct containing info about a thermometer device.
public struct Device {
    
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
    
    var name: String {
        return String(format: "%08X", serialNumber)
    }
    
    var macAddress: UInt64 {
        return (UInt64(serialNumber) * 10000 + 6912) | 0xC00000000000
    }
    
    var macAddressString: String {
        print("macAddress", macAddress)
        return String(format: "%012llX", macAddress)
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
}

extension Device: Hashable {
    public static func == (lhs: Device, rhs: Device) -> Bool {
        return lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
