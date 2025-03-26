//  NodeGaugeStatusReqest.swift
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

class NodeGaugeStatusRequest: NodeRequest {
    
    let serialNumber: String
    var gaugeStatus: GaugeStatus? = nil
    var hopCount: HopCount? = nil
    
    private enum Constants {
        static let PAYLOAD_LENGTH = 53
    }

    
    init?(data: Data, requestId: UInt32, payloadLength: Int) {
        let sequenceByteIndex = NodeRequest.HEADER_LENGTH
        
        let serialNumberRaw = data.subdata(in: sequenceByteIndex..<(sequenceByteIndex + 10))
        self.serialNumber = String(decoding: serialNumberRaw, as: UTF8.self).trimmingCharacters(in: CharacterSet(["\0"]))
        
        
        let probeStatusRaw: Data
        let hopCountRaw: Data
        
        // Parse guage status
        let payloadLength = data.count - NodeRequest.HEADER_LENGTH
        
        // Note - GaugeStatus can parse the entire payload intelligently. Pass it the entire remainder of
        // the message.
        let gaugeStatusRaw = data.subdata(in: (sequenceByteIndex + 10)..<data.count)
        
        hopCountRaw = data.subdata(in: (sequenceByteIndex + 34)..<(sequenceByteIndex + 35))
        
        if let ps = GaugeStatus(fromData: gaugeStatusRaw) {
            self.gaugeStatus = ps
        }
        
        let hopCountInteger = hopCountRaw.withUnsafeBytes {
            $0.load(as: UInt8.self)
        }
        
        if let hc = HopCount(rawValue: hopCountInteger) {
            self.hopCount = hc
        }
        
        super.init(requestId: requestId, payloadLength: payloadLength, type: .gaugeStatus)
    }
}

extension NodeGaugeStatusRequest {
    static func fromRaw(data: Data, requestId: UInt32, payloadLength: Int) -> NodeGaugeStatusRequest? {
        if(payloadLength < Constants.PAYLOAD_LENGTH) {
            return nil
        }
            
        return NodeGaugeStatusRequest(data: data, requestId: requestId, payloadLength: payloadLength)
    }
}
