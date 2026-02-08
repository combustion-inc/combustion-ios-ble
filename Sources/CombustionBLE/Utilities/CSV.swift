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
    
    private static func gaugeDataToCsv(serialNumber: String,
                                       temperatureLogs: [DeviceDataLog],
                                       firmwareVersion: String?,
                                       hardwareRevision: String?,
                                       appVersion: String,
                                       date: Date) -> String {
        var output = [String]()
        
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
        output.append("Timestamp,SessionID,SequenceNumber,Temperature")
        
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
                        var values = String(format: "%.3f,%u,%d,%.2f",
                                          timeStamp,
                                          session.id,
                                          dataPoint.sequenceNum,
                                            temp)
                        output.append(values)
                    }
                    else {
                        var values = String(format: "%.3f,%u,%d,",
                                          timeStamp,
                                          session.id,
                                          dataPoint.sequenceNum)
                        
                        values += "-"
                        output.append(values)
                    }
                }
            }
        }

        
        
        return output.joined(separator: "\n")
    }

    private static func engineDataToCsv(serialNumber: String,
                                        dataLogs: [DeviceDataLog],
                                        firmwareVersion: String?,
                                        hardwareRevision: String?,
                                        appVersion: String,
                                        date: Date) -> String {
        var output = [String]()

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateString = dateFormatter.string(from: date)

        output.append("Combustion Inc. Engine Data")
        output.append("App: iOS \(appVersion)")
        output.append("CSV version: 4")
        output.append("Engine S/N: \(serialNumber)")
        output.append("Engine FW version: \(firmwareVersion ?? "??")")
        output.append("Engine HW revision: \(hardwareRevision ?? "??")")
        output.append("Framework: iOS")
        output.append("Sample Period: \(dataLogs.first?.sessionInformation.samplePeriod ?? 0)")
        output.append("Created: \(dateString)")
        output.append("")

        output.append("Timestamp,SessionID,SequenceNumber,TemperatureSetPoint,ControlTemperature,FanState,DutyCycle,CommandedSpeed,MeasuredSpeed,FanOffTimeMs,FanOnTimeMs")

        if let firstSessionStart = dataLogs.first?.startTime?.timeIntervalSince1970 {
            for session in dataLogs {
                for dataPoint in session.dataPoints {
                    guard let enginePoint = dataPoint as? LoggedEngineDataPoint else { continue }

                    var timeStamp: TimeInterval = 0
                    if let currentSessionStart = session.startTime?.timeIntervalSince1970 {
                        let sessionStartTimeDiff = currentSessionStart - firstSessionStart
                        let dataPointSeconds = Double(enginePoint.sequenceNum) * Double(session.sessionInformation.samplePeriod) / 1000.0
                        timeStamp = dataPointSeconds + sessionStartTimeDiff
                    }

                    let fanStatus = enginePoint.fanStatus
                    let values = String(format: "%.3f,%u,%d,%.2f,%.2f,%d,%d,%d,%d,%u,%u",
                                        timeStamp,
                                        session.id,
                                        enginePoint.sequenceNum,
                                        enginePoint.temperatureSetPoint,
                                        enginePoint.controlTemperature,
                                        fanStatus.fanState.rawValue,
                                        fanStatus.dutyCycle,
                                        fanStatus.commandedSpeed,
                                        fanStatus.measuredSpeed,
                                        fanStatus.fanOffTime,
                                        fanStatus.fanOnTime)
                    output.append(values)
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
                                       date: Date) -> String {
        var output = [String]()
        
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
        output.append("Timestamp,SessionID,SequenceNumber,T1,T2,T3,T4,T5,T6,T7,T8,VirtualCoreTemperature,VirtualSurfaceTemperature,VirtualAmbientTemperature,EstimatedCoreTemperature,PredictionSetPoint,VirtualCoreSensor,VirtualSurfaceSensor,VirtualAmbientSensor,PredictionState,PredictionMode,PredictionType,PredictionValueSeconds")
        
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
                    
                    var values = String(format: "%.3f,%u,%d,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,",
                                      timeStamp,
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
                                     gaugeLogs: [DeviceDataLog],
                                     firmwareVersion: String?,
                                     hardwareRevision: String?,
                                     appVersion: String) -> URL? {
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
                                 date: date)
        
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
    /// - param engine: Engine for which to create the file
    /// - returns: URL of file
    public static func createEngineCSVFile(serialNumber: String,
                                           dataLogs: [DeviceDataLog],
                                           firmwareVersion: String?,
                                           hardwareRevision: String?,
                                           appVersion: String) -> URL? {
        let date = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH_mm_ss"
        let dateString = dateFormatter.string(from: date)

        let filename = "EngineData_\(serialNumber)_\(dateString).csv"

        let csv = engineDataToCsv(serialNumber: serialNumber,
                                  dataLogs: dataLogs,
                                  firmwareVersion: firmwareVersion,
                                  hardwareRevision: hardwareRevision,
                                  appVersion: appVersion,
                                  date: date)

        let filePath = NSTemporaryDirectory() + "/" + filename;

        let csvURL = URL(fileURLWithPath: filePath)

        do {
            try csv.write(to: csvURL, atomically: true, encoding: String.Encoding.utf8)
        } catch {
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
                                     appVersion: String) -> URL? {
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
                                 date: date)
        
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
