//  NodeLinkDevice.swift

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

public final class NodeLinkDeviceRequest: NodeRequest, NodeLinkingDeviceRequestDecoding {
    private enum Constants {
        static let PAYLOAD_LENGTH = 17
    }

    public let productType: ProductType
    public let serialNumber: NodeLinkingSerialNumber
    public let timestamp: UInt32

    public convenience init(probeSerialNumber: UInt32, timestamp: UInt32 = 0) {
        self.init(productType: .probe, serialNumber: .probe(probeSerialNumber), timestamp: timestamp)!
    }

    public init?(productType: ProductType, nodeSerialNumber: String, timestamp: UInt32 = 0) {
        self.productType = productType
        self.serialNumber = .node(nodeSerialNumber)
        self.timestamp = timestamp
        guard let payload = NodeLinkingWire.devicePayload(productType: productType,
                                                          serialNumber: serialNumber,
                                                          timestamp: timestamp) else {
            return nil
        }
        super.init(outgoingPayload: payload, type: .linkDevice)
    }

    private init?(productType: ProductType,
                  serialNumber: NodeLinkingSerialNumber,
                  timestamp: UInt32) {
        self.productType = productType
        self.serialNumber = serialNumber
        self.timestamp = timestamp
        guard let payload = NodeLinkingWire.devicePayload(productType: productType,
                                                          serialNumber: serialNumber,
                                                          timestamp: timestamp) else {
            return nil
        }
        super.init(outgoingPayload: payload, type: .linkDevice)
    }

    private init(payload: NodeLinkingWire.DevicePayload, requestId: UInt32, payloadLength: Int) {
        self.productType = payload.productType
        self.serialNumber = payload.serialNumber
        self.timestamp = payload.timestamp
        super.init(requestId: requestId, payloadLength: payloadLength, type: .linkDevice)
    }

    static func makeIncoming(payload: NodeLinkingWire.DevicePayload,
                             requestId: UInt32,
                             payloadLength: Int) -> NodeLinkDeviceRequest {
        NodeLinkDeviceRequest(payload: payload, requestId: requestId, payloadLength: payloadLength)
    }

    static func fromRaw(data: Data, requestId: UInt32, payloadLength: Int) -> NodeLinkDeviceRequest? {
        guard payloadLength == Constants.PAYLOAD_LENGTH else {
            return nil
        }
        return decode(data: data, requestId: requestId, payloadLength: payloadLength)
    }
}

public final class NodeLinkDeviceResponse: NodeResponse, NodeEmptyLinkingResponseDecoding {
    private enum Constants {
        static let PAYLOAD_LENGTH = 0
    }

    static func make(success: Bool,
                     requestId: UInt32,
                     responseId: UInt32,
                     payloadLength: Int) -> NodeLinkDeviceResponse {
        NodeLinkDeviceResponse(success: success,
                               requestId: requestId,
                               responseId: responseId,
                               payloadLength: payloadLength,
                               messageType: .linkDevice)
    }

    static func fromRaw(success: Bool,
                        requestId: UInt32,
                        responseId: UInt32,
                        payloadLength: Int) -> NodeLinkDeviceResponse? {
        guard payloadLength == Constants.PAYLOAD_LENGTH else {
            return nil
        }
        return decode(success: success,
                      requestId: requestId,
                      responseId: responseId,
                      payloadLength: payloadLength)
    }
}
