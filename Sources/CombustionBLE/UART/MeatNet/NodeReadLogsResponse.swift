//  NodeReadLogsResponse.swift

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

class NodeReadLogsResponse: NodeResponse {
    
    enum Constants {
        static let MINIMUM_PAYLOAD_LENGTH = 28
        
        static let SERIAL_RANGE = NodeResponse.HEADER_LENGTH..<(NodeResponse.HEADER_LENGTH + 4)
        static let SEQUENCE_RANGE = (NodeResponse.HEADER_LENGTH + 4)..<(NodeResponse.HEADER_LENGTH + 8)
        static let TEMPERATURE_RANGE = (NodeResponse.HEADER_LENGTH + 8)..<(NodeResponse.HEADER_LENGTH + 21)
        static let PREDICTION_LOG_RANGE = (NodeResponse.HEADER_LENGTH + 21)..<(NodeResponse.HEADER_LENGTH + 28)
    }
    
    let probeSerialNumber: UInt32
    let sequenceNumber: UInt32
    let temperatures: ProbeTemperatures
    let predictionLog: PredictionLog
    
    init(data: Data, success: Bool, requestId: UInt32, responseId: UInt32, payloadLength: Int) {
        let serialRaw = data.subdata(in: Constants.SERIAL_RANGE)
        probeSerialNumber = serialRaw.withUnsafeBytes {
            $0.load(as: UInt32.self)
        }
        
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

        super.init(success: success, requestId: requestId, responseId: responseId, payloadLength: payloadLength)
    }
}

extension NodeReadLogsResponse {

    static func fromRaw(data: Data, success: Bool, requestId: UInt32, responseId: UInt32, payloadLength: Int) -> NodeReadLogsResponse? {
        if(payloadLength < Constants.MINIMUM_PAYLOAD_LENGTH) {
            return nil
        }
            
        return NodeReadLogsResponse(data: data, success: success, requestId: requestId, responseId: responseId, payloadLength: payloadLength)
    }
}
