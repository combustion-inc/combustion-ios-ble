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
        
        setDFUAdvertisingName(advertisingName)
    }
    
    // TODO JDJ // When DFU is complete, remove this device from Device Manager
}
