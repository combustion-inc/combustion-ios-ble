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
        let firmware: DFUFirmware
        let startedAt: Date
    }
    
    // Dictionary of currently active DFUs. Key = DFU advertising name
    private var runningDFUs = [String: DFU]()
    
    private var defaultDisplayFirmware: DFUFirmware?
    private var defaultThermometerFirmware: DFUFirmware?
    
    enum Constants {
        static let THERMOMETER_DFU_NAME = "Thermom_DFU_"
        static let DISPLAY_DFU_NAME = "Display_DFU_"
        
        static let RETRY_TIME_DELAY = 10 // seconds
    }
    
    func startDFU(peripheral: CBPeripheral, device: Device, firmware: DFUFirmware) -> DFUServiceController? {
        let initiator = DFUServiceInitiator().with(firmware: firmware)
        
        initiator.delegate = device
        initiator.progressDelegate = device
        
        // Uncomment this to receive feedback from Nordic DFU library
//        initiator.logger = device
        
        let typeName = (device is Probe) ? Constants.THERMOMETER_DFU_NAME : Constants.DISPLAY_DFU_NAME
        
        // Add random value to advertising name
        let advertisingName = typeName + String(format: "%05d", arc4random_uniform(100000))
        
        // Set the DFU bootloader advertising name
        initiator.alternativeAdvertisingName = advertisingName
        
        runningDFUs[advertisingName] = DFU(firmware: firmware, startedAt: Date())
        
        return initiator.start(target: peripheral)
    }
    
    func retryDfuOnBootloader(peripheral: CBPeripheral, advertisingName: String) {
        if let runningDFU = runningDFUs[advertisingName] {
            
            // If more than 10 seconds have elapsed, then restart the DFU
            let differenceInSeconds = Int(Date().timeIntervalSince(runningDFU.startedAt))
            if(differenceInSeconds > Constants.RETRY_TIME_DELAY) {
                restartDfu(firmware: runningDFU.firmware,
                           advertisingName: advertisingName,
                           peripheral: peripheral)
            }
        }
        else {
            // Device is in bootloader, but DFU was not started by this app instance
            
            // Use advertising name to determine if device is Display or Thermometer
            // and restart DFU with the default file for each device type
            
            if advertisingName.contains(Constants.DISPLAY_DFU_NAME),
               let firmware = defaultDisplayFirmware {
                restartDfu(firmware: firmware,
                           advertisingName: advertisingName,
                           peripheral: peripheral)
                
            } else if advertisingName.contains(Constants.THERMOMETER_DFU_NAME),
                      let firmware = defaultThermometerFirmware {
                
                restartDfu(firmware: firmware,
                           advertisingName: advertisingName,
                           peripheral: peripheral)
            }
        }
    }
    
    private func restartDfu(firmware: DFUFirmware, advertisingName: String, peripheral: CBPeripheral) {
        let initiator = DFUServiceInitiator().with(firmware: firmware)
        
        // Initialize DFU start time
        runningDFUs[advertisingName] = DFU(firmware: firmware, startedAt: Date())
        
        _ = initiator.start(target: peripheral)
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
    
}
