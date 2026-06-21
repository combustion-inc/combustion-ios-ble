//  SetPrediction.swift

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

class SetPredictionRequest: Request {
    let serialNumber: UInt32
    let setPointCelsius: Double
    let mode: PredictionMode

    init(serialNumber: UInt32, setPointCelsius: Double, mode: PredictionMode) {
        self.serialNumber = serialNumber
        self.setPointCelsius = setPointCelsius
        self.mode = mode

        let rawSetPoint = UInt16(setPointCelsius / 0.1)        
        var rawPayload = (UInt16(mode.rawValue) << 10) | (rawSetPoint & 0x3FF)
        
        let payload = Data(bytes: &rawPayload, count: MemoryLayout.size(ofValue: rawPayload))
        
        super.init(payload: payload, type: .setPrediction)
    }
}

extension SetPredictionRequest: DeviceStatusConfirmingRequest {
    var confirmationSerialNumber: String {
        String(serialNumber)
    }

    func isConfirmed(by status: DeviceStatus) -> Bool {
        guard let status = status as? ProbeStatus else {
            return false
        }

        guard status.predictionStatus.predictionMode == mode else {
            return false
        }

        guard mode != .none else {
            return true
        }

        return abs(status.predictionStatus.predictionSetPointTemperature - setPointCelsius) <= 0.05
    }
}

class SetPredictionResponse : Response { 
    init(success: Bool, payloadLength: Int) {
        super.init(success:success,
                   payloadLength: payloadLength,
                   messageType: .setPrediction)
    }
}
