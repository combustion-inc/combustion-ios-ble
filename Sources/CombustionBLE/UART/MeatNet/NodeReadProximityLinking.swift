//  NodeReadProximityLinking.swift

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

public final class NodeReadProximityLinkingRequest: NodeRequest {
    private enum Constants {
        static let PAYLOAD_LENGTH = 0
    }

    public init() {
        super.init(outgoingPayload: Data(), type: .readProximityLinking)
    }

    private init(requestId: UInt32) {
        super.init(requestId: requestId,
                   payloadLength: Constants.PAYLOAD_LENGTH,
                   type: .readProximityLinking)
    }

    static func fromRaw(data: Data,
                        requestId: UInt32,
                        payloadLength: Int) -> NodeReadProximityLinkingRequest? {
        guard payloadLength == Constants.PAYLOAD_LENGTH,
              data.count >= NodeRequest.HEADER_LENGTH else {
            return nil
        }
        return NodeReadProximityLinkingRequest(requestId: requestId)
    }
}

public final class NodeReadProximityLinkingResponse: NodeResponse {
    private enum Constants {
        static let PAYLOAD_LENGTH = 1
        static let ENABLED_INDEX = NodeResponse.HEADER_LENGTH
    }

    public let enabled: Bool

    private init(enabled: Bool,
                 success: Bool,
                 requestId: UInt32,
                 responseId: UInt32,
                 payloadLength: Int) {
        self.enabled = enabled
        super.init(success: success,
                   requestId: requestId,
                   responseId: responseId,
                   payloadLength: payloadLength,
                   messageType: .readProximityLinking)
    }

    static func fromRaw(data: Data,
                        success: Bool,
                        requestId: UInt32,
                        responseId: UInt32,
                        payloadLength: Int) -> NodeReadProximityLinkingResponse? {
        guard payloadLength == Constants.PAYLOAD_LENGTH,
              data.count >= NodeResponse.HEADER_LENGTH + payloadLength else {
            return nil
        }

        let rawValue = data[Constants.ENABLED_INDEX]
        guard rawValue == 0 || rawValue == 1 else {
            return nil
        }

        return NodeReadProximityLinkingResponse(enabled: rawValue == 1,
                                                success: success,
                                                requestId: requestId,
                                                responseId: responseId,
                                                payloadLength: payloadLength)
    }
}
