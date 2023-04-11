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

class DFUManager {
    
    /// Singleton accessor for class
    static let shared = DFUManager()
    
    private struct DFU {
        let uniqueIdentifier: String
        let firmware: DFUFirmware
        let startedAt: Date
    }
    
    // Dictionary of currently active DFUs. Key = DFU advertising name
    private var runningDFUs = [String: DFU]()
    
    private var defaultDisplayFirmware: DFUFirmware?
    private var defaultThermometerFirmware: DFUFirmware?
    
    private enum Constants {
        static let THERMOMETER_DFU_NAME = "Thermom_DFU_"
        static let DISPLAY_DFU_NAME = "Display_DFU_"
        
        static let RETRY_TIME_DELAY = 10 // seconds
    }
    
    func setDisplayDFU(_ displayDFUFile: URL?) {
        guard let dfuFile = displayDFUFile else { return }
        
        do {
            defaultDisplayFirmware = try DFUFirmware(urlToZipFile: dfuFile)
        }
        catch { }
    }
    
    func setThermometerDFU(_ thermometerDFUFile: URL?) {
        guard let dfuFile = thermometerDFUFile else { return }
        
        do {
            defaultThermometerFirmware = try DFUFirmware(urlToZipFile: dfuFile)
        }
        catch { }
    }
    
    func uniqueIdentifierFrom(advertisingName: String) -> String? {
        return runningDFUs[advertisingName]?.uniqueIdentifier
    }
    
    static func bootloaderTypeFrom(advertisingName: String) -> CombustionProductType {
        if(advertisingName.contains(Constants.THERMOMETER_DFU_NAME)) {
            return CombustionProductType.probe
        }
        
        if(advertisingName.contains(Constants.DISPLAY_DFU_NAME)) {
            return CombustionProductType.display
        }
        
        return .unknown
    }
    
    func startDFU(peripheral: CBPeripheral, device: Device, firmware: DFUFirmware) -> DFUServiceController? {
        // Generate advertising name to use for bootloader during DFU
        let advertisingName = dfuAdvertisingName(for: device)
        
        return runDfu(peripheral: peripheral,
                      device: device,
                      advertisingName: advertisingName,
                      firmware: firmware)
    }
    
    
    func checkForStuckDFU(peripheral: CBPeripheral, advertisingName: String, device: Device) {
        if let runningDFU = runningDFUs[advertisingName] {
            // If more than 10 seconds have elapsed, then restart the DFU
            let differenceInSeconds = Int(Date().timeIntervalSince(runningDFU.startedAt))
            if(differenceInSeconds > Constants.RETRY_TIME_DELAY) {
                _ = runDfu(peripheral: peripheral,
                           device: device,
                           advertisingName: advertisingName,
                           firmware: runningDFU.firmware)
            }
        }
    }
    
    func retryDfuOnBootloader(peripheral: CBPeripheral, device: BootloaderDevice) {
        // Device is in bootloader, but DFU was not started by this app instance
        
        // Use advertising name to determine if device is Display or Thermometer
        // and restart DFU with the default file for each device type
        if let firmware = firmwareForBootloader(device) {
            _ = runDfu(peripheral: peripheral,
                       device: device,
                       advertisingName: device.advertisingName,
                       firmware: firmware)
        }
    }
    
    func clearCompletedDFU(device: Device) {
        // Find the running DFU for specified device
        let dfuTuple = runningDFUs.first { (_, value) in
            value.uniqueIdentifier == device.uniqueIdentifier
        }

        // Remove from runningDFUs dictionary if found
        if let key = dfuTuple?.key {
            runningDFUs.removeValue(forKey: key)
        }
    }
    
    private func dfuAdvertisingName(for device: Device) -> String {
        let typeName = (device is Probe) ? Constants.THERMOMETER_DFU_NAME : Constants.DISPLAY_DFU_NAME
        
        // Add random value to advertising name
        return typeName + String(format: "%05d", arc4random_uniform(100000))
    }
    
    private func runDfu(peripheral: CBPeripheral,
                        device: Device,
                        advertisingName: String,
                        firmware: DFUFirmware) -> DFUServiceController?  {
        let initiator = DFUServiceInitiator().with(firmware: firmware)
        
        initiator.delegate = device
        initiator.progressDelegate = device
        
        // Uncomment this to receive feedback from Nordic DFU library
        initiator.logger = device
        
        // Set the DFU bootloader advertising name
        initiator.alternativeAdvertisingName = advertisingName
        
        runningDFUs[advertisingName] = DFU(uniqueIdentifier: device.uniqueIdentifier,
                                           firmware: firmware,
                                           startedAt: Date())
        
        return initiator.start(target: peripheral)
    }
    
    private func firmwareForBootloader(_ device: BootloaderDevice) -> DFUFirmware? {
        if device.advertisingName.contains(Constants.DISPLAY_DFU_NAME) {
            return defaultDisplayFirmware
        }

        if device.advertisingName.contains(Constants.THERMOMETER_DFU_NAME) {
            return defaultThermometerFirmware
        }

        return nil
    }
    
}
