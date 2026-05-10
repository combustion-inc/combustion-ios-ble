//  DeviceDataLog.swift
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

public class DeviceDataLog : ObservableObject {
    
    public let sessionInformation: SessionInformation
    private let stateLock = NSRecursiveLock()
    
    /// Buffer of logged data points
    public var dataPointsDict : OrderedDictionary<UInt32, LoggedDeviceDataPoint> {
        get { withLock { _dataPointsDict } }
        set { withLock { _dataPointsDict = newValue } }
    }
    private var _dataPointsDict : OrderedDictionary<UInt32, LoggedDeviceDataPoint>
    
    /// Ordered array of data points in the buffer
    public var dataPoints : [LoggedDeviceDataPoint] {
        get { withLock { Array(_dataPointsDict.values) } }
    }
    
    /// Approximate start time of the session
    public var startTime: Date? {
        get { withLock { _startTime } }
        set { withLock { _startTime = newValue } }
    }
    private var _startTime: Date? = nil
    
    /// Number of MS to wait for new log data to flow in before inserting it into the data buffer.
    private let ACCUMULATOR_STABILIIZATION_TIME = 0.2
    /// Maximum number of records to allow to build up in the accumulator before forcing an update
    private let ACCUMULATOR_MAX = 500
    
    /// Timer used to cause records to accumulate in the accumulator prior to being bulk-inserted into
    /// the main list.
    private var accumulatorTimer : Timer? = nil
    
    /// Temporary place for incoming data points to accumulate prior to being inserted into the main
    /// data point dictionary. This prevents unnecesary re-sorting of the overall dictionary.
    private var dataPointAccumulator = OrderedSet<LoggedDeviceDataPoint>()
    
    /// Initialize empty temperature log
    public init(sessionInfo: SessionInformation) {
        _dataPointsDict = OrderedDictionary<UInt32, LoggedDeviceDataPoint>()
        sessionInformation = sessionInfo
    }
    
    /// Initialize with data points
    public init(sessionInformation: SessionInformation,
                dataPointsDict: OrderedDictionary<UInt32, LoggedDeviceDataPoint>,
                startTime: Date?) {
        self.sessionInformation = sessionInformation
        self._dataPointsDict = dataPointsDict
        self._startTime = startTime
    }
    
    /// Finds the missing sequence number range in the specified range of sequence numbers.
    /// - parameter sequenceRangeStart: First sequence number to search for
    /// - parameter sequenceRangeEnd: Last sequence number to search for
    /// - returns: Range of the lowest to highest missing sequence numbers.
    func missingRange(sequenceRangeStart: UInt32, sequenceRangeEnd: UInt32) -> ClosedRange<UInt32>? {
        withLock {
            var missingRange : ClosedRange<UInt32>? = nil
            
            var lowerBound : UInt32? = nil
            
            // Find the lower bound
            for search in sequenceRangeStart...sequenceRangeEnd {
                if _dataPointsDict[search] == nil {
                    // Record was missing so we're done searching
                    lowerBound = search
                    break
                }
            }
            
            if let lowerBound = lowerBound {
                // If a lower bound was found, find the upper bound.
                var upperBound : UInt32? = nil
                
                if lowerBound < sequenceRangeEnd {
                    for search in (lowerBound+1...sequenceRangeEnd).reversed() {
                        if _dataPointsDict[search] == nil {
                            // Record was missing so we're done searching
                            upperBound = search
                            break
                        }
                    }
                }
                
                if let upperBound = upperBound {
                    // If an upper bound was found, update the return range.
                    missingRange = lowerBound ... upperBound
                } else {
                    // If not, grab everything from the lower bound on
                    missingRange = lowerBound ... sequenceRangeEnd
                }
            }
            
            return missingRange
        }
    }
    
    
    /// Calculates the number of logs that have been received in the specified range of sequence numbers.
    /// - parameter range: Range of sequence numbers to check
    /// - returns number of log records received in that range.
    func logsInRange(sequenceNumbers: ClosedRange<UInt32>) -> Int {
        withLock {
            var records = 0
            
            // Find index of lowest element >= min
            if(!_dataPointsDict.isEmpty) {
                if let min = _dataPointsDict.keys.firstIndex(where: { $0 >= sequenceNumbers.lowerBound } ) {
                    // Find index of highest element <= max
                    if let max = _dataPointsDict.keys.lastIndex(where: { $0 <= sequenceNumbers.upperBound } ) {
                        records = max-min+1
                    }
                }
            }
           
            return records
        }
    }
    
    /// Inserts data points from the accumulator into the
    private func insertAccumulatedDataPoints() {
        withLock {
            let maxIndex = dataPointAccumulator.count
            var added : Bool = false
            
            if maxIndex > 0 {
                // Add all the accumulated data points (if any) and sort the main list if any were added.
                for idx in 0..<maxIndex {
                    let dp = dataPointAccumulator[idx]
                    if _dataPointsDict[dp.sequenceNum] == nil  {
                        // If the data point isn't already in our set, add it
                        _dataPointsDict[dp.sequenceNum] = dp
                        added = true;
                    }
                }
                
                // If any records were added to the buffer, sort it to ensure they appear in the correct
                // order.
                if(added) {
                    _dataPointsDict.sort { $0.key < $1.key }
                }
                
                // Delete the records in the accumulator that were processed
                dataPointAccumulator.removeFirst(maxIndex)
            }
        }
    }
    
    /// Inserts a new data point. Places it in the accumulator so it can be inserted with additional
    /// records coming in.
    /// - parameter newDataPoint: New data points to be added to the buffer
    private func insertDataPoint(newDataPoint: LoggedDeviceDataPoint) {
        withLock {
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
    }
    
    /// Appends data point to the logged probe data.
    public func appendDataPoint(dataPoint: LoggedDeviceDataPoint, sampledAt: Date? = nil) {
        withLock {
            // Check if new point's sequence number belongs at the end
            if let lastPoint = _dataPointsDict.values.last {
                if(dataPoint.sequenceNum == (lastPoint.sequenceNum + 1)) {
                    // If it does, simply add it and it will appear at the end of the ordered collection
                    _dataPointsDict[dataPoint.sequenceNum] = dataPoint
                    
                } else {
                    // If not, insert it at its appropriate location
                    insertDataPoint(newDataPoint: dataPoint)
                }
            } else {
                // If the collection is empty, just add it
                _dataPointsDict[dataPoint.sequenceNum] = dataPoint
            }
        
            // Set the start time of this session
            if let sampledAt = sampledAt {
                setStartTime(dataPoint: dataPoint, sampledAt: sampledAt)
            }
        }
    }
    
    /// Sets the session start time based on the datapoint and sample timestamp.
    /// - parameter dataPoint: Data point to calculate session start time from
    /// - parameter sampledAt: Time when data point was sampled
    private func setStartTime(dataPoint: LoggedDeviceDataPoint, sampledAt: Date) {
        withLock {
            // Do not recalculate start time after it has been set
            guard _startTime == nil else { return }
     
            let secondDiff = Int(dataPoint.sequenceNum) * Int(sessionInformation.samplePeriod) / 1000
            _startTime = Calendar.current.date(byAdding: .second, value: -1 * secondDiff, to: sampledAt)
        }
    }
    
    @inline(__always)
    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try body()
    }
}

extension DeviceDataLog: Identifiable {
    
    // Use the Session ID for `Identifiable` protocol
    public var id: UInt32 {
        return sessionInformation.sessionID
    }
}

@available(*, deprecated, renamed: "DeviceDataLog")
public typealias DeviceTemperatureLog = DeviceDataLog
