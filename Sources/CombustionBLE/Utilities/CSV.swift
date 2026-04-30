//  CSV.swift
//  CSV export of probe data

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

public struct CSVNote: Hashable {
    public let timestamp: Date
    public let text: String

    public init(timestamp: Date, text: String) {
        self.timestamp = timestamp
        self.text = text
    }
}

public struct CSV {

    private struct DataPointNoteMatch {
        let csvTimestamp: String
        let absoluteTimestamp: Date
    }
    
    private static func gaugeDataToCsv(serialNumber: String,
                                       temperatureLogs: [DeviceTemperatureLog],
                                       firmwareVersion: String?,
                                       hardwareRevision: String?,
                                       appVersion: String,
                                       date: Date,
                                       notes: [CSVNote]) -> String {
        var output = [String]()
        let notesByTimestamp = notesByCSVTimestamp(notes: notes,
                                                   dataPointMatches: dataPointMatches(from: temperatureLogs))
        let includesNotes = !notes.isEmpty
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateString = dateFormatter.string(from: date)
        
        output.append("Combustion Inc. Gauge Data")
        output.append("App: iOS \(appVersion)")
        output.append("CSV version: 4")
        output.append("Gauge S/N: \(serialNumber)")
        output.append("Gauge FW version: \(firmwareVersion ?? "??")")
        output.append("Gauge HW revision: \(hardwareRevision ?? "??")")
        output.append("Framework: iOS")
        output.append("Sample Period: \(temperatureLogs.first?.sessionInformation.samplePeriod ?? 0)")
        output.append("Created: \(dateString)")
        output.append("")
        
        // Header
        output.append("Timestamp,SessionID,SequenceNumber,Temperature\(includesNotes ? ",Notes" : "")")
        
        // Add temperature data points
        if let firstSessionStart = temperatureLogs.first?.startTime?.timeIntervalSince1970 {
            for session in temperatureLogs {
                for dataPoint in session.dataPoints {
                    
                    // Calculate timestamp for current data point
                    var timeStamp: TimeInterval = 0
                    if let currentSessionStart = session.startTime?.timeIntervalSince1970 {
                        // Number of seconds between first session start time and current start time
                        let sessionStartTimeDiff = currentSessionStart - firstSessionStart
                        
                        // Number of seconds beteen current data point and session start time
                        let dataPointSeconds = Double(dataPoint.sequenceNum) * Double(session.sessionInformation.samplePeriod) / 1000.0
                        
                        // Number of seconds between current data point and first session start
                        timeStamp = dataPointSeconds + sessionStartTimeDiff
                    }
                    
                    if let temp = dataPoint.temperatureForChannelIndex(0) {
                        let csvTimestamp = String(format: "%.3f", timeStamp)
                        var values = String(format: "%@,%u,%d,%.2f",
                                          csvTimestamp,
                                          session.id,
                                          dataPoint.sequenceNum,
                                            temp)
                        appendNote(to: &values,
                                   csvTimestamp: csvTimestamp,
                                   notesByTimestamp: notesByTimestamp,
                                   includesNotes: includesNotes)
                        output.append(values)
                    }
                    else {
                        let csvTimestamp = String(format: "%.3f", timeStamp)
                        var values = String(format: "%@,%u,%d,",
                                          csvTimestamp,
                                          session.id,
                                          dataPoint.sequenceNum)
                        
                        values += "-"
                        appendNote(to: &values,
                                   csvTimestamp: csvTimestamp,
                                   notesByTimestamp: notesByTimestamp,
                                   includesNotes: includesNotes)
                        output.append(values)
                    }
                }
            }
        }

        
        
        return output.joined(separator: "\n")
    }
    
    
    /// Helper function that generates a CSV representation of probe data.
    private static func probeDataToCsv(serialNumber: String,
                                       temperatureLogs: [ProbeTemperatureLog],
                                       firmwareVersion: String?,
                                       hardwareRevision: String?,
                                       appVersion: String,
                                       date: Date,
                                       notes: [CSVNote]) -> String {
        var output = [String]()
        let notesByTimestamp = notesByCSVTimestamp(notes: notes,
                                                   dataPointMatches: dataPointMatches(from: temperatureLogs))
        let includesNotes = !notes.isEmpty
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateString = dateFormatter.string(from: date)
        
        output.append("Combustion Inc. Probe Data")
        output.append("App: iOS \(appVersion)")
        output.append("CSV version: 4")
        output.append("Probe S/N: \(serialNumber)")
        output.append("Probe FW version: \(firmwareVersion ?? "??")")
        output.append("Probe HW revision: \(hardwareRevision ?? "??")")
        output.append("Framework: iOS")
        output.append("Sample Period: \(temperatureLogs.first?.sessionInformation.samplePeriod ?? 0)")
        output.append("Created: \(dateString)")
        output.append("")
        
        // Header
        output.append("Timestamp,SessionID,SequenceNumber,T1,T2,T3,T4,T5,T6,T7,T8,VirtualCoreTemperature,VirtualSurfaceTemperature,VirtualAmbientTemperature,EstimatedCoreTemperature,PredictionSetPoint,VirtualCoreSensor,VirtualSurfaceSensor,VirtualAmbientSensor,PredictionState,PredictionMode,PredictionType,PredictionValueSeconds\(includesNotes ? ",Notes" : "")")
        
        // Add temperature data points
        if let firstSessionStart = temperatureLogs.first?.startTime?.timeIntervalSince1970 {
            for session in temperatureLogs {
                for dataPoint in session.dataPoints {
                    
                    // Calculate timestamp for current data point
                    var timeStamp: TimeInterval = 0
                    if let currentSessionStart = session.startTime?.timeIntervalSince1970 {
                        // Number of seconds between first session start time and current start time
                        let sessionStartTimeDiff = currentSessionStart - firstSessionStart
                        
                        // Number of seconds beteen current data point and session start time
                        let dataPointSeconds = Double(dataPoint.sequenceNum) * Double(session.sessionInformation.samplePeriod) / 1000.0
                        
                        // Number of seconds between current data point and first session start
                        timeStamp = dataPointSeconds + sessionStartTimeDiff
                    }
                    
                    let csvTimestamp = String(format: "%.3f", timeStamp)
                    var values = String(format: "%@,%u,%d,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,",
                                      csvTimestamp,
                                      session.id,
                                      dataPoint.sequenceNum,
                                      dataPoint.temperatures.values[0], dataPoint.temperatures.values[1],
                                      dataPoint.temperatures.values[2], dataPoint.temperatures.values[3],
                                      dataPoint.temperatures.values[4], dataPoint.temperatures.values[5],
                                      dataPoint.temperatures.values[6], dataPoint.temperatures.values[7],
                                      dataPoint.virtualCore.temperatureFrom(dataPoint.temperatures),
                                      dataPoint.virtualSurface.temperatureFrom(dataPoint.temperatures),
                                      dataPoint.virtualAmbient.temperatureFrom(dataPoint.temperatures),
                                      dataPoint.estimatedCoreTemperature,
                                      dataPoint.predictionSetPointTemperature)
                    
                    values += "\(dataPoint.virtualCore),"
                    values += "\(dataPoint.virtualSurface),"
                    values += "\(dataPoint.virtualAmbient),"
                    values += "\(dataPoint.predictionState.toString()),"
                    values += "\(dataPoint.predictionMode.toString()),"
                    values += "\(dataPoint.predictionType.toString()),"
                    values += "\(dataPoint.predictionValueSeconds)"
                    appendNote(to: &values,
                               csvTimestamp: csvTimestamp,
                               notesByTimestamp: notesByTimestamp,
                               includesNotes: includesNotes)
                    
                    output.append(values)
                }
            }
        }

        
        
        return output.joined(separator: "\n")
    }
    
    /// Creates a CSV file for export.
    /// - param gauge: Gauge for which to create the file
    /// - returns: URL of file
    public static func createCSVFile(serialNumber: String,
                                     gaugeLogs: [DeviceTemperatureLog],
                                     firmwareVersion: String?,
                                     hardwareRevision: String?,
                                     appVersion: String,
                                     notes: [CSVNote] = []) -> URL? {
        let date = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH_mm_ss"
        let dateString = dateFormatter.string(from: date)
        
        let filename = "GaugeData_\(serialNumber)_\(dateString).csv"
        
        // Generate the CSV
        let csv = gaugeDataToCsv(serialNumber: serialNumber,
                                 temperatureLogs: gaugeLogs,
                                 firmwareVersion: firmwareVersion,
                                 hardwareRevision: hardwareRevision,
                                 appVersion: appVersion,
                                 date: date,
                                 notes: notes)
        
        // Create the temporary file
        let filePath = NSTemporaryDirectory() + "/" + filename;
        
        let csvURL = URL(fileURLWithPath: filePath)
        
        do {
            try csv.write(to: csvURL, atomically: true, encoding: String.Encoding.utf8)
        } catch {
            // Failed to write file, return nothing
            return nil
        }
        
        return csvURL
    }
    
    /// Creates a CSV file for export.
    /// - param probe: Probe for which to create the file
    /// - returns: URL of file
    public static func createCsvFile(serialNumber: String, 
                                     temperatureLogs: [ProbeTemperatureLog],
                                     firmwareVersion: String?,
                                     hardwareRevision: String?,
                                     appVersion: String,
                                     notes: [CSVNote] = []) -> URL? {
        let date = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH_mm_ss"
        let dateString = dateFormatter.string(from: date)
        
        let filename = "ProbeData_\(serialNumber)_\(dateString).csv"
        
        // Generate the CSV
        let csv = probeDataToCsv(serialNumber: serialNumber,
                                 temperatureLogs: temperatureLogs,
                                 firmwareVersion: firmwareVersion,
                                 hardwareRevision: hardwareRevision,
                                 appVersion: appVersion,
                                 date: date,
                                 notes: notes)
        
        // Create the temporary file
        let filePath = NSTemporaryDirectory() + "/" + filename;
        
        let csvURL = URL(fileURLWithPath: filePath)
        
        do {
            try csv.write(to: csvURL, atomically: true, encoding: String.Encoding.utf8)
        } catch {
            // Failed to write file, return nothing
            return nil
        }
        
        return csvURL
    }

    private static func appendNote(to values: inout String,
                                   csvTimestamp: String,
                                   notesByTimestamp: [String: String],
                                   includesNotes: Bool) {
        guard includesNotes else { return }
        values += ",\(csvEscaped(notesByTimestamp[csvTimestamp] ?? ""))"
    }

    private static func notesByCSVTimestamp(notes: [CSVNote],
                                            dataPointMatches: [DataPointNoteMatch]) -> [String: String] {
        guard !notes.isEmpty, !dataPointMatches.isEmpty else {
            return [:]
        }

        var matchedNotes: [String: [String]] = [:]
        let sortedDataPointMatches = dataPointMatches.sorted {
            $0.absoluteTimestamp < $1.absoluteTimestamp
        }

        for note in notes {
            guard let match = nearestMatch(to: note.timestamp, in: sortedDataPointMatches) else {
                continue
            }
            matchedNotes[match.csvTimestamp, default: []].append(note.text)
        }

        return matchedNotes.mapValues { $0.joined(separator: " | ") }
    }

    private static func nearestMatch(to timestamp: Date,
                                     in dataPointMatches: [DataPointNoteMatch]) -> DataPointNoteMatch? {
        guard !dataPointMatches.isEmpty else {
            return nil
        }

        var lowerBound = 0
        var upperBound = dataPointMatches.count

        while lowerBound < upperBound {
            let midpoint = lowerBound + (upperBound - lowerBound) / 2

            if dataPointMatches[midpoint].absoluteTimestamp < timestamp {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }

        if lowerBound == 0 {
            return dataPointMatches[0]
        }

        if lowerBound == dataPointMatches.count {
            return dataPointMatches[dataPointMatches.count - 1]
        }

        let previous = dataPointMatches[lowerBound - 1]
        let next = dataPointMatches[lowerBound]
        let previousDistance = abs(previous.absoluteTimestamp.timeIntervalSince(timestamp))
        let nextDistance = abs(next.absoluteTimestamp.timeIntervalSince(timestamp))

        return previousDistance <= nextDistance ? previous : next
    }

    private static func dataPointMatches(from logs: [ProbeTemperatureLog]) -> [DataPointNoteMatch] {
        guard let firstSessionStart = logs.first?.startTime else {
            return []
        }

        return logs.flatMap { log -> [DataPointNoteMatch] in
            guard let sessionStart = log.startTime else {
                return []
            }

            return log.dataPoints.map { dataPoint in
                makeDataPointMatch(firstSessionStart: firstSessionStart,
                                   sessionStart: sessionStart,
                                   samplePeriod: log.sessionInformation.samplePeriod,
                                   sequenceNumber: dataPoint.sequenceNum)
            }
        }
    }

    private static func dataPointMatches(from logs: [DeviceTemperatureLog]) -> [DataPointNoteMatch] {
        guard let firstSessionStart = logs.first?.startTime else {
            return []
        }

        return logs.flatMap { log -> [DataPointNoteMatch] in
            guard let sessionStart = log.startTime else {
                return []
            }

            return log.dataPoints.map { dataPoint in
                makeDataPointMatch(firstSessionStart: firstSessionStart,
                                   sessionStart: sessionStart,
                                   samplePeriod: log.sessionInformation.samplePeriod,
                                   sequenceNumber: dataPoint.sequenceNum)
            }
        }
    }

    private static func makeDataPointMatch(firstSessionStart: Date,
                                           sessionStart: Date,
                                           samplePeriod: UInt16,
                                           sequenceNumber: UInt32) -> DataPointNoteMatch {
        let dataPointSeconds = Double(sequenceNumber) * Double(samplePeriod) / 1000.0
        let relativeTimestamp = sessionStart.timeIntervalSince(firstSessionStart) + dataPointSeconds
        let absoluteTimestamp = sessionStart.addingTimeInterval(dataPointSeconds)

        return DataPointNoteMatch(csvTimestamp: String(format: "%.3f", relativeTimestamp),
                                  absoluteTimestamp: absoluteTimestamp)
    }

    private static func csvEscaped(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
            return value
        }

        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    
    
    /// Cleans up the temporary CSV file at location
    func cleanUpCsvFile(url: URL) {
        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: url.absoluteString) {
                try fileManager.removeItem(atPath: url.absoluteString)
            }
        } catch {
            // Couldn't delete, don't worry about it
        }
    }
    
}
