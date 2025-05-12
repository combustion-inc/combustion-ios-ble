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
    var type: CombustionProductType { get }
    /// Product serial number
    var serialNumber: SerialNumberType { get }
}

extension AdvertisingData {
    var serialNumberString: String {
        return "\(serialNumber)"
    }
}

/// Enumeration of Combustion, Inc. product types.
public enum CombustionProductType: UInt8 {
    case unknown = 0x00
    case probe = 0x01
    case meatNetNode = 0x02
    case gauge = 0x03
}

class NodeAdvertisingData: AdvertisingData {
    
    typealias SerialNumberType = String
    
    var serialNumber: String
    var type: CombustionProductType
    
    init(type: CombustionProductType, serialNumber: String) {
        self.type = type
        self.serialNumber = serialNumber
    }
    
    static func create(fromData data: Data?) -> (any AdvertisingData)? {
        if let advertising = GaugeAdvertisingData.populate(fromData: data) {
            return advertising
        }
        // add new advertising types here for devices
        else {
            return nil
        }
    }
}
