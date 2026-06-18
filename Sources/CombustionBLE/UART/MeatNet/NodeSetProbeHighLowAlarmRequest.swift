//
//  NodeSetProbeHighLowAlarm.swift

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

class NodeSetProbeHighLowAlarmRequest: NodeRequest {
    let serialNumber: UInt32
    let highAlarms: [AlarmStatus]
    let lowAlarms: [AlarmStatus]
    
    init(serialNumber: UInt32, highAlarms: [AlarmStatus], lowAlarms: [AlarmStatus]) {
        self.serialNumber = serialNumber
        self.highAlarms = highAlarms
        self.lowAlarms = lowAlarms

        var payload = Data()
        
        var serialNumberBytes = serialNumber
        
        payload.append(Data(bytes: &serialNumberBytes, count: MemoryLayout.size(ofValue: serialNumberBytes)))
        
        for status in highAlarms {
            payload.append(contentsOf: status.toBytes())
        }
        
        for status in lowAlarms {
            payload.append(contentsOf: status.toBytes())
        }
        
        super.init(outgoingPayload: payload, type: .setProbeHighLowAlarm)
    }
}

extension NodeSetProbeHighLowAlarmRequest: DeviceStatusConfirmingRequest {
    var confirmationSerialNumber: String {
        String(serialNumber)
    }

    func isConfirmed(by status: DeviceStatus) -> Bool {
        guard let status = status as? ProbeStatus else {
            return false
        }

        guard let statusHighAlarms = status.highAlarms,
              let statusLowAlarms = status.lowAlarms,
              statusHighAlarms.count == highAlarms.count,
              statusLowAlarms.count == lowAlarms.count else {
            return false
        }

        return zip(statusHighAlarms, highAlarms).allSatisfy { $0.matchesCommandedConfiguration($1) }
        && zip(statusLowAlarms, lowAlarms).allSatisfy { $0.matchesCommandedConfiguration($1) }
    }
}

class NodeSetProbeHighLowAlarmResponse : NodeResponse {
    init(success: Bool, requestId: UInt32, responseId: UInt32, payloadLength: Int) {
        super.init(success: success,
                   requestId: requestId,
                   responseId: responseId,
                   payloadLength: payloadLength,
                   messageType: .setProbeHighLowAlarm)
    }
}

extension AlarmStatus {
    
    func matchesCommandedConfiguration(_ expected: AlarmStatus) -> Bool {
        guard set == expected.set else { return false }
        guard expected.set else { return true }

        return temperaturesMatch(alarmTemperature, expected.alarmTemperature)
    }

    private func temperaturesMatch(_ lhs: Double?, _ rhs: Double?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case (.some(let lhs), .some(let rhs)):
            return abs(lhs - rhs) <= 0.05
        default:
            return false
        }
    }
}
