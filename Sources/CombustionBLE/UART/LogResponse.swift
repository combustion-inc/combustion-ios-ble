//  LogResponse.swift

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

class LogResponse: Response {
    
    static let PAYLOAD_LENGTH = 17
    
    let sequenceNumber: UInt32
    let temperatures: ProbeTemperatures
    
    init(data: Data, success: Bool) {
        let sequenceByteIndex = Response.HEADER_LENGTH
        let sequenceRaw = data.subdata(in: sequenceByteIndex..<(sequenceByteIndex + 4))
        sequenceNumber = sequenceRaw.withUnsafeBytes {
            $0.load(as: UInt32.self)
        }
        
        // Temperatures (8 13-bit) values
        let tempData = data.subdata(in: (Response.HEADER_LENGTH + 4)..<(Response.HEADER_LENGTH + 17))
        temperatures = ProbeTemperatures.fromRawData(data: tempData)
        
        // print("******** Received response!")
        // print("Sequence = \(sequenceNumber) : Temperature = \(temperatures)")

        super.init(success: success, payLoadLength: LogResponse.PAYLOAD_LENGTH)
    }
}
