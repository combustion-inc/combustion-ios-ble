//  MeatNetNode.swift

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

/// Representation of a Node on the MeatNet BLE repeater network. Various products
/// can be a MeatNet Node.
public class MeatNetNode: Device {
    
    public enum FeatureFlag: CaseIterable {
        case wifi
    }
    
    /// Serial Number
    @Published public internal(set) var serialNumberString: String?
    
    /// Dictionary of Devices connected to this Node's Network
    @Published public var devices: [String : Device] = [:]
    
    /// dfudevice type
    @Published public internal(set) var dfuType: DeviceType = .unknown
    
    /// Feature Flags
    @Published public internal(set) var featureFlags: [FeatureFlag]?
    
    /// Accessory
    @Published public internal(set) var accessory: Accessory?
    
    /// Meatnet node name
    public var name: String {
        let serialNumber = serialNumberString ?? ""
        
        switch(dfuType) {
        case .display:
            return "Display \(serialNumber)"
            
        case .charger:
            return "Booster \(serialNumber)"
            
        case .unknown:
            return "Repeater \(serialNumber)"
            
        case .thermometer:
            // Node should not have a DFU type of thermometer
            return "Unknown \(serialNumber)"
            
        case .gauge:
            return "Gauge \(serialNumber)"
        }
        
    }
    
    /// Dictionary of last time data was received for each connected device
    /// key = Device serial
    /// value = Last time advertising or status was recieved from device over this node
    private var lastTimeDataRecieved: [String: Date] = [:]
    
    private enum Constants {
        /// Number of seconds after which device should be removed from Node list
        static let DEVICE_REMOVE_CONNECTION_TIMEOUT = 30.0
        
        /// Minimum number of seconds before lastUpdateTime is updated
        static let MINIMUM_LAST_UPDATE_CHANGE = 1.0
    }
    
    private var deviceManager = DeviceManager.shared
    
    var lastMissingInfoCheck: Date?
    
    init(isConnectable: Bool, RSSI: NSNumber, identifier: UUID) {
        super.init(uniqueIdentifier: identifier.uuidString, bleIdentifier: identifier, RSSI: RSSI)
        
        updateMissingInfoIfRequired()
        updateLastUpdateTime()
    }
    
    init(_ advertising: AdvertisingData, isConnectable: Bool, RSSI: NSNumber, identifier: UUID) {
        super.init(uniqueIdentifier: identifier.uuidString, bleIdentifier: identifier, RSSI: RSSI)
        updateWithAdvertising(advertising, isConnectable: isConnectable, RSSI: RSSI)
    }
    
    func updateWithAdvertising(_ advertising: AdvertisingData, isConnectable: Bool, RSSI: NSNumber) {
        // Always update device RSSI and isConnectable flag
        
        self.rssi = RSSI.intValue
        self.isConnectable = isConnectable
        
        updateMissingInfoIfRequired()
        updateLastUpdateTime()
    }
    
    func updateDeviceStatus(deviceStatus: DeviceStatus, hopCount: HopCount? = nil) {
        accessory?.updateDeviceStatus(deviceStatus: deviceStatus, hopCount: hopCount)
        updateMissingInfoIfRequired()
        updateLastUpdateTime()
    }
    
    func dataReceivedFromDevice(_ device: Device?) {
        guard let device = device else { return }
        
        // Add connection to gauge
        devices[device.uniqueIdentifier] = device
        
        // Update last time data was recieved for device
        lastTimeDataRecieved[device.uniqueIdentifier] = Date()
        updateLastUpdateTime()
    }
    
    /// Removes device from device list
    private func removeConnectionToDevice(_ identifier: String) {
        devices[identifier] = nil
    }
    
    /// Returns true if node has connection to device.
    func hasConnectionToDevice(_ identifier: String) -> Bool {
        return devices[identifier] != nil
    }
    
    /// Updates whether the device is stale. Called on a timer interval by DeviceManager.
    override func updateDeviceStale() {
        for deviceSerial in devices.keys {
            if let lastUpdateTime = lastTimeDataRecieved[deviceSerial] {
                // If not data has been received from device for timeout length, then remove from list
                if(Date().timeIntervalSince(lastUpdateTime) > Constants.DEVICE_REMOVE_CONNECTION_TIMEOUT) {
                    removeConnectionToDevice(deviceSerial)
                }
            }
            else {
                // This should not happen, but if no update time for device, then remove from list
                removeConnectionToDevice(deviceSerial)
            }
        }
        
        super.updateDeviceStale()
    }
    
    func updateMissingInfoIfRequired() {
        var shouldCheckForMissingInfo: Bool = true
        
        // only attempt at most once every 10 seconds
        if let date = lastMissingInfoCheck, Date().timeIntervalSince(date) < 5 {
            shouldCheckForMissingInfo = false
        }
        
        guard shouldCheckForMissingInfo else { return }
        
        if featureFlags == nil, checkDeviceSupportForFeatureFlags() {
            deviceManager.readFeatureFlags(device: self)
        }
        
        lastMissingInfoCheck = Date()
    }
    
    func updateLastUpdateTime() {
        guard Date().timeIntervalSince(lastUpdateTime) > Constants.MINIMUM_LAST_UPDATE_CHANGE else { return }
        
        lastUpdateTime = Date()
    }
    
    /// Special handling for MeatNetNode model info.  Need to decode model info string
    /// to determine DFU type
    override func updateWithModelInfo(_ modelInfo: String) {
        super.updateWithModelInfo(modelInfo)
        
        if modelInfo.contains("Timer") {
            dfuType = .display
        }
        else if modelInfo.contains("Charger") {
            dfuType = .charger
        }
        else if modelInfo.contains("Gauge") {
            dfuType = .gauge
        }
    }
    
    func updateFeatureFlags(_ flags: FeatureFlags) {
        var updatedFlags: [FeatureFlag] = []
        
        if flags.wifi {
            updatedFlags.append(.wifi)
        }
        
        self.featureFlags = updatedFlags
    }
    
    func checkDeviceSupportForFeatureFlags() -> Bool {
        // if we can't determine the verison yet, we should check for feature flags
        guard let version = firmareVersion?.replacingOccurrences(of: "v", with: "") else { return true }
        
        return switch dfuType {
        case .display:
            version >= "2.1.0"
        case .charger:
            version >= "2.1.0"
        case .gauge:
            version >= "2.1.0"
        case .thermometer:
            false
        case .unknown:
            false
        }
    }
}
