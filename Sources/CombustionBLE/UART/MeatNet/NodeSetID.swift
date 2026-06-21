//  NodeSetID.swift

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

class NodeSetIDRequest: NodeRequest {
    let serialNumber: UInt32
    let id: ProbeID

    init(serialNumber: UInt32, id: ProbeID) {
        self.serialNumber = serialNumber
        self.id = id

        var payload = Data()
        var serialNumberBytes = serialNumber
        payload.append(Data(bytes: &serialNumberBytes, count: MemoryLayout.size(ofValue: serialNumberBytes)))
        payload.append(id.rawValue)
        
        super.init(outgoingPayload: payload, type: .setID)
    }
}

extension NodeSetIDRequest: DeviceStatusConfirmingRequest {
    var confirmationSerialNumber: String {
        String(serialNumber)
    }

    func isConfirmed(by status: DeviceStatus) -> Bool {
        guard let status = status as? ProbeStatus else {
            return false
        }

        return status.modeId.id == id
    }
}

class NodeSetIDResponse : NodeResponse {
    init(success: Bool, requestId: UInt32, responseId: UInt32, payloadLength: Int) {
        super.init(success: success,
                   requestId: requestId,
                   responseId: responseId,
                   payloadLength: payloadLength,
                   messageType: .setID)
    }
}
