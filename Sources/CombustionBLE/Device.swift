//  Device.swift
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

/// Struct containing info about a thermometer device.
public struct Device {
    
    /// Enumeration representing the various connection states of the device
    public enum ConnectionState : CaseIterable {
        /// App is currently disconnected from device
        case disconnected
        /// App is attempting to connect via BLE to device
        case connecting
        /// App is currently connected via BLE to device
        case connected
        /// Attempt to connect to device failed
        case failed
    }
    
    /// String representation of device identifier (UUID)
    public private(set) var id: String
    
    /// Device serial number
    public private(set) var serialNumber: UInt32
    /// Current connection state of device
    public private(set) var connectionState: ConnectionState = .disconnected
    /// Signal strength to device
    public private(set) var rssi : Int = Int.min
    public private(set) var batteryLevel : Float = 0.0
    public private(set) var currentTemperatures: ProbeTemperatures?
    public private(set) var status: DeviceStatus?
    
    /// Tracks whether the app should attempt to maintain a connection to the probe.
    public private(set) var maintainingConnection = false
    
    /// Tracks whether the data has gone stale (no new data in some time)
    public private(set) var stale = false
    
    /// Tracks whether all logs on probe have been synced to the app
    public private(set) var logsUpToDate = false
    
    /// Time at which
    private var lastUpdateTime = Date()
    
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
        print("macAddress", macAddress)
        return String(format: "%012llX", macAddress)
    }
       
    /// Stores historical values of probe temperatures
    public private(set) var temperatureLog : ProbeTemperatureLog = ProbeTemperatureLog()
}
    
extension Device {
    
    private enum Constants {
        /// Go stale after this many seconds of no Bluetooth activity
        static let STALE_TIMEOUT = 15.0
    }
    
    public init(_ advertising: AdvertisingData, RSSI: NSNumber, id: UUID) {
        self.serialNumber = advertising.serialNumber
        self.id = id.uuidString
        updateWithAdvertising(advertising, RSSI: RSSI)
    }
    
    /// Attempt to connect to the device.
    public mutating func connect() {
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
    public mutating func disconnect() {
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
    public func currentTemperature(index: Int, celsius: Bool) -> Double? {
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
