//  ProbeTemperatureLog.swift

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
import OrderedCollections

public class ProbeTemperatureLog : ObservableObject {
    
    public let sessionInformation: SessionInformation
    
    /// Buffer of logged data points
    public var dataPointsDict : OrderedDictionary<UInt32, LoggedProbeDataPoint>
    
    /// Ordered array of data points in the buffer
    public var dataPoints : [LoggedProbeDataPoint] {
        get {
            return Array(dataPointsDict.values)
        }
    }
    
    /// Approximate start time of the session
    public var startTime: Date? = nil
    
    /// Number of MS to wait for new log data to flow in before inserting it into the data buffer.
    private let ACCUMULATOR_STABILIIZATION_TIME = 0.2
    /// Maximum number of records to allow to build up in the accumulator before forcing an update
    private let ACCUMULATOR_MAX = 500
    
    /// Timer used to cause records to accumulate in the accumulator prior to being bulk-inserted into
    /// the main list.
    private var accumulatorTimer : Timer? = nil
    
    /// Temporary place for incoming data points to accumulate prior to being inserted into the main
    /// data point dictionary. This prevents unnecesary re-sorting of the overall dictionary.
    private var dataPointAccumulator : OrderedSet<LoggedProbeDataPoint>
    
    init(sessionInfo: SessionInformation) {
        dataPointsDict = OrderedDictionary<UInt32, LoggedProbeDataPoint>()
        dataPointAccumulator = OrderedSet<LoggedProbeDataPoint>()
        sessionInformation = sessionInfo
    }
    
    /// Finds the first missing sequence number in the specified range of sequence numbers.
    /// - parameter sequenceRangeStart: First sequence number to search for
    /// - parameter sequenceRangeEnd: Last sequence number to search for
    func firstMissingIndex(sequenceRangeStart: UInt32, sequenceRangeEnd: UInt32) -> UInt32? {
        var found : UInt32? = nil
        for search in sequenceRangeStart...sequenceRangeEnd {
            if dataPointsDict[search] == nil {
                // Record was missing so we're done searching
                found = search
                break
            }
        }
        return found
    }
    
    /// Inserts data points from the accumulator into the
    private func insertAccumulatedDataPoints() {
        let maxIndex = dataPointAccumulator.count
        var added : Bool = false
        
        if maxIndex > 0 {
            // Add all the accumulated data points (if any) and sort the main list if any were added.
            for idx in 0..<maxIndex {
                let dp = dataPointAccumulator[idx]
                if dataPointsDict[dp.sequenceNum] == nil  {
                    // If the data point isn't already in our set, add it
                    dataPointsDict[dp.sequenceNum] = dp
                    added = true;
                }
            }
            
            // If any records were added to the buffer, sort it to ensure they appear in the correct
            // order.
            if(added) {
                dataPointsDict.sort { $0.key < $1.key }
            }
            
            // Delete the records in the accumulator that were processed
            dataPointAccumulator.removeFirst(maxIndex)
        }
    }
    
    /// Inserts a new data point. Places it in the accumulator so it can be inserted with additional
    /// records coming in.
    /// - parameter newDataPoint: New data points to be added to the buffer
    private func insertDataPoint(newDataPoint: LoggedProbeDataPoint) {
        // Add the incoming data point to the accumulator
        let appendResult = dataPointAccumulator.append(newDataPoint)
        if appendResult.inserted {
            // If the data point was inserted (i.e. it wasn't already in the accumulator), process it.
        
            // Stop the accumulator timer if it's running
            accumulatorTimer?.invalidate()
            accumulatorTimer = nil
            
            // If more than the max number of data points have been accumuated, trigger an insert
            if(dataPointAccumulator.count > ACCUMULATOR_MAX) {
                insertAccumulatedDataPoints()
            } else {
                // Otherwise reset the accumulation timer to trigger after a short time if no
                // new data points are added to the accumulator.
                self.accumulatorTimer = Timer.scheduledTimer(withTimeInterval: ACCUMULATOR_STABILIIZATION_TIME,
                                                             repeats: false) { _ in
                    self.insertAccumulatedDataPoints()
                }
            }
        }
    }
    
    /// Appends data point to the logged probe data.
    func appendDataPoint(dataPoint: LoggedProbeDataPoint) {
        // Check if new point's sequence number belongs at the end
        if let lastPoint = dataPointsDict.values.last {
            if(dataPoint.sequenceNum == (lastPoint.sequenceNum + 1)) {
                // If it does, simply add it and it will appear at the end of the ordered collection
                dataPointsDict[dataPoint.sequenceNum] = dataPoint
                
            } else {
                // If not, insert it at its appropriate location
                insertDataPoint(newDataPoint: dataPoint)
            }
        } else {
            // If the collection is empty, just add it
            dataPointsDict[dataPoint.sequenceNum] = dataPoint
            
            setStartTime(dataPoint: dataPoint)
        }
    }
    
    private func setStartTime(dataPoint: LoggedProbeDataPoint) {
        // Do not recalculate start time after it has been set
        guard startTime == nil else { return }
 
        let currentTime = Date()
        let secondDiff = Int(dataPoint.sequenceNum) * Int(sessionInformation.samplePeriod) / 1000
        startTime = Calendar.current.date(byAdding: .second, value: -1 * secondDiff, to: currentTime)
    }
}

extension ProbeTemperatureLog: Identifiable {
    
    // Use the Session ID for `Identifiable` protocol
    public var id: UInt32 {
        return sessionInformation.sessionID
    }
}
