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
        let responseLength = min(data.count, NodeResponse.HEADER_LENGTH + payloadLength)
        let rawPayload = data.prefix(responseLength).hexString
        guard payloadLength >= Constants.MINIMUM_PAYLOAD_LENGTH else {
            print("DEVIN: bleLinkingTable event=decodeRejected table=unlinked requestID=\(requestId) responseID=\(responseId) success=\(success) reason=payloadTooShort payloadLength=\(payloadLength) raw=\(rawPayload)")
            return nil
        }
        guard let payload = NodeLinkingWire.parsePagePayload(data: data,
                                                             payloadLength: payloadLength,
                                                             permitsLegacyEntries: false) else {
            print("DEVIN: bleLinkingTable event=decodeRejected table=unlinked requestID=\(requestId) responseID=\(responseId) success=\(success) reason=invalidPagePayload payloadLength=\(payloadLength) raw=\(rawPayload)")
            return nil
        }

        let entrySummary = payload.entries.isEmpty
            ? "none"
            : payload.entries.map(\.diagnosticDescription).joined(separator: ",")
        print("DEVIN: bleLinkingTable event=decoded table=unlinked requestID=\(requestId) responseID=\(responseId) success=\(success) page=\(payload.page) totalPages=\(payload.totalPages) totalCount=\(payload.totalCount) pageCount=\(payload.entries.count) entries=\(entrySummary) raw=\(rawPayload)")

        return NodeReadUnlinkedDevicesResponse(payload: payload,
                                               success: success,
                                               requestId: requestId,
                                               responseId: responseId,
                                               payloadLength: payloadLength,
                                               messageType: .readUnlinkedDevices)
    }
}
