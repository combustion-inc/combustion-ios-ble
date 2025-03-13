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
        
        super.init(uniqueIdentifier: identifier.uuidString, bleIdentifier: identifier, RSSI: RSSI)
        
        self.dfuAdvertisingName = advertisingName
    }
    
    // TODO JDJ delete me
    override func dfuComplete() {
        super.dfuComplete()
        
        // When DFU is complete, remove this device from Device Manager
        DeviceManager.shared.clearDevice(device: self)
    }
}
