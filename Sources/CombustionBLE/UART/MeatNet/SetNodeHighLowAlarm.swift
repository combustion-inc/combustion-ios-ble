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

class SetNodeHighLowAlarmRequest: NodeRequest {
    let serialNumber: String
    let status: HighLowAlarmStatus
    
    class Constants {
        static let NODE_SERIAL_NUM_LENGTH = 10
    }
    
    init?(serialNumber: String, status: HighLowAlarmStatus) {
        self.serialNumber = serialNumber
        self.status = status
        
        var payload = Data(capacity: Constants.NODE_SERIAL_NUM_LENGTH + 4)
        
        var serialBytes = Array(serialNumber.utf8.prefix(Constants.NODE_SERIAL_NUM_LENGTH))
        serialBytes += Array(repeating: 0, count: Constants.NODE_SERIAL_NUM_LENGTH - serialBytes.count)
        
        payload.append(contentsOf: serialBytes)
        
        payload.append(contentsOf: status.toRawData())
        
        super.init(outgoingPayload: payload, type: .setHighLowAlarm)
    }
}

extension SetNodeHighLowAlarmRequest: DeviceStatusConfirmingRequest {
    var confirmationSerialNumber: String {
        serialNumber
    }

    func isConfirmed(by status: DeviceStatus) -> Bool {
        guard let status = status as? GaugeStatus else {
            return false
        }

        return status.highLowAlarmStatus.highAlarmStatus.matchesCommandedConfiguration(self.status.highAlarmStatus)
        && status.highLowAlarmStatus.lowAlarmStatus.matchesCommandedConfiguration(self.status.lowAlarmStatus)
    }
}

class SetNodeHighLowAlarmResponse : NodeResponse {
    init(success: Bool, requestId: UInt32, responseId: UInt32, payloadLength: Int) {
        super.init(success: success,
                   requestId: requestId,
                   responseId: responseId,
                   payloadLength: payloadLength,
                   messageType: .setHighLowAlarm)
    }
}
