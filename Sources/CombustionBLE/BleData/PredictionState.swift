//  PredictionState.swift

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
    case probeNotInserted       = 0x00
    case probeInserted          = 0x01
    case cooking                = 0x02
    case predicting             = 0x03
    case removalPredictionDone  = 0x04
    case reservedState5         = 0x05
    case reservedState6         = 0x06
    case reservedState7         = 0x07
    case reservedState8         = 0x08
    case reservedState9         = 0x09
    case reservedState10        = 0x0A
    case reservedState11        = 0x0B
    case reservedState12        = 0x0C
    case reservedState13        = 0x0D
    case reservedState14        = 0x0E
    case unknown                = 0x0F
    
    
    static let MASK: UInt8      = 0xF
    
    public func toString() -> String {
        switch self {
        case .probeNotInserted:
            return "Probe Not Inserted"
        case .probeInserted:
            return "Probe Inserted"
        case .cooking:
            return "Cooking"
        case .predicting:
            return "Predicting"
        case .removalPredictionDone:
            return "Removal Prediction Done"
        case .reservedState5:
            return "Reserved State 5"
        case .reservedState6:
            return "Reserved State 6"
        case .reservedState7:
            return "Reserved State 7"
        case .reservedState8:
            return "Reserved State 8"
        case .reservedState9:
            return "Reserved State 9"
        case .reservedState10:
            return "Reserved State 10"
        case .reservedState11:
            return "Reserved State 11"
        case .reservedState12:
            return "Reserved State 12"
        case .reservedState13:
            return "Reserved State 13"
        case .reservedState14:
            return "Reserved State 14"
        case .unknown:
            return "Unknown"
        }
    }
}
