//  ConnectionManager.swift

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

class ConnectionManager {
    
    /// Tracks whether MeatNet is enabled.
    var meatNetEnabled : Bool = false
    
    /// Tracks whether DFU mode is enabled.
    var dfuModeEnabled : Bool = false
    
    /// List of device serial numbers to connect to
    private(set) var deviceAllowList: Set<String>? = nil
    
    private var connectionTimers: [String: Timer] = [:]
    private var lastStatusUpdate: [String: Date] = [:]
    
    /// Number of seconds after which a direct connection should be made to probe
    private let DEVICE_STATUS_STALE_TIMEOUT = 10.0
    
    /// Sets the allow list for devices.  Framework will only connect to devices
    /// in the allow list and nodes that are advertising data from device in whitelist.
    /// - param whiteList: White list of device serial numbers
    func setDeviceAllowList(_ allowList: Set<String>) {
        deviceAllowList = allowList
    }
    
    func receivedDeviceAdvertising(_ device: Device?) {
        // Nothing to do if already connected to probe
        guard let device = device,
              device.connectionState != .connected else { return }
        
        var deviceStatusStale = true
        if let lastUpdateTime = lastStatusUpdate[device.uniqueIdentifier] {
            deviceStatusStale = Date().timeIntervalSince(lastUpdateTime) > DEVICE_STATUS_STALE_TIMEOUT
        }
        
        if dfuModeEnabled { // In DFU mode, connect to device if its in allow list
            if deviceInAllowList(device) {
                device.connect()
            }
        }
        else if !meatNetEnabled { // If meatnet is not enabled, always connect to device
            device.connect()
        }
        else { // When MeatNet is enabled and the device data is stale, then connect to it
            if deviceInAllowList(device) &&
                deviceStatusStale &&
                (connectionTimers[device.uniqueIdentifier] == nil) {
                
                // Start timer to connect to probe after delay
                connectionTimers[device.uniqueIdentifier] = Timer.scheduledTimer(withTimeInterval: 3, repeats: false, block: { [weak self] _ in
                    
                    if let device = self?.getDeviceWithIdentifier(device.uniqueIdentifier) {
                        device.connect()
                    }
                    
                    // Clear timer
                    self?.connectionTimers[device.uniqueIdentifier] = nil
                })
            }
        }
    }
    
    func receivedDeviceAdvertising(_ device: Device?, from node: MeatNetNode) {
        // Nothing to do if already connected to node
        guard node.connectionState != .connected else { return }
        
        if dfuModeEnabled { // DFU mode
            // Connect to node if its within the DFU range
            if node.withinProximityRange {
                node.connect()
            }
            // Or if node is connected to device is in allow list
            else if let device = device, deviceInAllowList(device) {
                node.connect()
            }
        }
        else if meatNetEnabled { // Meatnet is enabled
            // Connect to all Nodes that are advertising devices in allow list
            if let device = device,
               meatNetEnabled,
               deviceInAllowList(device) {
                node.connect()
            }
        }
    }
    
    func receivedStatusFor(_ device: Device, node: MeatNetNode?) {
        guard let identifier = device.uniqueIdentifier as? String else { return }
        
        lastStatusUpdate[identifier] = Date()
        
        // Track that data was recieved for device on node
        node?.dataReceivedFromDevice(device)
        
        // If also receiving status for a Probe from MeatNet and DFU mode is disabled,
        // then disconnect from the Probe to conserve the Probe's available inbound
        // connections and reduce the impact on its battery life.
        if let _ = device as? Probe {
            let directProbeConnection = (node == nil)
            if !directProbeConnection && meatNetEnabled && !dfuModeEnabled {
                
                if let device = getDeviceWithIdentifier(identifier),
                   device.connectionState == .connected {
                    device.disconnect()
                }
            }
        }
    }
    
    private func getDeviceWithIdentifier(_ identifier: String) -> Device? {
        let devices = DeviceManager.shared.getDevices()
        return devices.filter { $0.uniqueIdentifier == identifier}.first
    }
    
    private func deviceInAllowList(_ device: Device) -> Bool {
        // If allowList is nil, then return true
        guard let allowList = deviceAllowList else { return true }
        
        if let device = device as? Probe {
            return allowList.contains(device.serialNumberString)
        }
        else if let accessory = (device as? MeatNetNode)?.accessory {
            return allowList.contains(accessory.serialNumberString)
        }
        else {
            return false
        }
    }
}
