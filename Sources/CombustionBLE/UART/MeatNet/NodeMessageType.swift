//  NodeMessageType.swift

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

public enum NodeMessageType: Hashable, CaseIterable {
    
    case setID
    case setColor
    case setPowerMode
    case sessionInfo
    case log
    case setPrediction
    case readOverTemperature
    case configureFoodSafe
    case resetFoodSafe
    case getFeatureFlags
    
    case connected
    case disconnected
    case readNodeList
    case readNetworkTopology
    case readProbeList
    case probeStatus
    case probeFirmwareRevision
    case probeHardwareRevision
    case probeModelInformation
    case heartbeat
    case associateNode
    case syncThermometerList
    case resetSession
    
    case custom(address: UInt8)
    
    public static var allCases: [NodeMessageType] {
        return [.setID,
            .setColor,
            .sessionInfo,
            .log,
            .setPrediction,
            .setPowerMode,
            .readOverTemperature,
            .configureFoodSafe,
            .resetFoodSafe,
            .getFeatureFlags,
            .connected,
            .disconnected,
            .readNodeList,
            .readNetworkTopology,
            .readProbeList,
            .probeStatus,
            .probeFirmwareRevision,
            .probeHardwareRevision,
            .probeModelInformation,
            .heartbeat,
            .associateNode,
            .syncThermometerList,
                .resetSession]
    }
}

extension NodeMessageType {
    
    public var value : UInt8 {
        return switch self {
        case .setID: 0x01
        case .setColor: 0x02
        case .sessionInfo: 0x03
        case .log: 0x04
        case .setPrediction: 0x05
        case .readOverTemperature: 0x06
        case .configureFoodSafe: 0x07
        case .resetFoodSafe: 0x08
        case .setPowerMode: 0x09
        case .getFeatureFlags: 0x30
        case .connected: 0x40
        case .disconnected: 0x41
        case .readNodeList: 0x42
        case .readNetworkTopology: 0x43
        case .readProbeList: 0x44
        case .probeStatus: 0x45
        case .probeFirmwareRevision: 0x46
        case .probeHardwareRevision: 0x47
        case .probeModelInformation: 0x48
        case .heartbeat: 0x49
        case .associateNode: 0x4A
        case .syncThermometerList: 0x4B
        case .resetSession: 0x0A
        case .custom(let value):
            value
        }
    }
    
    
    public static func create(rawValue: UInt8) -> NodeMessageType? {
        if let value = allCases.first(where: { $0.value == rawValue }) {
            return value
        }
        else {
            return .custom(address: rawValue)
        }
    }
}
