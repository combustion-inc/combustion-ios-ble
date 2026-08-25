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

public protocol AdvertisingData {
    
    associatedtype SerialNumberType
    
    /// Type of Combustion product
    var type: ProductType { get }
    /// Product serial number
    var serialNumber: SerialNumberType { get }
}

extension AdvertisingData {
    var serialNumberString: String {
        return "\(serialNumber)"
    }
}

class NodeAdvertisingData: AdvertisingData {

    private enum Constants {
        static let VENDOR_ID_RANGE = 0..<2
        static let PRODUCT_TYPE_RANGE = 2..<3
        static let SERIAL_RANGE = 3..<13
        static let PREFERENCES_RANGE = 13..<14

        static let COMBUSTION_VENDOR_ID: UInt16 = 0x09C7
        static let MINIMUM_DATA_LENGTH = 13
    }

    typealias SerialNumberType = String

    var serialNumber: String
    var type: ProductType
    var highRadioPower: Bool {
        switch self {
        case let advertising as BoosterAdvertisingData:
            advertising.preferences.highRadioPower
        case let advertising as DisplayAdvertisingData:
            advertising.preferences.highRadioPower
        case let advertising as EngineAdvertisingData:
            advertising.preferences.highRadioPower
        case let advertising as GaugeAdvertisingData:
            advertising.preferences.highRadioPower
        default:
            false
        }
    }

    init(type: ProductType, serialNumber: String) {
        self.type = type
        self.serialNumber = serialNumber
    }

    static func create(fromData data: Data?) -> (any AdvertisingData)? {
        guard let data = data else { return nil }
        guard data.count >= Constants.PRODUCT_TYPE_RANGE.endIndex else { return nil }

        guard let type = ProductType(rawValue: data[Constants.PRODUCT_TYPE_RANGE.lowerBound]) else {
            return nil
        }

        switch type {
        case .gauge:
            return GaugeAdvertisingData.populate(fromData: data)
        case .engine:
            return EngineAdvertisingData.populate(fromData: data)
        case .display:
            return DisplayAdvertisingData.populate(fromData: data)
        case .charger:
            return BoosterAdvertisingData.populate(fromData: data)
        case .probe, .meatNetNode, .unknown:
            return nil
        }
    }

    static func deviceInfoFields(fromData data: Data?,
                                 expectedType: ProductType) -> (serialNumber: String, preferencesByte: UInt8?)? {
        guard let data else { return nil }
        guard data.count >= Constants.MINIMUM_DATA_LENGTH else { return nil }

        let vendorID = data.subdata(in: Constants.VENDOR_ID_RANGE).withUnsafeBytes {
            $0.load(as: UInt16.self)
        }
        guard vendorID == Constants.COMBUSTION_VENDOR_ID else { return nil }
        guard data[Constants.PRODUCT_TYPE_RANGE.lowerBound] == expectedType.rawValue else { return nil }

        let serialRaw = data.subdata(in: Constants.SERIAL_RANGE)
        let serialNumber = String(decoding: serialRaw, as: UTF8.self)
            .trimmingCharacters(in: CharacterSet(["\0"]))

        let preferencesByte = data.count >= Constants.PREFERENCES_RANGE.endIndex
            ? data[Constants.PREFERENCES_RANGE.lowerBound]
            : nil

        return (serialNumber, preferencesByte)
    }
}
