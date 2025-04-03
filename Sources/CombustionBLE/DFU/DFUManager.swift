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
    
    private var defaultFirmware: [DeviceType: DFUFirmware] = [:]
    
    // Unique identifier for device running DFU
    private var activeDfuUniqueIdentifier: String? {
        didSet {
            dfuIsInProgress = (activeDfuUniqueIdentifier != nil)
        }
    }
    
    private var bleManager = BleManager.shared
    
    private enum Constants {
        static let THERMOMETER_DFU_NAME = "Thermom_DFU_"
        static let DISPLAY_DFU_NAME = "Display_DFU_"
        static let CHARGER_DFU_NAME = "Charger_DFU_"
        static let GAUGE_DFU_NAME = "Gauge_DFU_"
        
        static let THERMOMETER_DEFAULT_BOOTLOADER = "CI Probe BL"
        
        static let RETRY_TIME_DELAY = 20 // seconds
        static let UNKNOWN_BOOTLOADER_DELAY = 20 // seconds
    }
    
    func setDefaultDFUForType(dfuFile: URL?, dfuType: DeviceType) {
        guard let dfuFile = dfuFile else { return }
        
        do {
            defaultFirmware[dfuType] = try DFUFirmware(urlToZipFile: dfuFile)
        }
        catch { }
    }
    
    static func bootloaderTypeFrom(advertisingName: String) -> DeviceType {
        if advertisingName == Constants.THERMOMETER_DEFAULT_BOOTLOADER {
            return .thermometer
        }
        else if(advertisingName.contains(Constants.THERMOMETER_DFU_NAME)) {
            return .thermometer
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
    
    func startDFU(peripheral: CBPeripheral, device: Device, firmware: DFUFirmware) {
        // Do not start a DFU if one is already in progress
        guard !dfuIsInProgress else { return }
        
        // Generate advertising name to use for bootloader during DFU
        let advertisingName = generateDfuAdvertisingNameFor(device)
        
        // Save advertising name and firmware
        device.setDFUFirmware(firmware)
        device.setDFUAdvertisingName(advertisingName)
        
        // Set device as having active DFU
        activeDfuUniqueIdentifier = device.uniqueIdentifier
        
        // Set DFU state
        device.updateDFUStatus(.requestName)
        
        // Send advertising name to device
        bleManager.sendDFURequest(identifier: device.bleIdentifier,
                                  request: .set(name: advertisingName))
    }
    
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
        unknownBootloader.setDFUFirmware(firmware)
        
        // Set as active DFU
        activeDfuUniqueIdentifier = unknownBootloader.uniqueIdentifier
    }
    
    func dfuCompleteFor(_ device: Device) {
        print("JDJ handleExecuteCommandResponseFor() : complete")
        device.updateDFUStatus(.complete)
        
        // Clear active DFU
        activeDfuUniqueIdentifier = nil
        
        // TODO JDJ // When DFU is complete, remove bootloader from Device Manager
        
        // TODO JDJ
//        // Find the running DFU for specified device
//        let dfuTuple = runningDFUs.first { (_, value) in
//            value.uniqueIdentifier == device.uniqueIdentifier
//        }
//
//        // Remove from runningDFUs dictionary if found
//        if let key = dfuTuple?.key {
//            runningDFUs.removeValue(forKey: key)
//        }
//        
//        // Update DFU in progress flag
//        dfuIsInProgress = !runningDFUs.isEmpty
    }
    
    func bootloaderDiscoveryComplete(_ device: Device) {
        device.updateDFUStatus(.selectCommandObject)
        
        device.updateDFUBytesTransferred(0)
        
        bleManager.sendRequestToBootloader(device, request: .selectCommandObject)
    }
    
    func handleDataFromAppFor(_ device: Device, data: Data) {
        
        // TODO JDJ check the response data
        
        if let response = ButtonlessDFUResponse(data) {
            print("JDJ handleDataFromAppFor : response \(response)")
        }
        
        if device.dfuStatus == .requestName {
            device.updateDFUStatus(.requestBootloader)
            bleManager.sendDFURequest(identifier: device.bleIdentifier,
                                             request: .enterBootloader)
        }
    }
    
    func handleDataFromBootloaderFor(_ device: Device, data: Data) {
        guard let response = SecureDFUResponse(data) else { return }
        
        print("JDJ handleDataFromBootloaderFor : response \(response)")
        
        switch device.dfuStatus {
        case .selectCommandObject:
            createInitPacketFor(device)
            
        case .createInitPacket:
            device.updateDFUStatus(.setPacketReceiptNotification)
            bleManager.sendRequestToBootloader(device, request: .setPacketReceiptNotification(value: 0))
            
        case .setPacketReceiptNotification:
            device.updateDFUStatus(.sendInitPacket)
            
            // Send Init packet
            if let initPacket = device.dfuFirmware?.initPacket {
                let initPacketLength = UInt32(initPacket.count)
                let data = initPacket.subdata(in: 0 ..< Int(initPacketLength))
                
                bleManager.sendPacketToBootloader(device, data: data)
            }
            
            // Send command to calculate checksum
            bleManager.sendRequestToBootloader(device, request: .calculateChecksumCommand)
            
        case .sendInitPacket:
            if let initPacket = device.dfuFirmware?.initPacket,
               let offset = response.offset,
               let crc = response.crc,
               verifyCRC(for: initPacket, range: 0..<Int(offset), matches: crc) {
                
                // Send command to execute
                device.updateDFUStatus(.executeCommand)
                bleManager.sendRequestToBootloader(device, request: .executeCommand)
            }
            else {
                print("TODO JDJ CRC failed")
            }

        case .executeCommand:
            handleExecuteCommandResponseFor(device, response: response)
            
        case .selectDataObject:
            if let maxSize = response.maxSize {
                // Save max size
                device.dfuMaxSize = maxSize
                
                // Send create data object
                sendCreateDataObject(device)
            }
            
        case .createDataObject:
            device.updateDFUStatus(.sendBlock)
            sendNextBlockTo(device)
            
        case .sendBlock:
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
                print("TODO JDJ CRC failed")
            }
            
        case .idle, .requestName, .requestBootloader, .complete:
            break
        }
    }
    
    private func createInitPacketFor(_ device: Device) {
        device.updateDFUStatus(.createInitPacket)
        
        if let firmware = device.dfuFirmware, let initPacket = firmware.initPacket {
            let initPacketLength = UInt32(initPacket.count)
            bleManager.sendRequestToBootloader(device, request: .createCommandObject(withSize: initPacketLength))
        }
    }
    
    private func sendCreateDataObject(_ device: Device) {
        guard let firmware = device.dfuFirmware else { return }
        
        device.updateDFUStatus(.createDataObject)
        
        let bytesLeft = UInt32(firmware.data.count) - device.dfuBytesTransferred
        let nextBlockSize = min(device.dfuMaxSize, bytesLeft)
        bleManager.sendRequestToBootloader(device, request: .createDataObject(withSize: nextBlockSize))
    }
    
    private func sendExecuteCommand(_ device: Device) {
        device.updateDFUStatus(.executeCommand)
        bleManager.sendRequestToBootloader(device, request: .executeCommand)
    }
    
    private func sendNextBlockTo(_ device: Device) {
        print("JDJ sendNextBlockTo() : dfuBytesTransferred \(device.dfuBytesTransferred) : maxSize \(device.dfuMaxSize) : packetSize \(device.dfuMaxPacketSize)")
        
        guard let firmware = device.dfuFirmware else { return }
        
        
        let totalBytesLeft = UInt32(firmware.data.count) - device.dfuBytesTransferred
        let bytesToSend = min(device.dfuMaxSize, totalBytesLeft)
        let range = Int(device.dfuBytesTransferred)..<Int(device.dfuBytesTransferred + bytesToSend)
        let packetSize = device.dfuMaxPacketSize
        let objectData = firmware.data.subdata(in: range)

        print("JDJ sendNextBlockTo() : range \(range) : data size = \(objectData.count)")
        
        var bytesSent: UInt32 = 0
        
        while bytesSent < bytesToSend {
            let bytesLeft = bytesToSend - bytesSent
            let packetLength = min(bytesLeft, packetSize)
            let packet = objectData.subdata(in: Int(bytesSent) ..< Int(bytesSent + packetLength))
            
            bleManager.sendPacketToBootloader(device, data: packet)
            
            bytesSent += packetLength
            
            // 25ms delay
            usleep(25000)
        }
        
        // After sending all data in block, send request to calculate checksum
        bleManager.sendRequestToBootloader(device, request: .calculateChecksumCommand)
    }
    
    private func handleExecuteCommandResponseFor(_ device: Device, response: SecureDFUResponse) {
        guard let firmware = device.dfuFirmware else { return }
        
        print("JDJ handleExecuteCommandResponseFor()")
        
        if response.error == .fwVersionFailure {
            // If the target device has rejected the first part, try sending the second part.
            // If may be that the SD+BL were flashed before and can't be updated again due to
            // `sd-req` and `bootloader-version` parameters set in the init packet.
            // In that case app update should be possible.
            if firmware.hasNextPart() {
                firmware.switchToNextPart()

                print("JDJ : Invalid system components. Trying to send application")

                // Verify the new part, which should also have the Init packet.
                guard firmware.initPacket != nil else {
                    print("JDJ : The init packet is required by the target device")
                    return
                }

                // Create init packet
                createInitPacketFor(device)
            }
        }
        else {
            // More data to send
            if device.dfuBytesTransferred < device.dfuFirmware?.data.count ?? 0 {
                device.updateDFUStatus(.selectDataObject)
                bleManager.sendRequestToBootloader(device, request: .selectDataObject)
            }
            else if firmware.hasNextPart() {
                // Nothing else to do, wait for device to disconnect and then reconnect
                // to handle firmware next part
                print("JDJ wait for device to disconnect")
            }
            else {
                dfuCompleteFor(device)
            }
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
    
    /**
     Verifies if the CRC-32 of the data from byte 0 to given offset matches the given CRC value.
     
     - parameter data:   Firmware or Init packet data.
     - parameter range:  Range of data that should be used for CRC calculation.
     - parameter crc:    The CRC obtained from the DFU Target to be matched.
     
     - returns: `True` if CRCs are identical, `false` otherwise.
     */
    private func verifyCRC(for data: Data, range: Range<Int>, matches crc: UInt32) -> Bool {
        print("JDJ verifyCRC range : \(range)")
        
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
