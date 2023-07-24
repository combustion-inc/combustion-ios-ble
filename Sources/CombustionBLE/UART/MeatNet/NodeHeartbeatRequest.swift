//  NodeHeartbeatRequest.swift

/*--
MIT License

Copyright (c) 2023 Combustion Inc.

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

class NodeHeartbeatRequest: NodeRequest {
    let serialNumber: String
    let macAddress: String
    let productType: CombustionProductType
    let hopCount: HopCount
    let inbound: Bool
    let connectionDetails: [ConnectionDetail]
    
    struct ConnectionDetail {
        let present: Bool
        let serialNumber: String
        let productType: CombustionProductType
        let rssi: Int
        
        enum Constants {
            static let PAYLOAD_LENGTH = 13
            
            static let PROBE_SERIAL_RANGE = 0..<4
            static let NODE_SERIAL_RANGE = 0..<10
            static let PRODUCT_TYPE_INDEX = 10
            static let ATTRIBUTES_INDEX = 11
            static let RSSI_INDEX = 12
        }
    }
    
    enum Constants {
        static let PAYLOAD_LENGTH = 71
        
        static let SERIAL_NUMBER_RANGE = NodeRequest.HEADER_LENGTH..<(NodeRequest.HEADER_LENGTH + 10)
        static let MAC_ADDRESS_RANGE = (NodeRequest.HEADER_LENGTH + 10)..<(NodeRequest.HEADER_LENGTH + 16)
        static let PRODUCT_TYPE_RANGE = (NodeRequest.HEADER_LENGTH + 16)..<(NodeRequest.HEADER_LENGTH + 17)
        static let HOP_COUNT_RANGE = (NodeRequest.HEADER_LENGTH + 17)..<(NodeRequest.HEADER_LENGTH + 18)
        static let INBOUND_RANGE = (NodeRequest.HEADER_LENGTH + 18)..<(NodeRequest.HEADER_LENGTH + 19)
        static let CONNECTION_DETAIL_START = (NodeRequest.HEADER_LENGTH + 19)
    }
    
    init(data: Data, requestId: UInt32, payloadLength: Int) {
        
        // Serial number
        let serialRaw = data.subdata(in: Constants.SERIAL_NUMBER_RANGE)
        serialNumber = String(decoding: serialRaw, as: UTF8.self)
        
        // Mac address
        let macAddressRaw = data.subdata(in: Constants.MAC_ADDRESS_RANGE)
        macAddress = macAddressRaw.map { String(format: "%02hhx", $0) }.joined(separator: ":").uppercased()
        
        // Product type
        let typeByte = data.subdata(in: Constants.PRODUCT_TYPE_RANGE)[0]
        productType = CombustionProductType(rawValue: typeByte) ?? .unknown
        
        // Hop Count
        let hopByte = data.subdata(in: Constants.HOP_COUNT_RANGE)[0]
        hopCount = HopCount.from(networkInfoByte: hopByte)
        
        // Inbound
        let inboundByte = data.subdata(in: Constants.INBOUND_RANGE)[0]
        inbound = (inboundByte != 0x00)
        
        var connections: [ConnectionDetail] = []
        for i in 0...3 {
            let startIndex = Constants.CONNECTION_DETAIL_START + (i * ConnectionDetail.Constants.PAYLOAD_LENGTH)
            let stopIndex = startIndex + ConnectionDetail.Constants.PAYLOAD_LENGTH
            let dataRange = (startIndex)..<(stopIndex)
            connections.append(ConnectionDetail.fromRaw(data: data.subdata(in: dataRange)))
        }

        connectionDetails = connections
        
        super.init(requestId: requestId, payloadLength: payloadLength)
    }
    
}

extension NodeHeartbeatRequest {

    static func fromRaw(data: Data, requestId: UInt32, payloadLength: Int) -> NodeHeartbeatRequest? {
        if(payloadLength < Constants.PAYLOAD_LENGTH) {
            return nil
        }
            
        return NodeHeartbeatRequest(data: data, requestId: requestId, payloadLength: payloadLength)
    }
}

extension NodeHeartbeatRequest.ConnectionDetail {

    static func fromRaw(data: Data) -> NodeHeartbeatRequest.ConnectionDetail {
        guard data.count >= Constants.PAYLOAD_LENGTH else {
            return NodeHeartbeatRequest.ConnectionDetail.notPresent()
        }
        
        let attributes = data[Constants.ATTRIBUTES_INDEX]

        // If this value isn't set, ignore the rest of it.
        guard ((attributes & 0x01) == 0x01) else {
            return NodeHeartbeatRequest.ConnectionDetail.notPresent()
        }
        
        let productType = CombustionProductType(rawValue: data[Constants.PRODUCT_TYPE_INDEX]) ?? .unknown
        
        let serialNumber: String
        switch (productType) {
        case .probe:
            let rawSerial = data.subdata(in: Constants.PROBE_SERIAL_RANGE)
            var revSerial : [UInt8] = []
            for byte in rawSerial {
                revSerial.insert(byte as UInt8, at: 0)
            }
            
            let serialArray = [UInt8](revSerial)
            var value: UInt32 = 0
            for byte in serialArray {
                value = value << 8
                value = value | UInt32(byte)
            }
            
            serialNumber = String(format:"%02X", value)
        case .meatNetNode:
            let serialRaw = data.subdata(in: Constants.NODE_SERIAL_RANGE)
            serialNumber = String(decoding: serialRaw, as: UTF8.self)
        case .unknown:
            serialNumber = ""
        }
        
        let rssi = Int8(bitPattern: data[Constants.RSSI_INDEX])
            
        return NodeHeartbeatRequest.ConnectionDetail(present: true,
                                                     serialNumber: serialNumber,
                                                     productType: productType,
                                                     rssi: Int(rssi))
    }
    
    static func notPresent() -> NodeHeartbeatRequest.ConnectionDetail {
        return NodeHeartbeatRequest.ConnectionDetail(present: false,
                                                     serialNumber: "",
                                                     productType: .unknown,
                                                     rssi: 0)
    }
}
