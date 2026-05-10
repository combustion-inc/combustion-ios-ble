//  NodeEngineReadLogsResponse.swift
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

class NodeEngineReadLogsResponse: NodeResponse {

    enum Constants {
        static let MINIMUM_PAYLOAD_LENGTH = 31

        static let SERIAL_RANGE = NodeResponse.HEADER_LENGTH..<(NodeResponse.HEADER_LENGTH + 10)
        static let SEQUENCE_RANGE = (NodeResponse.HEADER_LENGTH + 10)..<(NodeResponse.HEADER_LENGTH + 14)
        static let TEMPERATURE_SET_POINT_RANGE = (NodeResponse.HEADER_LENGTH + 14)..<(NodeResponse.HEADER_LENGTH + 16)
        static let CONTROL_TEMPERATURE_RANGE = (NodeResponse.HEADER_LENGTH + 16)..<(NodeResponse.HEADER_LENGTH + 18)
        static let STATUS_FLAGS_RANGE = (NodeResponse.HEADER_LENGTH + 18)..<(NodeResponse.HEADER_LENGTH + 19)
        static let FAN_STATUS_RANGE = (NodeResponse.HEADER_LENGTH + 19)..<(NodeResponse.HEADER_LENGTH + 31)
    }

    let engineSerialNumber: String
    let sequenceNumber: UInt32
    let temperatureSetPoint: Double
    let controlTemperature: Double
    let statusFlags: EngineStatusFlags
    let fanStatus: EngineFanStatus

    init(data: Data, success: Bool, requestId: UInt32, responseId: UInt32, payloadLength: Int) {
        let serialRaw = data.subdata(in: Constants.SERIAL_RANGE)
        engineSerialNumber = String(decoding: serialRaw, as: UTF8.self).trimmingCharacters(in: CharacterSet(["\0"]))

        let sequenceRaw = data.subdata(in: Constants.SEQUENCE_RANGE)
        sequenceNumber = sequenceRaw.withUnsafeBytes {
            $0.load(as: UInt32.self)
        }

        let temperatureSetPointData = data.subdata(in: Constants.TEMPERATURE_SET_POINT_RANGE)
        let temperatureSetPointRaw = temperatureSetPointData.withUnsafeBytes { $0.load(as: UInt16.self) }
        temperatureSetPoint = EngineStatus.decodeTemperature(from: temperatureSetPointRaw)

        let controlTemperatureData = data.subdata(in: Constants.CONTROL_TEMPERATURE_RANGE)
        let controlTemperatureRaw = controlTemperatureData.withUnsafeBytes { $0.load(as: UInt16.self) }
        controlTemperature = EngineStatus.decodeTemperature(from: controlTemperatureRaw)

        let statusFlagsByte = data[Constants.STATUS_FLAGS_RANGE.lowerBound]
        statusFlags = EngineStatusFlags.fromByte(statusFlagsByte)

        let fanStatusData = data.subdata(in: Constants.FAN_STATUS_RANGE)
        fanStatus = EngineFanStatus.fromData(fanStatusData)

        super.init(success: success,
                   requestId: requestId,
                   responseId: responseId,
                   payloadLength: payloadLength,
                   messageType: .engineLog)
    }
}

extension NodeEngineReadLogsResponse {

    static func fromRaw(data: Data, success: Bool, requestId: UInt32, responseId: UInt32, payloadLength: Int) -> NodeEngineReadLogsResponse? {
        if(payloadLength < Constants.MINIMUM_PAYLOAD_LENGTH) {
            return nil
        }

        return NodeEngineReadLogsResponse(data: data, success: success, requestId: requestId, responseId: responseId, payloadLength: payloadLength)
    }
}
