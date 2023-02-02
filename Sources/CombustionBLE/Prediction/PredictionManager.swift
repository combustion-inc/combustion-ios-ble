//  PredictionManager.swift
//  Prediction manager

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

protocol PredictionManagerDelegate: AnyObject {
    func publishPredictionInfo(info: PredictionInfo?)
}

class PredictionManager {
    private enum Constants {
        /// Prediction is considered stale after 15 seconds
        static let PREDICTION_STALE_TIMEOUT = 15.0
        
        /// Cap the prediction to 4 hours
        static let MAX_PREDICTION_TIME : UInt = 60*60*4
        
        /// Number of samples to wait between updates to prediction 'seconds remaining',
        /// for syncing time remaining across apps, Displays etc.
        static let PREDICTION_TIME_UPDATE_COUNT : UInt = 3
        
        /// Number of prediction seconds at or above which to round the 'time remaining' display.
        static let LOW_RESOLUTION_CUTOFF_SECONDS : UInt = 60*5
        
        /// Resolution of prediction display in 'low resolution' mode.
        static let LOW_RESOLUTION_PRECISION_SECONDS : UInt = 15
        
        /// Rate at which the linearization timer is run
        static let LINEARIZATION_UPDATE_RATE_MS : Double = 200.0
        
        /// Rate at which the linearization timer is run
        static let PREDICTION_STATUS_RATE_MS : Double = 5000.0
    }
    
    weak var delegate: PredictionManagerDelegate?

    private var previousPredictionInfo: PredictionInfo?
    private var previousSequenceNumber: UInt32?
    
    private var linearizationTargetSeconds = 0
    private var linearizationTimerUpdateValue: Double = 0
    private var currentLinearizationMs: Double = 0
    
    private var linearizationTimer = Timer()
    private var staleTimer = Timer()
    
    func updatePredictionStatus(_ predictionStatus: PredictionStatus?, sequenceNumber: UInt32) {
        // Ignore calls with duplicate predictionStatus
        if let previousSequence = previousSequenceNumber, previousSequence == sequenceNumber {
            return
        }
        
        // Stop the previous timer
        clearLinearizationTimer()
        
        // Update prediction information with latest prediction status from probe
        let predictionInfo = infoFromStatus(predictionStatus, sequenceNumber: sequenceNumber)
        
        // Save sequence number to check for duplicates
        previousSequenceNumber = sequenceNumber
        
        // Publish new prediction info
        publishPredictionInfo(predictionInfo)
        
        // Clear previous staleness timer.
        staleTimer.invalidate()
        // Restart 'staleness' timer.
        let intervalSeconds = Constants.PREDICTION_STALE_TIMEOUT;
        staleTimer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: false, block: { _ in
            // If updates have gone stale (not arrived in some time), restart the timer.
            self.clearLinearizationTimer()
        })
    }
    
    private func infoFromStatus(_ predictionStatus: PredictionStatus?,
                           sequenceNumber: UInt32) -> PredictionInfo? {
        guard let status = predictionStatus else { return nil }

        let secondsRemaining = secondsRemaining(predictionStatus: status,
                                                sequenceNumber: sequenceNumber)
        
        return PredictionInfo(predictionState: status.predictionState,
                              predictionMode: status.predictionMode,
                              predictionType: status.predictionType,
                              predictionSetPointTemperature: status.predictionSetPointTemperature,
                              estimatedCoreTemperature: status.estimatedCoreTemperature,
                              secondsRemaining: secondsRemaining,
                              percentThroughCook: percentThroughCook(predictionStatus: status))
    }
    
    
    private func secondsRemaining(predictionStatus: PredictionStatus,
                                  sequenceNumber: UInt32) -> UInt? {
        
        // Do not return a value if not in predicting state
        guard predictionStatus.predictionState == .predicting else { return nil }
        
        // Do not return a value if above max seconds remaining
        guard predictionStatus.predictionValueSeconds <= Constants.MAX_PREDICTION_TIME else { return nil }
        
        let previousSecondsRemaining = previousPredictionInfo?.secondsRemaining
        
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
            
            // If we're less than the 'low-resolution' cutoff time, linearize the value

            // Calculate new linearization target, when next prediction status arrives (in 5 seconds)
            // the linearization should hit the current prediction - 5 seconds
            let predictionUpdateRateSeconds = UInt(Constants.PREDICTION_STATUS_RATE_MS / 1000.0)
            if(predictionStatus.predictionValueSeconds < predictionUpdateRateSeconds) {
                linearizationTargetSeconds = 0
            }
            else {
                linearizationTargetSeconds = Int(predictionStatus.predictionValueSeconds - predictionUpdateRateSeconds)
            }

            if previousPredictionInfo?.predictionState == .predicting {
                let intervalCount = Constants.PREDICTION_STATUS_RATE_MS / Constants.LINEARIZATION_UPDATE_RATE_MS
                linearizationTimerUpdateValue = (currentLinearizationMs - (Double(linearizationTargetSeconds) * 1000.0)) / intervalCount
            }
            else {
                currentLinearizationMs = Double(predictionStatus.predictionValueSeconds) * 1000.0
                linearizationTimerUpdateValue = Constants.LINEARIZATION_UPDATE_RATE_MS
            }
            
            // Setup a linearization timer
            let intervalSeconds = Constants.LINEARIZATION_UPDATE_RATE_MS / 1000.0 ;
            linearizationTimer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true, block: { _ in
                self.updatePredictionSeconds()
            })
            
            return UInt(currentLinearizationMs / 1000.0)
        }
    }
    
    private func updatePredictionSeconds() {
        guard let previousInfo = previousPredictionInfo else { return }

        currentLinearizationMs -= linearizationTimerUpdateValue
        
        let secondsRemaining = UInt(currentLinearizationMs / 1000.0)
        
        let info = PredictionInfo(predictionState: previousInfo.predictionState,
                                  predictionMode: previousInfo.predictionMode,
                                  predictionType: previousInfo.predictionType,
                                  predictionSetPointTemperature: previousInfo.predictionSetPointTemperature,
                                  estimatedCoreTemperature: previousInfo.estimatedCoreTemperature,
                                  secondsRemaining: secondsRemaining,
                                  percentThroughCook: previousInfo.percentThroughCook)
        
        // Publish new prediction info
        publishPredictionInfo(info)
    }
    
    private func percentThroughCook(predictionStatus: PredictionStatus) -> Int {
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
    
    private func publishPredictionInfo(_ predictionInfo: PredictionInfo?) {
        // Save prediction information
        previousPredictionInfo = predictionInfo
        
        // Send new value to delegate
        delegate?.publishPredictionInfo(info: predictionInfo)
    }
    
    private func clearLinearizationTimer() {
        linearizationTimer.invalidate()
    }
}
