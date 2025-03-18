//
//  BootloaderDevice.swift
//  
//
//  Created by Jesse Johnston on 12/19/22.
//

import Foundation


public class BootloaderDevice : Device {
    public let type: DeviceType
 
    init(advertisingName: String, RSSI: NSNumber, identifier: UUID) {
        type = DFUManager.bootloaderTypeFrom(advertisingName: advertisingName)
        
        super.init(uniqueIdentifier: identifier.uuidString, bleIdentifier: nil, RSSI: RSSI)
        
        // TODO JDJ this need more work
//        let firmware = DFUManager.defaultFirmware[type]
//        self.setDFUFirmware(<#T##dfuFirmware: DFUFirmware##DFUFirmware#>, dfuAdvertisingName: <#T##String#>)
//        self.dfuAdvertisingName = advertisingName
    }
    
    // TODO JDJ // When DFU is complete, remove this device from Device Manager

}
