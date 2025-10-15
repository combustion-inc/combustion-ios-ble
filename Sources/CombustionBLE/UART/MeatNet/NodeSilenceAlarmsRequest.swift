//  NodeSilenceAlarmsRequest.swift

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
SOFTWARE
 --*/

import Foundation

class NodeSilenceAlarmsRequest: NodeRequest {
    
    var global: Bool
    var productType: ProductType?
    var probeSerialNumber: String?
    var nodeSerialNumber: String?
    
    private enum Constants {
        static let GLOBAL_FLAG_RANGE = 0..<1
        static let PRODUCT_TYPE_RANGE = 1..<2
        static let PROBE_SERIAL_RANGE = 2..<6
        static let NODE_SERIAL_RANGE = 6..<16

        static let PAYLOAD_LENGTH = 16
    }
    
    init(global: Bool,
         productType: ProductType? = nil,
         probeSerialNumber: String? = nil,
         nodeSerialNumber: String? = nil) {
        
        self.global = global
        self.productType = productType
        self.probeSerialNumber = probeSerialNumber
        self.nodeSerialNumber = nodeSerialNumber
        
        var payload = Data()
        
        var globalFlagBytes: UInt8 = global ? 1 : 0
        payload.append(Data(bytes: &globalFlagBytes, count: MemoryLayout.size(ofValue: globalFlagBytes)))
        
        if let productType = productType {
            var productTypeBytes = productType.rawValue
            payload.append(Data(bytes: &productTypeBytes, count: MemoryLayout.size(ofValue: productTypeBytes)))
        }
        else {
            payload.append(Data(repeating: UInt8(0), count: 1))
        }
        
        if let probeSerialNumber = probeSerialNumber {
            var serialNumberBytes = UInt32(probeSerialNumber, radix: 16)
            payload.append(Data(bytes: &serialNumberBytes, count: MemoryLayout.size(ofValue: serialNumberBytes)))
        }
        else {
            payload.append(Data(repeating: UInt8(0), count: 4))
        }
        
        if let nodeSerialNumber = nodeSerialNumber {
            var serialNumberBytes = UInt8(nodeSerialNumber, radix: 16)
            payload.append(Data(bytes: &serialNumberBytes, count: MemoryLayout.size(ofValue: serialNumberBytes)))
        }
        else {
            payload.append(Data(repeating: UInt8(0), count: 10))
        }
        
        super.init(outgoingPayload: payload, type: .silenceAlarms)
    }
    
    init?(data: Data, requestId: UInt32, payloadLength: Int) {
        // Validate payload length
        guard payloadLength >= Constants.PAYLOAD_LENGTH else {
            return nil
        }

        // Global flag
        let globalByte = data.subdata(in: Constants.GLOBAL_FLAG_RANGE).first
        self.global = (globalByte != 0)

        // Product type
        let typeByte = data.subdata(in: Constants.PRODUCT_TYPE_RANGE)[0]
        productType = ProductType(rawValue: typeByte) ?? .unknown

        // if not a global silence all, then parse device serial number
        if !global {
            switch productType {
            case .probe:
                let probeSerialRaw = data.subdata(in: Constants.PROBE_SERIAL_RANGE)
                let rawProbeSerialNumber = probeSerialRaw.withUnsafeBytes { pointer in
                    pointer.load(as: UInt32.self)
                }
                
                probeSerialNumber = String(format:"%02X", rawProbeSerialNumber)
            default:
                let nodeSerialRaw = data.subdata(in: Constants.NODE_SERIAL_RANGE)
                
                nodeSerialNumber = String(decoding: nodeSerialRaw, as: UTF8.self)
            }
        }

        super.init(requestId: requestId, payloadLength: payloadLength, type: .silenceAlarms)
    }
}

extension NodeSilenceAlarmsRequest {
    
    static func fromRaw(data: Data, requestId: UInt32, payloadLength: Int) -> NodeSilenceAlarmsRequest? {
        if payloadLength < Constants.PAYLOAD_LENGTH {
            return nil
        }
            
        return NodeSilenceAlarmsRequest(data: data, requestId: requestId, payloadLength: payloadLength)
    }
}

class NodeSilenceAlarmsResponse : NodeResponse {
    init(success: Bool, requestId: UInt32, responseId: UInt32, payloadLength: Int) {
        super.init(success: success,
                   requestId: requestId,
                   responseId: responseId,
                   payloadLength: payloadLength,
                   messageType: .silenceAlarms)
    }
}
