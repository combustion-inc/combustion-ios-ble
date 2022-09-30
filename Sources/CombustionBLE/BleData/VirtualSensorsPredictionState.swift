//  BatteryStatusVirtualSensors.swift

/*--
MIT License

Copyright (c) 2022 Combustion Inc.

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

/// Enumeration of Battery status
public enum PredictionState: UInt8 {
    case ProbeNotInserted       = 0x00
    case ProbeInserted          = 0x01
    case Warming                = 0x02
    case Predicting             = 0x03
    case RemovalPredictionDone  = 0x04
//    * 5: Reserved State 5
//    * 6: Reserved State 6
//    ...
//    * 14: Reserved State 14
    case Unknown                = 0x0F
    
    
    static let MASK: UInt8      = 0xF
}

class VirtualSensorsPredictionState {
    let predictionState: PredictionState
    let virtualSensors: VirtualSensors
    
    
    init() {
        predictionState = .Unknown
        virtualSensors = VirtualSensors()
    }
    
    init(predictionState: PredictionState,
         virtualSensors: VirtualSensors) {
        self.predictionState = predictionState
        self.virtualSensors = virtualSensors
    }
    
    static func fromBytes(_ rawValue: UInt16) -> VirtualSensorsPredictionState {
        let lowerByte = UInt8(rawValue & 0xFF)
        let virtualSensors = VirtualSensors.fromByte(lowerByte)
        
        let rawPrediction = UInt8((rawValue >> 7) & UInt16(PredictionState.MASK))
        let prediction = PredictionState(rawValue: rawPrediction) ?? .Unknown
        
        return VirtualSensorsPredictionState(predictionState: prediction, virtualSensors: virtualSensors)
    }
}
