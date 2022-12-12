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
import NordicDFU

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
    public var identifier: String
    
    /// Device firmware version
    @Published public internal(set) var firmareVersion: String?
    
    /// Device hardware revision
    @Published public internal(set) var hardwareRevision: String?
    
    /// Current connection state of device
    @Published public internal(set) var connectionState: ConnectionState = .disconnected
    
    /// Connectable flag set in advertising packet
    @Published public internal(set) var isConnectable = false
    
    /// Signal strength to device
    @Published public internal(set) var rssi: Int
    
    /// Tracks whether the app should attempt to maintain a connection to the device.
    @Published public private(set) var maintainingConnection = false
    
    /// Tracks whether the data has gone stale (no new data in some time)
    @Published public private(set) var stale = false
    
    /// DFU state
    @Published public private(set) var dfuState: DFUState?
    
    public struct DFUErrorMessage {
        public let error: DFUError
        public let message: String
    }
    
    /// DFU error message
    @Published public private(set) var dfuError: DFUErrorMessage?

    public struct DFUUploadProgress {
        public let part: Int
        public let totalParts: Int
        public let progress: Int
    }
    
    /// DFU Upload progress
    @Published public private(set) var dfuUploadProgress: DFUUploadProgress?
    
    private var dfuServiceController: DFUServiceController? = nil
    
    /// Time at which device was last updated
    internal var lastUpdateTime = Date()
    
    public init(identifier: UUID, RSSI: NSNumber) {
        self.identifier = identifier.uuidString
        self.rssi = RSSI.intValue
    }
    
    func updateConnectionState(_ state: ConnectionState) {
        connectionState = state
        
        // Clear firmware version and DFU state on disconnect
        if(connectionState == .disconnected) {
            firmareVersion = nil
        }
        
        // If we were disconnected and we should be maintaining a connection, attempt to reconnect.
        if(maintainingConnection && (connectionState == .disconnected || connectionState == .failed)) {
            DeviceManager.shared.connectToDevice(self)
        }
    }
    
    func updateDeviceStale() {
        stale = Date().timeIntervalSince(lastUpdateTime) > Constants.STALE_TIMEOUT
        
        
        // If device data is stale, assume its not longer connectable
        if(stale) {
            isConnectable = false
        }
    }
    
    public func isDFURunning() -> Bool {
        guard let dfuState = dfuState else { return false }
        
        if(dfuState == .completed) {
            return false
        }
        
        return true
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
    
    public func runSoftwareUpgrade(dfuFile: URL) -> Bool {
        do {
            let dfu = try DFUFirmware(urlToZipFile: dfuFile)
            dfuServiceController = BleManager.shared.startFirmwareUpdate(device: self, dfu: dfu)
            return true
        }
        catch {
            return false
        }
    }
}


extension Device: Hashable {
    public static func == (lhs: Device, rhs: Device) -> Bool {
        return lhs.identifier == rhs.identifier
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
}

extension Device: DFUServiceDelegate {
    public func dfuStateDidChange(to state: DFUState) {
        dfuState = state
    }
    
    public func dfuError(_ error: DFUError, didOccurWithMessage message: String) {
        dfuError = DFUErrorMessage(error: error, message: message)
        
        dfuServiceController?.restart()
    }
}

extension Device: DFUProgressDelegate {
    public func dfuProgressDidChange(for part: Int,
                                     outOf totalParts: Int,
                                     to progress: Int,
                                     currentSpeedBytesPerSecond: Double,
                                     avgSpeedBytesPerSecond: Double) {
        dfuUploadProgress = DFUUploadProgress(part: part, totalParts: totalParts, progress: progress)
    }
}

extension Device: LoggerDelegate {
    public func logWith(_ level: NordicDFU.LogLevel, message: String) {
        NSLog("LoggerDelegate : \(message)")
    }
}
