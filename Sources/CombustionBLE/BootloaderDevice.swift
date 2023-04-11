//
//  File.swift
//  
//
//  Created by Jesse Johnston on 12/19/22.
//

import Foundation


public class BootloaderDevice : Device {
    public let type: CombustionProductType
    
    private(set) var advertisingName: String
 
    init(advertisingName: String, RSSI: NSNumber, identifier: UUID) {
        self.advertisingName = advertisingName
        
        type = DFUManager.bootloaderTypeFrom(advertisingName: advertisingName)
        
        super.init(uniqueIdentifier: identifier.uuidString, bleIdentifier: identifier, RSSI: RSSI)
    }
    
    override func dfuComplete() {
        super.dfuComplete()
        
        // When DFU is complete, remove this device from Device Manager
        DeviceManager.shared.clearDevice(device: self)
    }
}
