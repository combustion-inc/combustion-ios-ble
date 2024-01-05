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
import NordicDFU

public enum DFUDeviceType {
    case thermometer
    case display
    case charger
    case unknown
}

class DFUManager {
    
    /// Singleton accessor for class
    static let shared = DFUManager()
    
    /// Flag that tracks if any DFUs are currently in progress
    @Published var dfuIsInProgress = false
    
    private struct DFU {
        let uniqueIdentifier: String
        let firmware: DFUFirmware
        let startedAt: Date
    }
    
    // Dictionary of currently active DFUs. Key = DFU advertising name
    private var runningDFUs = [String: DFU]()
    
    private var defaultFirmware: [DFUDeviceType: DFUFirmware] = [:]
    
    private enum Constants {
        static let THERMOMETER_DFU_NAME = "Thermom_DFU_"
        static let DISPLAY_DFU_NAME = "Display_DFU_"
        static let CHARGER_DFU_NAME = "Charger_DFU_"
        
        static let DFU_TIMEOUT = 180 // seconds
    }
    
    private init() {
        // Start a timer check for timed out DFUs
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] _ in
            checkForTimedOutDFUs()
        }
    }
    
    func setDefaultDFUForType(dfuFile: URL?, dfuType: DFUDeviceType) {
        guard let dfuFile = dfuFile else { return }
        
        do {
            defaultFirmware[dfuType] = try DFUFirmware(urlToZipFile: dfuFile)
        }
        catch { }
    }
    
    func uniqueIdentifierFrom(advertisingName: String) -> String? {
        return runningDFUs[advertisingName]?.uniqueIdentifier
    }
    
    static func bootloaderTypeFrom(advertisingName: String) -> DFUDeviceType {
        if(advertisingName.contains(Constants.THERMOMETER_DFU_NAME)) {
            return .thermometer
        }
        
        if(advertisingName.contains(Constants.DISPLAY_DFU_NAME)) {
            return .display
        }
        
        if(advertisingName.contains(Constants.CHARGER_DFU_NAME)) {
            return .charger
        }
        
        return .unknown
    }
    
    func startDFU(peripheral: CBPeripheral, device: Device, firmware: DFUFirmware) {
        // Generate advertising name to use for bootloader during DFU
        let advertisingName = dfuAdvertisingName(for: device)
        
        print("DFU DFUManager startDFU(): \(advertisingName)")
        
        runDfu(peripheral: peripheral,
               device: device,
               advertisingName: advertisingName,
               firmware: firmware)
    }
    
    
    func checkForStuckDFU(peripheral: CBPeripheral, advertisingName: String, device: Device) {
        if let runningDFU = runningDFUs[advertisingName] {
            // If more timeout has elapsed, then cancel the DFU
            let differenceInSeconds = Int(Date().timeIntervalSince(runningDFU.startedAt))
            print("DFU checkForStuckDFU : \(advertisingName) : \(differenceInSeconds)")
            
            // TODO JDJ delete this function
            
//            if(differenceInSeconds > Constants.DFU_TIMEOUT) {
//                clearInProgressDFU(device: device)
//            }
        }
    }
    
    
    private func checkForTimedOutDFUs() {
        for advertisingName in runningDFUs.keys {
            if let runningDFU = runningDFUs[advertisingName] {
                
                // If timeout has elapsed, then remove DFU from dictionary
                let differenceInSeconds = Int(Date().timeIntervalSince(runningDFU.startedAt))
                
                if(differenceInSeconds > Constants.DFU_TIMEOUT) {
                    print("DFU checkForTimedOutDFUs : \(advertisingName) has timed out")
                    
                    runningDFUs[advertisingName] = nil
                    
                    // Update DFU in progress flag
                    dfuIsInProgress = !runningDFUs.isEmpty
                }
            }
        }
    }
    
    func retryDfuOnBootloader(peripheral: CBPeripheral, device: BootloaderDevice) {
        // Device is in bootloader, but DFU was not started by this app instance
        
        print("DFU retryDfuOnBootloader() : disabling retry")
        
//        // Use advertising name to determine if device is Display or Thermometer
//        // and restart DFU with the default file for each device type
//        if let firmware = defaultFirmware[device.type] {
//            runDfu(peripheral: peripheral,
//                   device: device,
//                   advertisingName: device.advertisingName,
//                   firmware: firmware)
//        }
    }
    
    func clearInProgressDFU(device: Device) {
        print("DFU clearInProgressDFU() : aborted \(device.dfuServiceController?.aborted)")
        
        // Clear service controller
        device.dfuServiceController = nil
        
        // Find the running DFU for specified device
        let dfuTuple = runningDFUs.first { (_, value) in
            value.uniqueIdentifier == device.uniqueIdentifier
        }

        // Remove from runningDFUs dictionary if found
        if let key = dfuTuple?.key {
            runningDFUs.removeValue(forKey: key)
        }
        
        // Update DFU in progress flag
        dfuIsInProgress = !runningDFUs.isEmpty
    }
    
    private func dfuAdvertisingName(for device: Device) -> String {
        let typeName = deviceTypeAdvertisingName(for: device)
        
        // Add random value to advertising name
        return typeName + String(format: "%05d", arc4random_uniform(100000))
    }
    
    private func deviceTypeAdvertisingName(for device: Device) -> String {

        if let node = device as? MeatNetNode {
            if node.dfuType == .charger {
                return Constants.CHARGER_DFU_NAME
            }
            else if(node.dfuType == .display) {
                return Constants.DISPLAY_DFU_NAME
            }
        }

        return Constants.THERMOMETER_DFU_NAME
    }
    
    private func runDfu(peripheral: CBPeripheral,
                        device: Device,
                        advertisingName: String,
                        firmware: DFUFirmware) {
        
        print("DFU DFUManager runDfu(): \(advertisingName)")
        
        let initiator = DFUServiceInitiator().with(firmware: firmware)
        
        initiator.delegate = device
        initiator.progressDelegate = device
        
        // Uncomment this to receive feedback from Nordic DFU library
        initiator.logger = device
        
        // Set the DFU bootloader advertising name
        initiator.alternativeAdvertisingName = advertisingName
        
        // Adding Nordic recommended delay
        print("DFU DFUManager runDfu(): \(advertisingName) : setting dataObjectPreparationDelay to 0.75")
        initiator.dataObjectPreparationDelay = 0.75
        
        runningDFUs[advertisingName] = DFU(uniqueIdentifier: device.uniqueIdentifier,
                                           firmware: firmware,
                                           startedAt: Date())
        
        // Update DFU in progress flag
        dfuIsInProgress = true
        
        // Save the service controller
        device.dfuServiceController = initiator.start(target: peripheral)
    }
    
}
