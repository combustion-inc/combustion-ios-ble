//  AdvertisingData.swift

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

/// Enumeration of Combustion, Inc. product types.
public enum CombustionProductType: UInt8 {
    case UNKNOWN = 0x00
    case PROBE = 0x01
    case NODE = 0x02
}


/// Struct containing advertising data received from device.
public struct AdvertisingData {
    /// Type of Combustion product
    public let type: CombustionProductType
    /// Product serial number
    public let serialNumber: UInt32
    /// Latest temperatures read by device
    public let temperatures: ProbeTemperatures
    /// Prode ID
    public let id: ProbeID
    /// Probe Color
    public let color: ProbeColor
    /// Probe mode
    public let mode: ProbeMode

    private enum Constants {
        // Locations of data in advertising packets
        static let PRODUCT_TYPE_RANGE = 2..<3
        static let SERIAL_RANGE = 3..<7
        static let TEMPERATURE_RANGE = 7..<20
        static let MODE_COLOR_ID_RANGE = 20..<21
    }
}

extension AdvertisingData {
    init?(fromData : Data?) {
        guard let data = fromData else { return nil }
        guard data.count >= 20 else { return nil }
        
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
        
        // Decode Probe ID and Color if its present in the advertising packet
        if(data.count >= 21) {
            let modeIdColorData  = data.subdata(in: Constants.MODE_COLOR_ID_RANGE)
            id = ProbeID.fromRawData(data: modeIdColorData)
            color = ProbeColor.fromRawData(data: modeIdColorData)
            mode = ProbeMode.fromRawData(data: modeIdColorData)
        }
        else {
            id = .ID1
            color = .COLOR1
            mode = .Normal
        }
    }
}


extension AdvertisingData {
    // Fake data initializer for previews
    public init(fakeSerial: UInt32) {
        type = .PROBE
        temperatures = ProbeTemperatures.withFakeData()
        serialNumber = fakeSerial
        id = .ID1
        color = .COLOR1
        mode = .Normal
    }
    
    // Fake data initializer for Simulated Probe
    public init(fakeSerial: UInt32, fakeTemperatures: ProbeTemperatures) {
        type = .PROBE
        temperatures = fakeTemperatures
        serialNumber = fakeSerial
        id = .ID1
        color = .COLOR1
        mode = .Normal
    }
}
