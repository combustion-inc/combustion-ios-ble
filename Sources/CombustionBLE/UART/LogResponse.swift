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
    
    enum Constants {
        static let MINIMUM_PAYLOAD_LENGTH = 24
        
        static let SEQUENCE_RANGE = Response.HEADER_LENGTH..<(Response.HEADER_LENGTH + 4)
        static let TEMPERATURE_RANGE = (Response.HEADER_LENGTH + 4)..<(Response.HEADER_LENGTH + 17)
        static let PREDICTION_LOG_RANGE = (Response.HEADER_LENGTH + 17)..<(Response.HEADER_LENGTH + 24)
    }
    
    let sequenceNumber: UInt32
    let temperatures: ProbeTemperatures
    let predictionLog: PredictionLog
    
    init(data: Data, success: Bool, payloadLength: Int) {
        let sequenceRaw = data.subdata(in: Constants.SEQUENCE_RANGE)
        sequenceNumber = sequenceRaw.withUnsafeBytes {
            $0.load(as: UInt32.self)
        }
        
        // Temperatures (8 13-bit) values
        let tempData = data.subdata(in: Constants.TEMPERATURE_RANGE)
        temperatures = ProbeTemperatures.fromRawData(data: tempData)
        
        // Prediction Log
        let predictionLogData = data.subdata(in: Constants.PREDICTION_LOG_RANGE)
        predictionLog = PredictionLog.fromRaw(data: predictionLogData)

        super.init(success: success, payloadLength: payloadLength)
    }
}

extension LogResponse {

    static func fromRaw(data: Data, success: Bool, payloadLength: Int) -> LogResponse? {
        if(payloadLength < Constants.MINIMUM_PAYLOAD_LENGTH) {
            return nil
        }
            
        return LogResponse(data: data, success: success, payloadLength: payloadLength)
    }
}
