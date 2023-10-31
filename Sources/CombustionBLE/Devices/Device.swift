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
open class Device : ObservableObject {
    
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

    /// String representation of BLE device identifier (UUID), if able to see this device's
    /// adveritsing messages directly.
    public var bleIdentifier: String?
    
    /// Unique identifier for this device, which is Serial Number for Probes, or BLE device
    /// identifier for Nodes.
    public var uniqueIdentifier: String
    
    /// Device firmware version
    @Published public internal(set) var firmareVersion: String?
    
    /// Device hardware revision
    @Published public internal(set) var hardwareRevision: String?
    
    /// Device SKU
    @Published public internal(set) var sku: String?
    
    /// Device lot #
    @Published public internal(set) var manufacturingLot: String?
    
    /// Current connection state of device
    @Published public internal(set) var connectionState: ConnectionState = .disconnected
    
    /// Connectable flag set in advertising packet
    @Published public internal(set) var isConnectable = false
    
    /// Signal strength to device
    @Published public internal(set) var rssi: Int {
        didSet {
            handleRSSIUpdate()
        }
    }
    
    /// Within Proximity Identification range
    @Published public internal(set) var withinProximityRange: Bool = false
    
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
    
    private var rssiEWMA = EWMA(span: 6)
    
    /// Time at which device was last updated
    internal var lastUpdateTime = Date()
    
    public init(uniqueIdentifier: String, bleIdentifier: UUID?, RSSI: NSNumber?) {
        self.uniqueIdentifier = uniqueIdentifier
        
        if let bleIdentifier = bleIdentifier {
            self.bleIdentifier = bleIdentifier.uuidString
        }
        
        if let RSSI = RSSI {
            self.rssi = RSSI.intValue
        } else {
            self.rssi = Constants.MIN_RSSI
        }
    }
    
    func updateConnectionState(_ state: ConnectionState) {
        connectionState = state
        
        // Clear firmware version and RSSI on disconnect
        if(connectionState == .disconnected) {
            firmareVersion = nil
            rssi = Constants.MIN_RSSI
        }
        
        // If we were disconnected and we should be maintaining a connection, attempt to reconnect.
        if(maintainingConnection && (connectionState == .disconnected || connectionState == .failed)) {
            connect()
        }
    }
    
    /// Updates whether the device is stale. Called on a timer interval by DeviceManager.
    func updateDeviceStale() {
        stale = Date().timeIntervalSince(lastUpdateTime) > Constants.STALE_TIMEOUT
        
        
        // If device data is stale, assume its not connectable
        // and clear RSSI
        if(stale) {
            isConnectable = false
            rssi = Constants.MIN_RSSI
        }
    }
    
    public func isDFURunning() -> Bool {
        guard let dfuState = dfuState else { return false }
        
        if(dfuState == .completed) {
            return false
        }
        
        return true
    }
    
    /// Called when DFU has completed
    func dfuComplete() {
        DFUManager.shared.clearCompletedDFU(device: self)
    }
    
    /// Updates SKU and Lot number based on Model Info string.
    func updateWithModelInfo(_ modelInfo: String) {
        // Parse the SKU and lot number, which are delimited by a ':'
        let parts = modelInfo.components(separatedBy: ":")
        if parts.count == 2 {
            self.sku = parts[0]
            self.manufacturingLot = parts[1]
        }
    }
}
    
extension Device {
    
    private enum Constants {
        /// Go stale after this many seconds of no Bluetooth activity
        static let STALE_TIMEOUT = 15.0
        
        /// Minimum possible value for RSSI
        static internal let MIN_RSSI = -128
        
        // RSSI limits for proximity check
        static let PROXIMITY_RSSI_MAX: Float = -48.0
        static let PROXIMITY_RSSI_MIN: Float = -55.0
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
    
    private func handleRSSIUpdate() {
        // Ignore unreasonable values
        if(rssi > 0) {
            return
        }
        
        if(rssi == Constants.MIN_RSSI) {
            // Reset values if RSSI is set to MIN
            rssiEWMA.reset()
            withinProximityRange = false
        }
        else {
            // Update RSSI EWMA
            rssiEWMA.put(value: Float(rssi))
            
            // Check RSSI proximity
            if(withinProximityRange && rssiEWMA.get() < Constants.PROXIMITY_RSSI_MIN) {
                withinProximityRange = false
            }
            else if(!withinProximityRange && rssiEWMA.get() > Constants.PROXIMITY_RSSI_MAX) {
                withinProximityRange = true
            }
        }
    }
}


extension Device: Hashable {
    public static func == (lhs: Device, rhs: Device) -> Bool {
        return lhs.uniqueIdentifier == rhs.uniqueIdentifier
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(uniqueIdentifier)
    }
}

extension Device: DFUServiceDelegate {
    public func dfuStateDidChange(to state: DFUState) {
        dfuState = state
        
        if(dfuState == .completed) {
            dfuComplete()
        }
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
