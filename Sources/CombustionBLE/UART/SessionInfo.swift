//  SessionInfo.swift

/*--
MIT License

Copyright (c) 2022 Combustion Inc.

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

class SessionInfoRequest: Request {
    static let PAYLOAD_LENGTH: UInt8 = 0
    
    init() {
        super.init(payloadLength: LogRequest.PAYLOAD_LENGTH, type: .SessionInfo)
    }
}

class SessionInfoResponse: Response {
    let sessionID: UInt16
    let samplePeriod: UInt16
    
    init(data: Data, success: Bool) {
        let sequenceByteIndex = Response.HEADER_LENGTH
        let sessionIDRaw = data.subdata(in: sequenceByteIndex..<(sequenceByteIndex + 2))
        sessionID = sessionIDRaw.withUnsafeBytes {
            $0.load(as: UInt16.self)
        }
        
        let samplePeriodRaw = data.subdata(in: (sequenceByteIndex + 2)..<(sequenceByteIndex + 4))
        samplePeriod = samplePeriodRaw.withUnsafeBytes {
            $0.load(as: UInt16.self)
        }

        super.init(success: success)
    }
}
