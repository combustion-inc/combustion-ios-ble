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

public struct CSV {
    
    /// Helper function that generates a CSV representation of probe data.
    private static func probeDataToCsv(probe: Probe, appVersion: String, date: Date) -> String {
        var output = [String]()
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateString = dateFormatter.string(from: date)
        
        output.append("Combustion Inc. Probe Data")
        output.append("App: iOS \(appVersion)")
        output.append("CSV version: 3")
        output.append("Probe S/N: \(String(format: "%4X", probe.serialNumber))")
        output.append("Probe FW version: \(probe.firmareVersion ?? "??")")
        output.append("Probe HW revision: \(probe.hardwareRevision ?? "??")")
        output.append("Framework: iOS")
        output.append("Sample Period: \(probe.temperatureLogs.first?.sessionInformation.samplePeriod ?? 0)")
        output.append("Created: \(dateString)")
        output.append("")
        
        // Header
        output.append("Timestamp,SessionID,SequenceNumber,T1,T2,T3,T4,T5,T6,T7,T8")
        
        // Add temperature data points
        if let firstSessionStart = probe.temperatureLogs.first?.startTime?.timeIntervalSince1970 {
            for session in probe.temperatureLogs {
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

                    
                    output.append(String(format: "%.3f,%u,%d,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f",
                                         timeStamp,
                                         session.id,
                                         dataPoint.sequenceNum,
                                         dataPoint.temperatures.values[0], dataPoint.temperatures.values[1],
                                         dataPoint.temperatures.values[2], dataPoint.temperatures.values[3],
                                         dataPoint.temperatures.values[4], dataPoint.temperatures.values[5],
                                         dataPoint.temperatures.values[6], dataPoint.temperatures.values[7]))
                }
            }
        }

        
        
        return output.joined(separator: "\n")
    }
    
    /// Creates a CSV file for export.
    /// - param probe: Probe for which to create the file
    /// - returns: URL of file
    public static func createCsvFile(probe: Probe, appVersion: String) -> URL? {
        let date = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH_mm_ss"
        let dateString = dateFormatter.string(from: date)
        
        let filename = "Probe Data - \(String(format: "%4X", probe.serialNumber)) - \(dateString).csv"
        
        // Generate the CSV
        let csv = probeDataToCsv(probe: probe, appVersion: appVersion, date: date)
        
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
