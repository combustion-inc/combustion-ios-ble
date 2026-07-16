//  NodeSetProximityLinking.swift

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

public final class NodeSetProximityLinkingRequest: NodeRequest {
    private enum Constants {
        static let PAYLOAD_LENGTH = 1
        static let ENABLED_INDEX = NodeRequest.HEADER_LENGTH
    }

    public let enabled: Bool

    public init(enabled: Bool) {
        self.enabled = enabled
        super.init(outgoingPayload: Data([enabled ? 1 : 0]), type: .setProximityLinking)
    }

    private init(enabled: Bool, requestId: UInt32, payloadLength: Int) {
        self.enabled = enabled
        super.init(requestId: requestId, payloadLength: payloadLength, type: .setProximityLinking)
    }

    static func fromRaw(data: Data,
                        requestId: UInt32,
                        payloadLength: Int) -> NodeSetProximityLinkingRequest? {
        guard payloadLength == Constants.PAYLOAD_LENGTH,
              data.count >= NodeRequest.HEADER_LENGTH + payloadLength else {
            return nil
        }

        let rawValue = data[Constants.ENABLED_INDEX]
        guard rawValue == 0 || rawValue == 1 else {
            return nil
        }

        return NodeSetProximityLinkingRequest(enabled: rawValue == 1,
                                              requestId: requestId,
                                              payloadLength: payloadLength)
    }
}

public final class NodeSetProximityLinkingResponse: NodeResponse, NodeEmptyLinkingResponseDecoding {
    private enum Constants {
        static let PAYLOAD_LENGTH = 0
    }

    static func make(success: Bool,
                     requestId: UInt32,
                     responseId: UInt32,
                     payloadLength: Int) -> NodeSetProximityLinkingResponse {
        NodeSetProximityLinkingResponse(success: success,
                                        requestId: requestId,
                                        responseId: responseId,
                                        payloadLength: payloadLength,
                                        messageType: .setProximityLinking)
    }

    static func fromRaw(success: Bool,
                        requestId: UInt32,
                        responseId: UInt32,
                        payloadLength: Int) -> NodeSetProximityLinkingResponse? {
        guard payloadLength == Constants.PAYLOAD_LENGTH else {
            return nil
        }
        return decode(success: success,
                      requestId: requestId,
                      responseId: responseId,
                      payloadLength: payloadLength)
    }
}
