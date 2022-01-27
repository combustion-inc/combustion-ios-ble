//  Device.swift
//  Representation of a Combustion BLE Device

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
public class Device : ObservableObject {
    
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
    
    /// Device firmware version
    public internal(set) var firmareVersion: String?
    
    /// Current connection state of device
    @Published public internal(set) var connectionState: ConnectionState = .disconnected
    
    /// Signal strength to device
    @Published public internal(set) var rssi : Int = Int.min
    
    /// Tracks whether the app should attempt to maintain a connection to the device.
    @Published public internal(set) var maintainingConnection = false
    
    /// Tracks whether the data has gone stale (no new data in some time)
    @Published public internal(set) var stale = false
    
    /// Time at which device was last updated
    internal var lastUpdateTime = Date()
    
    public init(id: UUID) {
        self.id = id.uuidString
    }
}
    
extension Device {
    
    private enum Constants {
        /// Go stale after this many seconds of no Bluetooth activity
        static let STALE_TIMEOUT = 15.0
    }
    
    /// Attempt to connect to the device.
    public func connect() {
        // Mark that we should maintain a connection to this device.
        // TODO - this doesn't seem to be propagating back to the UI??
        maintainingConnection = true
        
        if(connectionState != .connected) {
            DeviceManager.shared.connectToDevice(self)
        }
    }
    
    /// Mark that app should no longer attempt to maintain a connection to this device.
    public func disconnect() {
        // No longer attempt to maintain a connection to this device
        maintainingConnection = false
        
        // Disconnect if connected
        DeviceManager.shared.disconnectFromDevice(self)
    }
    
    func updateConnectionState(_ state: ConnectionState) {
        connectionState = state
        
        // If we were disconnected and we should be maintaining a connection, attempt to reconnect.
        if(maintainingConnection && (connectionState == .disconnected || connectionState == .failed)) {
            DeviceManager.shared.connectToDevice(self)
        }
    }
    
    func updateDeviceStale() {
        stale = Date().timeIntervalSince(lastUpdateTime) > Constants.STALE_TIMEOUT
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
