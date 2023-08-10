//  PredictionInfo.swift
//  Probe prediction information

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

public struct PredictionInfo {
    public let predictionState: PredictionState
    public let predictionMode: PredictionMode
    public let predictionType: PredictionType
    public let predictionSetPointTemperature: Double
    public let estimatedCoreTemperature: Double
    
    public let secondsRemaining: UInt?
    public let percentThroughCook: Int
}

extension PredictionInfo {
    
    /// Helper function to check if prediction is running
    public func predictionIsRunning() -> Bool {
        return predictionMode == .timeToRemoval
    }
    
    /// Helper function to check if prediction is running and complete
    public func predictionIsComplete() -> Bool {
        guard predictionIsRunning() else { return false }
        
        if (predictionState != .predicting) && (estimatedCoreTemperature > predictionSetPointTemperature) {
            return true
        }
        
        return predictionState == .removalPredictionDone
    }
}
