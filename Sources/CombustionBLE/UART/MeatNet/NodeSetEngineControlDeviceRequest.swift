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

    private enum Constants {
        static let NODE_SERIAL_NUM_LENGTH = 10
        static let PROBE_SERIAL_NUM_LENGTH = 4
    }

    /// Creates a request to set the Engine's control device to a probe
    /// - Parameters:
    ///   - serialNumber: Engine serial number (10 characters)
    ///   - probeSerialNumber: Probe serial number (UInt32)
    init?(serialNumber: String, probeSerialNumber: UInt32) {
        var payload = Data(capacity: Constants.NODE_SERIAL_NUM_LENGTH + 1 + Constants.PROBE_SERIAL_NUM_LENGTH)

        // Engine Serial Number (10 bytes, padded with nulls if needed)
        var serialBytes = Array(serialNumber.utf8.prefix(Constants.NODE_SERIAL_NUM_LENGTH))
        serialBytes += Array(repeating: 0, count: Constants.NODE_SERIAL_NUM_LENGTH - serialBytes.count)
        payload.append(contentsOf: serialBytes)

        // Control Device Type (1 byte)
        payload.append(ProductType.probe.rawValue)

        // Probe Serial Number (4 bytes)
        var probeSerial = probeSerialNumber
        payload.append(Data(bytes: &probeSerial, count: MemoryLayout.size(ofValue: probeSerial)))

        super.init(outgoingPayload: payload, type: .setEngineControlDevice)
    }

    /// Creates a request to set the Engine's control device to a gauge (node)
    /// - Parameters:
    ///   - serialNumber: Engine serial number (10 characters)
    ///   - gaugeSerialNumber: Gauge serial number (10 characters)
    init?(serialNumber: String, gaugeSerialNumber: String) {
        var payload = Data(capacity: Constants.NODE_SERIAL_NUM_LENGTH + 1 + Constants.NODE_SERIAL_NUM_LENGTH)

        // Engine Serial Number (10 bytes, padded with nulls if needed)
        var serialBytes = Array(serialNumber.utf8.prefix(Constants.NODE_SERIAL_NUM_LENGTH))
        serialBytes += Array(repeating: 0, count: Constants.NODE_SERIAL_NUM_LENGTH - serialBytes.count)
        payload.append(contentsOf: serialBytes)

        // Control Device Type (1 byte)
        payload.append(ProductType.gauge.rawValue)

        // Gauge Serial Number (10 bytes, padded with nulls if needed)
        var gaugeSerialBytes = Array(gaugeSerialNumber.utf8.prefix(Constants.NODE_SERIAL_NUM_LENGTH))
        gaugeSerialBytes += Array(repeating: 0, count: Constants.NODE_SERIAL_NUM_LENGTH - gaugeSerialBytes.count)
        payload.append(contentsOf: gaugeSerialBytes)

        super.init(outgoingPayload: payload, type: .setEngineControlDevice)
    }
}
