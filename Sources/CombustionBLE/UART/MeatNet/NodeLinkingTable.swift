//  NodeLinkingTable.swift

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

/// Serial-number representation used by the MeatNet linking-table protocol.
public enum NodeLinkingSerialNumber: Equatable, Sendable {
    /// Numeric serial number used by Predictive Thermometers.
    case probe(UInt32)

    /// Ten-byte alphanumeric serial number used by MeatNet Node products.
    case node(String)

    /// BLE MAC address carried by an unresolved version 1 linking-table entry.
    case legacyMACAddress(String)
}

/// A device entry returned by Read Linked Devices or Read Unlinked Devices.
public struct NodeLinkingTableEntry: Equatable, Sendable {
    public let productType: ProductType
    public let serialNumber: NodeLinkingSerialNumber

    /// Unix timestamp for the link or unlink operation. A value of zero means unavailable.
    public let timestamp: UInt32

    /// Whether this is an unresolved version 1 MAC-address entry.
    public let isLegacy: Bool

    public init(productType: ProductType,
                serialNumber: NodeLinkingSerialNumber,
                timestamp: UInt32,
                isLegacy: Bool) {
        self.productType = productType
        self.serialNumber = serialNumber
        self.timestamp = timestamp
        self.isLegacy = isLegacy
    }
}

extension NodeLinkingTableEntry {
    var diagnosticDescription: String {
        let serial: String
        switch serialNumber {
        case .probe(let value):
            serial = String(format: "%08X", value)
        case .node(let value), .legacyMACAddress(let value):
            serial = value
        }
        return "\(productType.rawValue):\(serial):timestamp=\(timestamp):legacy=\(isLegacy)"
    }
}

enum NodeLinkingWire {
    static let productSerialLength = 12
    static let nodeSerialLength = 10
    static let legacyMACAddressLength = 6
    static let devicePayloadLength = 17
    static let pageHeaderLength = 4
    static let entryLength = 18
    static let maximumEntriesPerPage = 4

    struct DevicePayload {
        let productType: ProductType
        let serialNumber: NodeLinkingSerialNumber
        let timestamp: UInt32
    }

    struct PagePayload {
        let page: UInt8
        let totalPages: UInt8
        let totalCount: UInt8
        let entries: [NodeLinkingTableEntry]
    }

    static func uint32(from data: Data, at index: Int) -> UInt32? {
        guard index >= 0, index + MemoryLayout<UInt32>.size <= data.count else {
            return nil
        }

        return UInt32(data[index])
            | (UInt32(data[index + 1]) << 8)
            | (UInt32(data[index + 2]) << 16)
            | (UInt32(data[index + 3]) << 24)
    }

    static func append(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value >> 16))
        data.append(UInt8(truncatingIfNeeded: value >> 24))
    }

    static func productSerialData(productType: ProductType,
                                  serialNumber: NodeLinkingSerialNumber) -> Data? {
        var result = Data(repeating: 0xFF, count: productSerialLength)

        switch serialNumber {
        case .probe(let value):
            guard productType == .probe else {
                return nil
            }

            var bytes = Data()
            append(value, to: &bytes)
            result.replaceSubrange(0..<MemoryLayout<UInt32>.size, with: bytes)

        case .node(let value):
            guard productType != .probe,
                  productType != .unknown else {
                return nil
            }

            let bytes = Array(value.utf8)
            guard bytes.count == nodeSerialLength else {
                return nil
            }
            result.replaceSubrange(0..<nodeSerialLength, with: bytes)

        case .legacyMACAddress:
            // Version 1 entries are read-only and cannot be used by Link/Unlink requests.
            return nil
        }

        return result
    }

    static func serialNumber(productType: ProductType,
                             data: Data,
                             isLegacy: Bool) -> NodeLinkingSerialNumber? {
        guard data.count == productSerialLength else {
            return nil
        }

        if isLegacy {
            let macAddress = data.prefix(legacyMACAddressLength)
                .map { String(format: "%02X", $0) }
                .joined(separator: ":")
            return .legacyMACAddress(macAddress)
        }

        if productType == .probe {
            guard let value = uint32(from: data, at: 0) else {
                return nil
            }
            return .probe(value)
        }

        let nodeSerialData = data.prefix(nodeSerialLength)
        guard let value = String(data: nodeSerialData, encoding: .utf8) else {
            return nil
        }
        return .node(value.trimmingCharacters(in: CharacterSet(charactersIn: "\0")))
    }

    static func devicePayload(productType: ProductType,
                              serialNumber: NodeLinkingSerialNumber,
                              timestamp: UInt32) -> Data? {
        guard let serialData = productSerialData(productType: productType,
                                                 serialNumber: serialNumber) else {
            return nil
        }

        var payload = Data(capacity: devicePayloadLength)
        payload.append(productType.rawValue)
        payload.append(serialData)
        append(timestamp, to: &payload)
        return payload
    }

    static func parseDevicePayload(data: Data, payloadLength: Int) -> DevicePayload? {
        guard payloadLength == devicePayloadLength,
              data.count >= NodeRequest.HEADER_LENGTH + payloadLength else {
            return nil
        }

        let payloadStart = NodeRequest.HEADER_LENGTH
        let rawProductType = data[payloadStart]
        let productType = ProductType(rawValue: rawProductType) ?? .unknown
        let serialStart = payloadStart + 1
        let serialEnd = serialStart + productSerialLength
        let serialData = data.subdata(in: serialStart..<serialEnd)

        guard let serialNumber = serialNumber(productType: productType,
                                              data: serialData,
                                              isLegacy: false),
              let timestamp = uint32(from: data, at: serialEnd) else {
            return nil
        }

        return DevicePayload(productType: productType,
                             serialNumber: serialNumber,
                             timestamp: timestamp)
    }

    static func parsePagePayload(data: Data,
                                 payloadLength: Int,
                                 permitsLegacyEntries: Bool) -> PagePayload? {
        guard payloadLength >= pageHeaderLength,
              data.count >= NodeResponse.HEADER_LENGTH + payloadLength else {
            return nil
        }

        let payloadStart = NodeResponse.HEADER_LENGTH
        let page = data[payloadStart]
        let totalPages = data[payloadStart + 1]
        let totalCount = data[payloadStart + 2]
        let countOnPage = Int(data[payloadStart + 3])

        guard countOnPage <= maximumEntriesPerPage,
              countOnPage <= Int(totalCount),
              payloadLength >= pageHeaderLength + (countOnPage * entryLength) else {
            return nil
        }

        var entries: [NodeLinkingTableEntry] = []
        entries.reserveCapacity(countOnPage)

        for index in 0..<countOnPage {
            let entryStart = payloadStart + pageHeaderLength + (index * entryLength)
            let productType = ProductType(rawValue: data[entryStart]) ?? .unknown
            let serialStart = entryStart + 1
            let serialEnd = serialStart + productSerialLength
            let serialData = data.subdata(in: serialStart..<serialEnd)

            guard let timestamp = uint32(from: data, at: serialEnd) else {
                return nil
            }

            let legacyValue = data[serialEnd + MemoryLayout<UInt32>.size]
            guard legacyValue == 0 || legacyValue == 1 else {
                return nil
            }

            let isLegacy = legacyValue == 1
            guard permitsLegacyEntries || !isLegacy,
                  let serialNumber = serialNumber(productType: productType,
                                                  data: serialData,
                                                  isLegacy: isLegacy) else {
                return nil
            }

            entries.append(NodeLinkingTableEntry(productType: productType,
                                                 serialNumber: serialNumber,
                                                 timestamp: timestamp,
                                                 isLegacy: isLegacy))
        }

        return PagePayload(page: page,
                           totalPages: totalPages,
                           totalCount: totalCount,
                           entries: entries)
    }
}

/// Common response fields for the two paginated linking-table reads.
public class NodeLinkingTablePageResponse: NodeResponse {
    public let page: UInt8
    public let totalPages: UInt8
    public let totalCount: UInt8
    public let entries: [NodeLinkingTableEntry]

    init(payload: NodeLinkingWire.PagePayload,
         success: Bool,
         requestId: UInt32,
         responseId: UInt32,
         payloadLength: Int,
         messageType: NodeMessageType) {
        self.page = payload.page
        self.totalPages = payload.totalPages
        self.totalCount = payload.totalCount
        self.entries = payload.entries
        super.init(success: success,
                   requestId: requestId,
                   responseId: responseId,
                   payloadLength: payloadLength,
                   messageType: messageType)
    }
}

protocol NodeLinkingDeviceRequestDecoding where Self: NodeRequest {
    static func makeIncoming(payload: NodeLinkingWire.DevicePayload,
                             requestId: UInt32,
                             payloadLength: Int) -> Self
}

extension NodeLinkingDeviceRequestDecoding {
    static func decode(data: Data, requestId: UInt32, payloadLength: Int) -> Self? {
        guard let payload = NodeLinkingWire.parseDevicePayload(data: data,
                                                              payloadLength: payloadLength) else {
            return nil
        }
        return makeIncoming(payload: payload, requestId: requestId, payloadLength: payloadLength)
    }
}

protocol NodeEmptyLinkingResponseDecoding where Self: NodeResponse {
    static func make(success: Bool,
                     requestId: UInt32,
                     responseId: UInt32,
                     payloadLength: Int) -> Self
}

extension NodeEmptyLinkingResponseDecoding {
    static func decode(success: Bool,
                       requestId: UInt32,
                       responseId: UInt32,
                       payloadLength: Int) -> Self? {
        guard payloadLength == 0 else {
            return nil
        }
        return make(success: success,
                    requestId: requestId,
                    responseId: responseId,
                    payloadLength: payloadLength)
    }
}
