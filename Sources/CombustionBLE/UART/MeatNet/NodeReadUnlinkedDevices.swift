//  NodeReadUnlinkedDevices.swift

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

public final class NodeReadUnlinkedDevicesRequest: NodeRequest {
    private enum Constants {
        static let PAYLOAD_LENGTH = 1
        static let PAGE_INDEX = NodeRequest.HEADER_LENGTH
    }

    public let page: UInt8

    public init(page: UInt8) {
        self.page = page
        super.init(outgoingPayload: Data([page]), type: .readUnlinkedDevices)
    }

    private init(page: UInt8, requestId: UInt32, payloadLength: Int) {
        self.page = page
        super.init(requestId: requestId, payloadLength: payloadLength, type: .readUnlinkedDevices)
    }

    static func fromRaw(data: Data,
                        requestId: UInt32,
                        payloadLength: Int) -> NodeReadUnlinkedDevicesRequest? {
        guard payloadLength == Constants.PAYLOAD_LENGTH,
              data.count >= NodeRequest.HEADER_LENGTH + payloadLength else {
            return nil
        }

        return NodeReadUnlinkedDevicesRequest(page: data[Constants.PAGE_INDEX],
                                              requestId: requestId,
                                              payloadLength: payloadLength)
    }
}

public final class NodeReadUnlinkedDevicesResponse: NodeLinkingTablePageResponse {
    private enum Constants {
        static let MINIMUM_PAYLOAD_LENGTH = 4
    }

    static func fromRaw(data: Data,
                        success: Bool,
                        requestId: UInt32,
                        responseId: UInt32,
                        payloadLength: Int) -> NodeReadUnlinkedDevicesResponse? {
        guard payloadLength >= Constants.MINIMUM_PAYLOAD_LENGTH else {
            return nil
        }
        guard let payload = NodeLinkingWire.parsePagePayload(data: data,
                                                             payloadLength: payloadLength,
                                                             permitsLegacyEntries: false) else {
            return nil
        }

        return NodeReadUnlinkedDevicesResponse(payload: payload,
                                               success: success,
                                               requestId: requestId,
                                               responseId: responseId,
                                               payloadLength: payloadLength,
                                               messageType: .readUnlinkedDevices)
    }
}
