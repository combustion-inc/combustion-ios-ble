//  GaugeAdvertisingData.swift
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

import Foundation

class GaugeAdvertisingData: NodeAdvertisingData {
    
    private enum Constants {
        // Locations of data in advertising packets
        static let VENDOR_ID_RANGE = 0..<2
        static let PRODUCT_TYPE_RANGE = 2..<3
        static let SERIAL_RANGE = 3..<7
        static let TEMPERATURE_RANGE = 7..<20
        static let DEVICE_STATUS_RANGE = 21..<22
        static let NETWORK_INFO_RANGE = 22..<23
        
        static let COMBUSTION_VENDOR_ID = 0x09C7
    }
    
    var temperatures: GaugeTemperature
    
    init(type: CombustionProductType, serialNumber: UInt32, hopCount: HopCount, temperature: GaugeTemperature) {
        self.temperatures = temperature
        super.init(type: type, serialNumber: serialNumber, hopCount: hopCount)
    }
    
    static func populate(fromData data: Data?) -> AdvertisingData? {
        guard let data = data else { return nil }
        guard data.count >= 20 else { return nil }
        
        // Vendor ID
        let rawVendorId = data.subdata(in: Constants.VENDOR_ID_RANGE)
        let vendorID = rawVendorId.withUnsafeBytes {
            $0.load(as: UInt16.self)
        }
        
        guard vendorID == Constants.COMBUSTION_VENDOR_ID else { return nil }
        
        // Product type (1 byte)
        let rawType = data.subdata(in: Constants.PRODUCT_TYPE_RANGE)
        let typeByte = [UInt8](rawType)
        let type = CombustionProductType(rawValue: typeByte[0]) ?? .unknown
        
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
        
        let serialNumber = value
        
        // Temperatures (8 13-bit) values
        let tempData = data.subdata(in: Constants.TEMPERATURE_RANGE)
        let temperatures = GaugeTemperature.fromRawData(data: tempData)
        
        // Decode network information
        var hopCount: HopCount
        if(data.count >= 23) {
            let byte = data.subdata(in: Constants.NETWORK_INFO_RANGE)[0]
            hopCount = HopCount.from(networkInfoByte: byte)
        } else {
            hopCount = HopCount.defaultValues()
        }
        
        return GaugeAdvertisingData(type: .gauge, serialNumber: serialNumber, hopCount: hopCount, temperature: temperatures)
    }
}
