//  NodeEngineStatusRequest.swift
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

/// Incoming Engine Status notification (0x70)
class NodeEngineStatusRequest: NodeRequest {

    let serialNumber: String
    var engineStatus: EngineStatus? = nil
    var hopCount: HopCount? = nil

    private enum Constants {
        static let MINIMUM_PAYLOAD_LENGTH = 59
        static let SERIAL_NUMBER_LENGTH = 10
        static let HOP_COUNT_OFFSET = 68
    }

    init?(data: Data, requestId: UInt32, payloadLength: Int) {
        let sequenceByteIndex = NodeRequest.HEADER_LENGTH

        // Serial Number
        let serialNumberRaw = data.subdata(in: sequenceByteIndex..<(sequenceByteIndex + Constants.SERIAL_NUMBER_LENGTH))
        self.serialNumber = String(decoding: serialNumberRaw, as: UTF8.self).trimmingCharacters(in: CharacterSet(["\0"]))

        // Parse Engine Status
        if let status = EngineStatus(fromData: data) {
            self.engineStatus = status
        }

        // Hop Count
        if data.count > Constants.HOP_COUNT_OFFSET {
            let hopCountRaw = data[Constants.HOP_COUNT_OFFSET]
            self.hopCount = HopCount.from(networkInfoByte: hopCountRaw)
        }

        super.init(requestId: requestId, payloadLength: payloadLength, type: .engineStatus)
    }
}

extension NodeEngineStatusRequest {
    static func fromRaw(data: Data, requestId: UInt32, payloadLength: Int) -> NodeEngineStatusRequest? {
        if payloadLength < Constants.MINIMUM_PAYLOAD_LENGTH {
            return nil
        }

        return NodeEngineStatusRequest(data: data, requestId: requestId, payloadLength: payloadLength)
    }
}
