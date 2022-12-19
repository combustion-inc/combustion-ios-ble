//  NodeProbeStatusRequest.swift

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

class NodeProbeStatusRequest: NodeRequest {
    static let PAYLOAD_LENGTH = 35
    
    let serialNumber: UInt32
    var probeStatus: ProbeStatus? = nil
    var hopCount: HopCount? = nil
    
    init(data: Data, requestId: UInt32, payloadLength: Int) {
        let sequenceByteIndex = Response.HEADER_LENGTH
        
        let serialNumberRaw = data.subdata(in: sequenceByteIndex..<(sequenceByteIndex + 4))
        self.serialNumber = serialNumberRaw.withUnsafeBytes {
            $0.load(as: UInt32.self)
        }
        
        // Parse Probe Status
        let probeStatusRaw = data.subdata(in: (sequenceByteIndex + 4)..<(sequenceByteIndex + 31))
        if let ps = ProbeStatus(fromData: probeStatusRaw) {
            self.probeStatus = ps
        }
        
        let hopCountRaw = data.subdata(in: (sequenceByteIndex + 31)..<(sequenceByteIndex + 32))
        let hopCountInteger = hopCountRaw.withUnsafeBytes {
            $0.load(as: UInt8.self)
        }
        if let hc = HopCount(rawValue: hopCountInteger) {
            self.hopCount = hc
        }
        
        super.init(requestId: requestId, payLoadLength: payloadLength)
    }
}

extension NodeProbeStatusRequest {

    static func fromRaw(data: Data, requestId: UInt32, payloadLength: Int) -> NodeProbeStatusRequest? {
        if(payloadLength < PAYLOAD_LENGTH) {
            return nil
        }
            
        return NodeProbeStatusRequest(data: data, requestId: requestId, payloadLength: payloadLength)
    }
}
