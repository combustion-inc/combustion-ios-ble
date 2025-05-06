//  DFUManager.swift

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

import CoreBluetooth
import Foundation

class DFUManager {
    
    /// Singleton accessor for class
    static let shared = DFUManager()
    
    /// Flag that tracks if any DFUs are currently in progress
    @Published var dfuIsInProgress = false
    
    // Dictionary of when unknown bootloader were first detected
    // Key = Advertising name
    // Value = Time when first detected
    private var unknownBootloaderDetected = [String: Date]()
    
    private var defaultFirmware: [ProductType: DFUFirmware] = [:]
    
    // Unique identifier for device running DFU
    private var activeDfuUniqueIdentifier: String? {
        didSet {
            dfuIsInProgress = (activeDfuUniqueIdentifier != nil)
        }
    }
    
    private var bleManager = BleManager.shared
    
    private var responseTimer: Timer?
    
    private var analyticsLogger: AnalyticsLogger?
    
    private enum Constants {
        static let THERMOMETER_DFU_NAME = "Thermom_DFU_"
        static let DISPLAY_DFU_NAME = "Display_DFU_"
        static let CHARGER_DFU_NAME = "Charger_DFU_"
        static let GAUGE_DFU_NAME = "Gauge_DFU_"
        
        static let THERMOMETER_DEFAULT_BOOTLOADER = "CI Probe BL"
        
        static let RESPONSE_TIMEOUT = 10.0 // seconds
        static let UNKNOWN_BOOTLOADER_DELAY = 10 // seconds
    }
    
    /// Set the defualt DFU file for each device type.  These DFU files
    /// will be used when trying to recover a device that is stuck in
    /// the bootloader.
    /// - Parameters:
    ///   - dfuFile: DFU file
    ///   - dfuType: Product type
    func setDefaultDFUForType(dfuFile: URL?, dfuType: ProductType) {
        guard let dfuFile = dfuFile else { return }
        
        do {
            defaultFirmware[dfuType] = try DFUFirmware(urlToZipFile: dfuFile)
        }
        catch { }
    }
    
    /// Set the analytics logger
    /// - Parameter logger: Analytics logger
    func setAnalyticsLogger(_ logger: AnalyticsLogger) {
        analyticsLogger = logger
    }
    
    /// Determine device type from bootloader advertising name
    /// - Parameter advertisingName: Bootloader advertising name
    /// - Returns: Device type
    static func bootloaderTypeFrom(advertisingName: String) -> ProductType {
        if advertisingName == Constants.THERMOMETER_DEFAULT_BOOTLOADER {
            return .probe
        }
        else if(advertisingName.contains(Constants.THERMOMETER_DFU_NAME)) {
            return .probe
        }
        else if advertisingName.contains(Constants.DISPLAY_DFU_NAME) {
            return .display
        }
        else if advertisingName.contains(Constants.CHARGER_DFU_NAME) {
            return .charger
        }
        else if advertisingName.contains(Constants.GAUGE_DFU_NAME) {
            return .gauge
        }
        
        return .unknown
    }
    
    
    /// Start the DFU process
    /// - Parameters:
    ///   - peripheral: BLE peripheral associated with device
    ///   - device: Device to run DFU on
    ///   - firmware: DFU firmware to apply to device
    func startDFU(peripheral: CBPeripheral, device: Device, firmware: DFUFirmware) {
        // Do not start a DFU if one is already in progress
        guard !dfuIsInProgress else { return }
        
        // Log DFU start
        analyticsLogger?.logStartDFU()
        
        // Generate advertising name to use for bootloader during DFU
        let advertisingName = generateDfuAdvertisingNameFor(device)
        
        // Save advertising name and firmware
        device.initializeDFU(firmware)
        device.setDFUAdvertisingName(advertisingName)
        
        // Set device as having active DFU
        activeDfuUniqueIdentifier = device.uniqueIdentifier
        
        // Set DFU state
        updateDeviceDFUStatusFor(device, status: .requestName)
        
        // Send advertising name to device
        sendDFURequestTo(device, request: .set(name: advertisingName))
    }
    
    /// Handle the advertising packet from a device bootloader.  This will get called
    /// as part of the normal DFU process flow.  It will also get called if an
    /// unknown device bootloader is detected.
    /// - Parameters:
    ///   - device: Device that advertising as bootloader
    ///   - advertisingName: BLE advertising name
    func handleAdvertisingBootloader(device: Device, advertisingName: String) {
        // A device that is advertising from bootloader, but DFU was not initiated
        // from this app will instantiated as a BootloaderDevice
        if let unknownBootloader = device as? BootloaderDevice {
            handleUnkownBootloader(unknownBootloader, advertisingName: advertisingName)
        }
        
        // Check that this device matches active DFU before connecting to bootloader
        guard activeDfuUniqueIdentifier == device.uniqueIdentifier else { return }
        
        // Connect to bootloader
        guard let bootloaderIdentifier = device.bootloaderIdentifier else { return }
        bleManager.connect(identifier: bootloaderIdentifier)
    }
    
    /// Handle the advertising packet from and unknown bootloader device.
    /// - Parameters:
    ///   - unknownBootloader: Device
    ///   - advertisingName: BLE advertising name
    private func handleUnkownBootloader(_ unknownBootloader: BootloaderDevice, advertisingName: String) {
        // Save time that this unknown bootloader was first detected
        guard let firstDetected = unknownBootloaderDetected[advertisingName] else {
            unknownBootloaderDetected[advertisingName] = Date()
            return
        }
        
        // Delay before restarting DFU for unknown bootloader
        let secondsSinceFirstDetected = Int(Date().timeIntervalSince(firstDetected))
        guard secondsSinceFirstDetected > Constants.UNKNOWN_BOOTLOADER_DELAY else { return }
        
        // Check that no other DFU is active
        guard !dfuIsInProgress else { return }
        
        // Set the firmware on the bootloader device
        guard let firmware = defaultFirmware[unknownBootloader.type] else { return }
        unknownBootloader.initializeDFU(firmware)
        
        // Log the DFU restart
        analyticsLogger?.logRestartDFU()
        
        // Set as active DFU
        activeDfuUniqueIdentifier = unknownBootloader.uniqueIdentifier
    }
    
    /// BLE discovery is complete on device booloader
    /// - Parameter device: Device that discovery is complete on
    func bootloaderDiscoveryComplete(_ device: Device) {
        updateDeviceDFUStatusFor(device, status: .selectCommandObject)
        
        // Reset the bytes transferred
        device.updateDFUBytesTransferred(0)
        
        bleManager.sendRequestToBootloader(device, request: .selectCommandObject)
    }
    
    
    /// Handle the response data from application DFU service
    /// - Parameters:
    ///   - device: device that sent data
    ///   - data: DFU response data
    func handleDataFromAppFor(_ device: Device, data: Data) {
        // Check that device is expecting response
        guard device.dfuStatus == .requestName || device.dfuStatus == .requestBootloader else { return }
        
        // Stop the response timer
        responseTimer?.invalidate()
        
        // Check that response is valid
        guard let response = ButtonlessDFUResponse(data) else {
            updateDeviceDFUStatusFor(device, status: .failure(.invalidResponse))
            return
        }
        
        // Check that response was successful
        guard response.status == .success else {
            updateDeviceDFUStatusFor(device, status: .failure(.commandFailed))
            return
        }
        
        if device.dfuStatus == .requestName {
            // Update status
            updateDeviceDFUStatusFor(device, status: .requestBootloader)
            
            // Send the next command
            sendDFURequestTo(device, request: .enterBootloader)
        }
        else if device.dfuStatus == .requestBootloader {
            // Nothing else to do, wait for device to reboot into bootloader
        }
    }
    
    /// Handle the response data from bootloader DFU service
    /// - Parameters:
    ///   - device: device that sent data
    ///   - data: DFU response data
    func handleDataFromBootloaderFor(_ device: Device, data: Data) {
        // Check that response is valid
        guard let response = SecureDFUResponse(data) else {
            updateDeviceDFUStatusFor(device, status: .failure(.invalidResponse))
            return
        }
        
        // Check that response was successful, expect for execute command
        if response.status != .success && response.requestOpCode != .execute {
            updateDeviceDFUStatusFor(device, status: .failure(.commandFailed))
            return
        }
        
        switch device.dfuStatus {
        case .selectCommandObject:
            guard response.requestOpCode == .selectObject else { return }
            createInitPacketFor(device)
            
        case .createInitPacket:
            guard response.requestOpCode == .createObject else { return }
            updateDeviceDFUStatusFor(device, status: .setPacketReceiptNotification)
            bleManager.sendRequestToBootloader(device, request: .setPacketReceiptNotification(value: 0))
            
        case .setPacketReceiptNotification:
            guard response.requestOpCode == .setPRNValue else { return }
            sendInitPacketFor(device)
            
        case .sendInitPacket:
            guard response.requestOpCode == .calculateChecksum else { return }
            executeInitPacketFor(device, response: response)
            
        case .executeCommand:
            guard response.requestOpCode == .execute else { return }
            handleExecuteCommandResponseFor(device, response: response)
            
        case .selectDataObject:
            if let maxSize = response.maxSize {
                // Save max block size
                device.dfuMaxBlockSize = maxSize
                
                // Send create data object
                sendCreateDataObject(device)
            }
            
        case .createDataObject:
            updateDeviceDFUStatusFor(device, status: .sendBlock)
            
            // Send next data block on background thread
            DispatchQueue.global(qos: .background).async { [weak self] in
                self?.sendNextBlockTo(device)
            }
            
        case .sendBlock:
            executeBlockFor(device, response: response)
            
        case .idle, .requestName, .requestBootloader, .complete, .failure:
            break
        }
    }
    
    private func sendDFURequestTo(_ device: Device, request: ButtonlessDFURequest) {
        responseTimer?.invalidate()
        
        responseTimer = Timer.scheduledTimer(withTimeInterval: Constants.RESPONSE_TIMEOUT, repeats: false) { [weak self] _ in
            self?.updateDeviceDFUStatusFor(device, status: .failure(.commandTimeout))
            
            // There is a DFU bug in some versions of device firmware that will ignore DFU commands
            // from the iOS app if it was not the last connection made to device.  To work around this
            // issue, manually disconnect from device so that iOS app can reconnect and will be the
            // most recent BLE connection to device.
            device.disconnect()
        }
        
        bleManager.sendDFURequest(identifier: device.bleIdentifier,
                                  request: request)
    }
    
    private func createInitPacketFor(_ device: Device) {
        updateDeviceDFUStatusFor(device, status: .createInitPacket)
        
        if let firmware = device.dfuFirmware, let initPacket = firmware.initPacket {
            let initPacketLength = UInt32(initPacket.count)
            bleManager.sendRequestToBootloader(device, request: .createCommandObject(withSize: initPacketLength))
        }
    }
    
    private func sendInitPacketFor(_ device: Device) {
        updateDeviceDFUStatusFor(device, status: .sendInitPacket)
        
        // Send Init packet
        if let initPacket = device.dfuFirmware?.initPacket {
            let initPacketLength = UInt32(initPacket.count)
            let data = initPacket.subdata(in: 0 ..< Int(initPacketLength))
            
            bleManager.sendPacketToBootloader(device, data: data)
        }
        
        // Send command to calculate checksum
        bleManager.sendRequestToBootloader(device, request: .calculateChecksumCommand)
    }
    
    private func executeInitPacketFor(_ device: Device, response: SecureDFUResponse) {
        if let initPacket = device.dfuFirmware?.initPacket,
           let offset = response.offset,
           let crc = response.crc,
           verifyCRC(for: initPacket, range: 0..<Int(offset), matches: crc) {
            
            sendExecuteCommand(device)
        }
        else {
            // CRC check failed
            updateDeviceDFUStatusFor(device, status: .failure(.crcIncorrect))
        }
    }
    
    private func executeBlockFor(_ device: Device, response: SecureDFUResponse) {
        if let fimrwareData = device.dfuFirmware?.data,
           let offset = response.offset,
           let crc = response.crc,
           verifyCRC(for: fimrwareData,
                     range: 0..<Int(offset),
                     matches: crc) {
            
            // Update bytes transferred
            device.updateDFUBytesTransferred(offset)
            
            // Send command to execute
            sendExecuteCommand(device)
        }
        else {
            // CRC check failed
            updateDeviceDFUStatusFor(device, status: .failure(.crcIncorrect))
        }
    }
    
    private func sendCreateDataObject(_ device: Device) {
        guard let firmware = device.dfuFirmware else { return }
        
        updateDeviceDFUStatusFor(device, status: .createDataObject)
        
        let bytesLeft = UInt32(firmware.data.count) - device.dfuBytesTransferred
        let nextBlockSize = min(device.dfuMaxBlockSize, bytesLeft)
        bleManager.sendRequestToBootloader(device, request: .createDataObject(withSize: nextBlockSize))
    }
    
    private func sendExecuteCommand(_ device: Device) {
        updateDeviceDFUStatusFor(device, status: .executeCommand)
        bleManager.sendRequestToBootloader(device, request: .executeCommand)
    }
    
    private func sendNextBlockTo(_ device: Device) {
        guard let firmware = device.dfuFirmware else { return }
        
        let totalBytesLeft = UInt32(firmware.data.count) - device.dfuBytesTransferred
        let bytesToSend = min(device.dfuMaxBlockSize, totalBytesLeft)
        let range = Int(device.dfuBytesTransferred)..<Int(device.dfuBytesTransferred + bytesToSend)
        let packetSize = device.dfuMaxPacketSize
        let objectData = firmware.data.subdata(in: range)
        
        var bytesSent: UInt32 = 0
        
        while bytesSent < bytesToSend {
            let bytesLeft = bytesToSend - bytesSent
            let packetLength = min(bytesLeft, packetSize)
            let packet = objectData.subdata(in: Int(bytesSent) ..< Int(bytesSent + packetLength))
            
            bleManager.sendPacketToBootloader(device, data: packet)
            
            bytesSent += packetLength
            
            // Add a small delay (5ms) between each block
            usleep(5000)
        }
        
        // After sending all data in block, send request to calculate checksum
        bleManager.sendRequestToBootloader(device, request: .calculateChecksumCommand)
    }
    
    private func handleExecuteCommandResponseFor(_ device: Device, response: SecureDFUResponse) {
        guard let firmware = device.dfuFirmware else { return }
        
        if response.error == .fwVersionFailure {
            // If the target device has rejected the first part, try sending the second part.
            // If may be that the SD+BL were flashed before and can't be updated again due to
            // `sd-req` and `bootloader-version` parameters set in the init packet.
            // In that case app update should be possible.
            if firmware.hasNextPart() {
                firmware.switchToNextPart()
                
                // Verify the new part, which should also have the Init packet.
                guard firmware.initPacket != nil else {
                    updateDeviceDFUStatusFor(device, status: .failure(.invalidDFU))
                    return
                }
                
                // Create init packet
                createInitPacketFor(device)
            }
        }
        else {
            // More data to send
            if device.dfuBytesTransferred < device.dfuFirmware?.data.count ?? 0 {
                updateDeviceDFUStatusFor(device, status: .selectDataObject)
                bleManager.sendRequestToBootloader(device, request: .selectDataObject)
            }
            else if firmware.hasNextPart() {
                // Nothing else to do, wait for device to disconnect and then reconnect
                // to handle firmware next part
            }
            else {
                dfuCompleteFor(device)
            }
        }
    }
    
    private func dfuCompleteFor(_ device: Device) {
        updateDeviceDFUStatusFor(device, status: .complete)
        
        // Remove Bootloader devices when complete
        if let bootloader = device as? BootloaderDevice {
            DeviceManager.shared.clearDevice(device: bootloader)
        }
    }
    
    private func deviceTypeAdvertisingName(for device: Device) -> String {
        
        if let node = device as? MeatNetNode {
            if node.dfuType == .charger {
                return Constants.CHARGER_DFU_NAME
            }
            else if node.dfuType == .display {
                return Constants.DISPLAY_DFU_NAME
            }
            else if node.dfuType == .gauge {
                return Constants.GAUGE_DFU_NAME
            }
        }
        
        return Constants.THERMOMETER_DFU_NAME
    }
    
    private func updateDeviceDFUStatusFor(_ device: Device, status: DFUStatus) {
        device.updateDFUStatus(status)
        
        // Log DFU failure and completion
        if case let .failure(reason) = status {
            analyticsLogger?.logDFUFailure(reason: reason)
        }
        else if status == .complete {
            analyticsLogger?.logCompletedDFU()
        }
        
        // Clear DFU if status is no longer active
        if !status.isActive() {
            activeDfuUniqueIdentifier = nil
        }
    }
    
    /**
     Verifies if the CRC-32 of the data from byte 0 to given offset matches the given CRC value.
     
     - parameter data:   Firmware or Init packet data.
     - parameter range:  Range of data that should be used for CRC calculation.
     - parameter crc:    The CRC obtained from the DFU Target to be matched.
     
     - returns: `True` if CRCs are identical, `false` otherwise.
     */
    private func verifyCRC(for data: Data, range: Range<Int>, matches crc: UInt32) -> Bool {
        // Edge case where a different object might be flashed with a bigger init file.
        guard range.lowerBound >= 0 && range.upperBound <= data.count else {
            return false
        }
        // Get data form 0 up to the offset the peripheral has reported.
        let offsetData = data.subdata(in: range)
        let calculatedCRC = crc32(data: offsetData)
        
        // This returns true if the current data packet's CRC matches the current firmware's
        // packet CRC.
        return calculatedCRC == crc
    }
    
    private func generateDfuAdvertisingNameFor(_ device: Device) -> String {
        let typeName = deviceTypeAdvertisingName(for: device)
        
        // Add random value to advertising name
        return typeName + String(format: "%05d", arc4random_uniform(100000))
    }
}
