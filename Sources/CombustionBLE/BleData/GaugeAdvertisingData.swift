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
        static let SERIAL_RANGE = 3..<13
        static let TEMPERATURE_RANGE = 13..<15
        static let DEVICE_STATUS_RANGE = 15..<16
        static let RESERVED_RANGE = 16..<17
        static let HI_LO_STATUS_ALARM_RANGE = 17..<21
        // Byte 21 contains gauge preferences.
        static let ID_INDEX = 22
        
        static let COMBUSTION_VENDOR_ID = 0x09C7
    }
    
    // Zero is ambiguous with the reserved byte on older firmware; status confirms ID 1.
    let id: UInt8?
    var temperatures: GaugeTemperature
    var status: GaugeDetails
    var highLowAlarmStatus: HighLowAlarmStatus
    
    init(type: ProductType,
         serialNumber: String,
         temperature: GaugeTemperature,
         status: GaugeDetails,
         highLowAlarmStatus: HighLowAlarmStatus,
         id: UInt8? = nil) {
        self.id = id
        self.temperatures = temperature
        self.status = status
        self.highLowAlarmStatus = highLowAlarmStatus
        super.init(type: type, serialNumber: serialNumber)
    }
    
    static func populate(fromData data: Data?) -> (any AdvertisingData)? {
        guard let data = data else { return nil }
        guard data.count >= Constants.HI_LO_STATUS_ALARM_RANGE.upperBound else { return nil }
        
        // Vendor ID
        let rawVendorId = data.subdata(in: Constants.VENDOR_ID_RANGE)
        let vendorID = rawVendorId.withUnsafeBytes {
            $0.load(as: UInt16.self)
        }
        
        guard vendorID == Constants.COMBUSTION_VENDOR_ID else { return nil }
        
        let serialRaw = data.subdata(in: Constants.SERIAL_RANGE)
        let serialNumberString = String(decoding: serialRaw, as: UTF8.self).trimmingCharacters(in: CharacterSet(["\0"]))
                
        // Temperature (2 bytes) value
        let tempData = data.subdata(in: Constants.TEMPERATURE_RANGE)
        let temperatures = GaugeTemperature.fromRawData(data: tempData)
        
        let status = GaugeDetails.fromByte(data.subdata(in: Constants.DEVICE_STATUS_RANGE)[0])
        
        let hiLoAlarmData = data.subdata(in: Constants.HI_LO_STATUS_ALARM_RANGE)
        let hiLoAlarmStatus = HighLowAlarmStatus.fromData(hiLoAlarmData)
        
        return GaugeAdvertisingData(type: .gauge,
                                    serialNumber: serialNumberString,
                                    temperature: temperatures,
                                    status: status,
                                    highLowAlarmStatus: hiLoAlarmStatus,
                                    id: data.count > Constants.ID_INDEX && data[Constants.ID_INDEX] != 0 ? data[Constants.ID_INDEX] : nil)
    }
}

extension GaugeAdvertisingData {
    // Fake data initializer for previews
    public convenience init(fakeSerial: String) {
        self.init(type: .gauge,
                  serialNumber: fakeSerial,
                  temperature: GaugeTemperature.withFakeData(),
                  status: GaugeDetails.defaultValues(),
                  highLowAlarmStatus: HighLowAlarmStatus.defaultValues())
    }
    
    // Fake data initializer for Simulated Gauge
    public convenience init(fakeSerial: String, fakeTemperatures: GaugeTemperature) {
        self.init(type: .gauge,
                  serialNumber: fakeSerial,
                  temperature: fakeTemperatures,
                  status: GaugeDetails.defaultValues(),
                  highLowAlarmStatus: HighLowAlarmStatus.defaultValues())
    }
}
