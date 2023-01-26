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
    
    private enum Constants {
        /// Cap the prediction to 4 hours
        static let MAX_PREDICTION_TIME : UInt = 60*60*4
        
        /// Number of samples to wait between updates to prediction 'seconds remaining',
        /// for syncing time remaining across apps, Displays etc.
        static let PREDICTION_TIME_UPDATE_COUNT : UInt = 3
        
        /// Number of prediction seconds at or above which to round the 'time remaining' display.
        static let LOW_RESOLUTION_CUTOFF_SECONDS : UInt = 60*5
        
        /// Resolution of prediction display in 'low resolution' mode.
        static let LOW_RESOLUTION_PRECISION_SECONDS : UInt = 15
    }
    
    static func fromStatus(_ predictionStatus: PredictionStatus?,
                           previousInfo: PredictionInfo?,
                           sequenceNumber: UInt32) -> PredictionInfo? {
        guard let status = predictionStatus else { return nil}
        
        let secondsRemaining = secondsRemaining(predictionStatus: status,
                                               previousInfo: previousInfo,
                                               sequenceNumber: sequenceNumber)
        
        return PredictionInfo(predictionState: status.predictionState,
                              predictionMode: status.predictionMode,
                              predictionType: status.predictionType,
                              predictionSetPointTemperature: status.predictionSetPointTemperature,
                              estimatedCoreTemperature: status.estimatedCoreTemperature,
                              secondsRemaining: secondsRemaining,
                              percentThroughCook: percentThroughCook(predictionStatus: status))
    }
    

    private static func secondsRemaining(predictionStatus: PredictionStatus,
                                        previousInfo: PredictionInfo?,
                                        sequenceNumber: UInt32) -> UInt? {
        // Do not return a value if above max seconds remaining
        guard predictionStatus.predictionValueSeconds <= Constants.MAX_PREDICTION_TIME else { return nil }
        
        let previousSecondsRemaining = previousInfo?.secondsRemaining
        
        if(predictionStatus.predictionValueSeconds > Constants.LOW_RESOLUTION_CUTOFF_SECONDS) {
            // If the prediction is longer than the low-resolution cutoff, only update every few samples
            // (unless we don't yet have a value), using modulo to sync with other apps, Displays etc.
            if previousSecondsRemaining == nil || (UInt(sequenceNumber) % Constants.PREDICTION_TIME_UPDATE_COUNT) == 0 {
                // In low-resolution mode, round the value to the nearest 15 seconds.
                let remainder = predictionStatus.predictionValueSeconds % Constants.LOW_RESOLUTION_PRECISION_SECONDS
                if(remainder > (Constants.LOW_RESOLUTION_PRECISION_SECONDS / 2)) {
                    // Round up
                    return predictionStatus.predictionValueSeconds + (Constants.LOW_RESOLUTION_PRECISION_SECONDS - remainder)
                } else {
                    // Round down
                    return predictionStatus.predictionValueSeconds - remainder
                }
            }
            else {
                return previousSecondsRemaining
            }
        } else {
            // If we're less than the 'low-resolution' cutoff time, use the actual value for every sample.
            // TODO - linearize this value.
            return predictionStatus.predictionValueSeconds
        }
    }
    
    private static func percentThroughCook(predictionStatus: PredictionStatus) -> Int {
        let start = predictionStatus.heatStartTemperature
        let end = predictionStatus.predictionSetPointTemperature
        let core = predictionStatus.estimatedCoreTemperature
        
        // Max percentage is 100
        if(core > end) {
            return 100
        }
        
        // Minimum percentage is 0
        if(start > core) {
            return 0
        }
        
        return Int(((core - start) / (end - start)) * 100.0)
    }
}
