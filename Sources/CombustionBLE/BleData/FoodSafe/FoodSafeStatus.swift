//  FoodSafeStatus.swift

/*--
MIT License

Copyright (c) 2023 Combustion Inc.

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

public struct FoodSafeStatus: Equatable {
    public let state: FoodSafeState
    public let logReduction: Double
    public let secondsAboveThreshold: UInt
    public let foodSafeSequenceNumber: UInt
    
    public init(state: FoodSafeState, logReduction: Double, secondsAboveThreshold: UInt, foodSafeSequenceNumber: UInt) {
        self.state = state
        self.logReduction = logReduction
        self.secondsAboveThreshold = secondsAboveThreshold
        self.foodSafeSequenceNumber = foodSafeSequenceNumber
    }
}

extension FoodSafeStatus {
    
    /// Parses Food Safe Status data from raw data buffer
    static func fromRawData(data: Data) -> FoodSafeStatus? {
        guard data.count >= 8 else { return nil }

        // Safe State - 3 bits
        let rawState = data[0] & FoodSafeState.MASK
        let state = FoodSafeState(rawValue: rawState) ?? .notSafe
        
        // Log Reduction - 8 bits
        let rawLogReduction = ((data[0] & 0xF8) >> 3) | ((data[1] & 0x07) << 5)
        
        // Seconds above threshold - 16 bits
        let secondsAboveThreshold =  (UInt16(data[1]) & 0xF8) >> 3  |
                                     (UInt16(data[2]) & 0xFF) << 5  |
                                     (UInt16(data[3]) & 0x07) << 13
        
        // Food safe log sequence number - 32 bits
        let foodSafeSequenceNumber = (UInt32(data[3]) & 0xF8) >> 3   |
                                     (UInt32(data[4]) & 0xFF) << 5   |
                                     (UInt32(data[5]) & 0xFF) << 13  |
                                     (UInt32(data[6]) & 0xFF) << 21  |
                                     (UInt32(data[7]) & 0x07) << 29

        return FoodSafeStatus(
            state: state,
            logReduction: Double(rawLogReduction) * 0.1,
            secondsAboveThreshold: UInt(secondsAboveThreshold), 
            foodSafeSequenceNumber: UInt(foodSafeSequenceNumber)
        )
    }
}
