//  NodeDeviceUnlinked.swift

/*--
MIT License

Copyright (c) 2026 Combustion Inc.

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

final class NodeDeviceUnlinkedRequest: NodeRequest, NodeLinkingDeviceRequestDecoding {
    private enum Constants {
        static let PAYLOAD_LENGTH = 17
    }

    let productType: ProductType
    let serialNumber: NodeLinkingSerialNumber
    let timestamp: UInt32

    private init(payload: NodeLinkingWire.DevicePayload, requestId: UInt32, payloadLength: Int) {
        self.productType = payload.productType
        self.serialNumber = payload.serialNumber
        self.timestamp = payload.timestamp
        super.init(requestId: requestId, payloadLength: payloadLength, type: .deviceUnlinked)
    }

    static func makeIncoming(payload: NodeLinkingWire.DevicePayload,
                             requestId: UInt32,
                             payloadLength: Int) -> NodeDeviceUnlinkedRequest {
        NodeDeviceUnlinkedRequest(payload: payload, requestId: requestId, payloadLength: payloadLength)
    }

    static func fromRaw(data: Data, requestId: UInt32, payloadLength: Int) -> NodeDeviceUnlinkedRequest? {
        guard payloadLength == Constants.PAYLOAD_LENGTH else {
            return nil
        }
        return decode(data: data, requestId: requestId, payloadLength: payloadLength)
    }
}
