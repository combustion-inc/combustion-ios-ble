//
//  AdvertisingData.swift
//  Needle
//
//  Created by Jesse Johnston on 2/10/20.
//  Copyright © 2021 Combustion Inc. All rights reserved.
//

import Foundation

public enum CombustionProductType: UInt8 {
    case UNKNOWN = 0x00
    case PROBE = 0x01
    case NODE = 0x02
}

// TODO: update this with device type when feature/ble-network brabch
// is merged into probe firmware project

public struct AdvertisingData {
    public let type: CombustionProductType
    public let serialNumber: UInt32
    public let temperatures: ProbeTemperatures

    private enum Constants {
        // Locations of data in advertising packets
        static let PRODUCT_TYPE_RANGE = 2..<3
        static let SERIAL_RANGE = 3..<7
        static let TEMPERATURE_RANGE = 7..<20
    }
}

extension AdvertisingData {
    init?(fromData : Data?) {
        guard let data = fromData else { return nil }
        guard data.count >= 19 else { return nil }
        
        // Product type (1 byte)
        let rawType = data.subdata(in: Constants.PRODUCT_TYPE_RANGE)
        let typeByte = [UInt8](rawType)
        type = CombustionProductType(rawValue: typeByte[0]) ?? .UNKNOWN
        
        // Device Serial number (4 bytes)
        // Reverse the byte order (this is a little-endian packed bitfield)
        let rawSerial = data.subdata(in: Constants.SERIAL_RANGE)
        var revSerial : [UInt8] = []
        for byte in rawSerial {
            revSerial.insert(byte as UInt8, at: 0)
        }
        
        let serialArray = [UInt8](revSerial)
        var value: UInt32 = 0
        for byte in serialArray {
            value = value << 8
            value = value | UInt32(byte)
        }
        
        serialNumber = value
        
        
        // Temperatures (8 13-bit) values
        let tempData = data.subdata(in: Constants.TEMPERATURE_RANGE)
        temperatures = ProbeTemperatures.fromRawData(data: tempData)
    }
}


extension AdvertisingData {
    // Fake data initializer for previews
    init?(fakeSerial: UInt32) {
        type = .PROBE
        temperatures = ProbeTemperatures.withFakeData()
        serialNumber = fakeSerial
    }
}
