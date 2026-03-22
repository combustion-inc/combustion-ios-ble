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
    
    /// String representation of BLE device identifier (UUID), for this device's bootloader
    var bootloaderIdentifier: String?
    
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
    
    @Published public private(set) var dfuStatus: DFUStatus = .idle
    
    @Published public private(set) var dfuUploadPercentage: Double = 0
    
    private(set) var dfuAdvertisingName: String?
    
    private(set) var dfuFirmware: DFUFirmware?
    
    var dfuMaxBlockSize: UInt32 = 0
    
    private(set) var dfuBytesTransferred: UInt32 = 0
    
    private(set) var dfuMaxPacketSize: UInt32 = 20
    
    /// Last time device received an advertising packet or status notification
    @Published public var lastUpdateTime = Date()
    
    public private(set) var rssiEWMA = EWMA(span: 6)
    
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
    
    func setMaximumWriteValueLength(_ value: Int) {
        // Make the packet size the first word-aligned value that's less than the maximum
        dfuMaxPacketSize = UInt32(value) & 0xFFFFFFFC
    }
    
    func initializeDFU(_ dfuFirmware: DFUFirmware) {
        // Reset progress
        dfuUploadPercentage = 0
        
        self.dfuFirmware = dfuFirmware
    }
    
    func setDFUAdvertisingName(_ dfuAdvertisingName: String) {
        self.dfuAdvertisingName = dfuAdvertisingName
    }
    
    func updateDFUBytesTransferred(_ dfuBytesTransferred: UInt32) {
        guard let dfuFirmware else { return }
        
        self.dfuBytesTransferred = dfuBytesTransferred
        
        // Percentage already complete
        let completePercentage = Double(dfuFirmware.currentPart - 1) / Double(dfuFirmware.parts) * 100
        
        // Progress of current part
        let progress = Double(dfuBytesTransferred) / Double(dfuFirmware.data.count)
        
        // Percentage for this step
        let currentStepPercentage = progress / Double(dfuFirmware.parts) * 100
        
        // Total percentage
        self.dfuUploadPercentage = (completePercentage + currentStepPercentage)
    }
    
    func updateDFUStatus(_ status: DFUStatus) {
        dfuStatus = status
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
    
    /// Updates SKU and Lot number based on Model Info string.
    func updateWithModelInfo(_ modelInfo: String, seperator: String = ":") {
        // Parse the SKU and lot number, which are delimited by a ':'
        let parts = modelInfo.components(separatedBy: seperator)
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
            BleManager.shared.startFirmwareUpdate(device: self, dfu: dfu)
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
