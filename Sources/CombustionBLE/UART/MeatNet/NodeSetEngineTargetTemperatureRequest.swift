//  NodeSetEngineTargetTemperatureRequest.swift
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

/// Outgoing request to set Engine's target temperature (0x71)
class NodeSetEngineTargetTemperatureRequest: NodeRequest {
    let serialNumber: String
    let temperatureCelsius: Double

    private enum Constants {
        static let NODE_SERIAL_NUM_LENGTH = 10
    }

    /// Creates a request to set the Engine's target temperature
    /// - Parameters:
    ///   - serialNumber: Engine serial number (10 characters)
    ///   - temperatureCelsius: Target temperature in Celsius (-20 to 799)
    init?(serialNumber: String, temperatureCelsius: Double) {
        self.serialNumber = serialNumber
        self.temperatureCelsius = temperatureCelsius

        var payload = Data(capacity: Constants.NODE_SERIAL_NUM_LENGTH + 2)

        // Serial Number (10 bytes, padded with nulls if needed)
        var serialBytes = Array(serialNumber.utf8.prefix(Constants.NODE_SERIAL_NUM_LENGTH))
        serialBytes += Array(repeating: 0, count: Constants.NODE_SERIAL_NUM_LENGTH - serialBytes.count)
        payload.append(contentsOf: serialBytes)

        // Temperature Set Point (2 bytes, 13-bit packed, 0.1°C resolution, -20 offset)
        let rawValue = EngineStatus.encodeTemperature(temperatureCelsius)
        var tempBytes = rawValue
        payload.append(Data(bytes: &tempBytes, count: MemoryLayout.size(ofValue: tempBytes)))

        super.init(outgoingPayload: payload, type: .setEngineTargetTemperature)
    }
}

extension NodeSetEngineTargetTemperatureRequest: DeviceStatusConfirmingRequest {
    var confirmationSerialNumber: String {
        serialNumber
    }

    func isConfirmed(by status: DeviceStatus) -> Bool {
        guard let status = status as? EngineStatus else {
            return false
        }

        return EngineStatus.encodeTemperature(status.temperatureSetPoint) == EngineStatus.encodeTemperature(temperatureCelsius)
    }
}
