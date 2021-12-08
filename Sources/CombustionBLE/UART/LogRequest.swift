//  LogRequest.swift

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

class LogRequest: Request {
    static let PAYLOAD_LENGTH: UInt8 = 8
    
    /// Maximum number of log messages allowed per log request
    static let MAX_LOG_MESSAGES: UInt32 = 500
    
    init(minSequence: UInt32, maxSequence: UInt32) {
        super.init(payloadLength: LogRequest.PAYLOAD_LENGTH, type: .Log)
        
        // print("Log Request Range: ", minSequence, maxSequence)
        
        var min = minSequence
        let minData = Data(bytes: &min, count: MemoryLayout.size(ofValue: min))
        self.data[Request.HEADER_SIZE + 0] = minData[0]
        self.data[Request.HEADER_SIZE + 1] = minData[1]
        self.data[Request.HEADER_SIZE + 2] = minData[2]
        self.data[Request.HEADER_SIZE + 3] = minData[3]
        
        var max = maxSequence
        if((maxSequence - minSequence) > LogRequest.MAX_LOG_MESSAGES) {
            // Constrain the number of recoreds to our maximum.
            max = minSequence + LogRequest.MAX_LOG_MESSAGES - 1
        }
        
        // print("Actual Log Request Range: ", minSequence, max)
        let maxData = Data(bytes: &max, count: MemoryLayout.size(ofValue: max))
        self.data[Request.HEADER_SIZE + 4] = maxData[0]
        self.data[Request.HEADER_SIZE + 5] = maxData[1]
        self.data[Request.HEADER_SIZE + 6] = maxData[2]
        self.data[Request.HEADER_SIZE + 7] = maxData[3]
    }
}
