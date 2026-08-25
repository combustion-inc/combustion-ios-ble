//  EngineAdvertisingData.swift
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

class EngineAdvertisingData: NodeAdvertisingData {

    private enum Constants {
        // Locations of data in advertising packets
        static let VENDOR_ID_RANGE = 0..<2
        static let PRODUCT_TYPE_RANGE = 2..<3
        static let SERIAL_RANGE = 3..<13
        static let TEMPERATURE_SET_POINT_RANGE = 13..<15
        static let STATUS_FLAGS_RANGE = 15..<16
        static let PREFERENCES_RANGE = 16..<17

        static let COMBUSTION_VENDOR_ID: UInt16 = 0x09C7
        static let MINIMUM_DATA_LENGTH = 16
    }

    /// Current temperature set point (in Celsius)
    var temperatureSetPoint: Double
    /// Engine status flags
    var statusFlags: EngineStatusFlags
    /// Engine advertising preferences.
    var preferences: EnginePreferences

    init(type: ProductType,
         serialNumber: String,
         temperatureSetPoint: Double,
         statusFlags: EngineStatusFlags,
         preferences: EnginePreferences = .defaultValues()) {
        self.temperatureSetPoint = temperatureSetPoint
        self.statusFlags = statusFlags
        self.preferences = preferences
        super.init(type: type, serialNumber: serialNumber)
    }

    static func populate(fromData data: Data?) -> (any AdvertisingData)? {
        guard let data = data else { return nil }
        guard data.count >= Constants.MINIMUM_DATA_LENGTH else { return nil }

        // Vendor ID
        let rawVendorId = data.subdata(in: Constants.VENDOR_ID_RANGE)
        let vendorID = rawVendorId.withUnsafeBytes {
            $0.load(as: UInt16.self)
        }

        guard vendorID == Constants.COMBUSTION_VENDOR_ID else { return nil }

        // Serial Number
        let serialRaw = data.subdata(in: Constants.SERIAL_RANGE)
        let serialNumberString = String(decoding: serialRaw, as: UTF8.self).trimmingCharacters(in: CharacterSet(["\0"]))

        // Temperature Set Point (13-bit packed, 0.1°C resolution, -20 offset)
        let setPointData = data.subdata(in: Constants.TEMPERATURE_SET_POINT_RANGE)
        let setPointRaw = setPointData.withUnsafeBytes { $0.load(as: UInt16.self) }
        let setPointValue = setPointRaw & 0x1FFF
        let temperatureSetPoint = Double(setPointValue) * 0.1 - 20.0

        // Status Flags
        let statusFlagsByte = data[Constants.STATUS_FLAGS_RANGE.lowerBound]
        let statusFlags = EngineStatusFlags.fromByte(statusFlagsByte)

        // Preferences
        let preferences = data.count >= Constants.PREFERENCES_RANGE.endIndex
            ? EnginePreferences.fromByte(data[Constants.PREFERENCES_RANGE.lowerBound])
            : .defaultValues()

        return EngineAdvertisingData(type: .engine,
                                     serialNumber: serialNumberString,
                                     temperatureSetPoint: temperatureSetPoint,
                                     statusFlags: statusFlags,
                                     preferences: preferences)
    }
}

extension EngineAdvertisingData {
    // Fake data initializer for previews
    public convenience init(fakeSerial: String) {
        self.init(type: .engine,
                  serialNumber: fakeSerial,
                  temperatureSetPoint: 225.0,
                  statusFlags: EngineStatusFlags.defaultValues(),
                  preferences: EnginePreferences.defaultValues())
    }

    // Fake data initializer for Simulated Engine
    public convenience init(fakeSerial: String, fakeTemperatureSetPoint: Double) {
        self.init(type: .engine,
                  serialNumber: fakeSerial,
                  temperatureSetPoint: fakeTemperatureSetPoint,
                  statusFlags: EngineStatusFlags.defaultValues(),
                  preferences: EnginePreferences.defaultValues())
    }
}
