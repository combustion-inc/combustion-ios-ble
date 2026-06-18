//  NodeSetEngineControlDeviceRequest.swift
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

/// Outgoing request to set Engine's control device (0x72)
class NodeSetEngineControlDeviceRequest: NodeRequest {
    let serialNumber: String
    let controlDeviceType: ProductType
    let probeSerialNumber: UInt32?
    let gaugeSerialNumber: String?

    private enum Constants {
        static let SERIAL_NUM_LENGTH = 10
        static let PROBE_SERIAL_NUM_LENGTH = 4
        static let PRODUCT_SERIAL_NUM_LENGTH = 10
    }

    /// Creates a request to set the Engine's control device to a probe
    /// - Parameters:
    ///   - serialNumber: Engine serial number (10 characters)
    ///   - probeSerialNumber: Probe serial number (UInt32)
    init?(serialNumber: String, probeSerialNumber: UInt32) {
        self.serialNumber = serialNumber
        self.controlDeviceType = .probe
        self.probeSerialNumber = probeSerialNumber
        self.gaugeSerialNumber = nil

        var payload = Data(capacity: Constants.SERIAL_NUM_LENGTH + 1 + Constants.PRODUCT_SERIAL_NUM_LENGTH)

        // Engine Serial Number (10 bytes, padded with nulls if needed)
        var serialBytes = Array(serialNumber.utf8.prefix(Constants.SERIAL_NUM_LENGTH))
        serialBytes += Array(repeating: 0, count: Constants.SERIAL_NUM_LENGTH - serialBytes.count)
        payload.append(contentsOf: serialBytes)

        // Control Device Type (1 byte)
        payload.append(ProductType.probe.rawValue)

        // Product Serial Number (10 bytes): the first 4 bytes contain the probe serial.
        var productSerialBytes = Data(count: Constants.PRODUCT_SERIAL_NUM_LENGTH)
        var probeSerial = probeSerialNumber.littleEndian
        withUnsafeBytes(of: &probeSerial) { buffer in
            productSerialBytes.replaceSubrange(0..<Constants.PROBE_SERIAL_NUM_LENGTH, with: buffer)
        }
        payload.append(productSerialBytes)

        super.init(outgoingPayload: payload, type: .setEngineControlDevice)
    }

    /// Creates a request to set the Engine's control device to a gauge (node)
    /// - Parameters:
    ///   - serialNumber: Engine serial number (10 characters)
    ///   - gaugeSerialNumber: Gauge serial number (10 characters)
    init?(serialNumber: String, gaugeSerialNumber: String) {
        self.serialNumber = serialNumber
        self.controlDeviceType = .gauge
        self.probeSerialNumber = nil
        self.gaugeSerialNumber = gaugeSerialNumber

        var payload = Data(capacity: Constants.SERIAL_NUM_LENGTH + 1 + Constants.PRODUCT_SERIAL_NUM_LENGTH)

        // Engine Serial Number (10 bytes, padded with nulls if needed)
        var serialBytes = Array(serialNumber.utf8.prefix(Constants.SERIAL_NUM_LENGTH))
        serialBytes += Array(repeating: 0, count: Constants.SERIAL_NUM_LENGTH - serialBytes.count)
        payload.append(contentsOf: serialBytes)

        // Control Device Type (1 byte)
        payload.append(ProductType.gauge.rawValue)

        // Product Serial Number (10 bytes, padded with nulls if needed)
        var gaugeSerialBytes = Array(gaugeSerialNumber.utf8.prefix(Constants.PRODUCT_SERIAL_NUM_LENGTH))
        gaugeSerialBytes += Array(repeating: 0, count: Constants.PRODUCT_SERIAL_NUM_LENGTH - gaugeSerialBytes.count)
        payload.append(contentsOf: gaugeSerialBytes)

        super.init(outgoingPayload: payload, type: .setEngineControlDevice)
    }
}

extension NodeSetEngineControlDeviceRequest: DeviceStatusConfirmingRequest {
    var confirmationSerialNumber: String {
        serialNumber
    }

    func isConfirmed(by status: DeviceStatus) -> Bool {
        guard let status = status as? EngineStatus else {
            return false
        }

        guard status.controlDeviceType == controlDeviceType else {
            return false
        }

        switch controlDeviceType {
        case .probe:
            return status.probeSerialNumber == probeSerialNumber
        case .gauge:
            return status.nodeSerialNumber == gaugeSerialNumber
        default:
            return false
        }
    }
}
