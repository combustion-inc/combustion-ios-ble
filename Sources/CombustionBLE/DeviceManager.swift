//  DeviceManager.swift

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
import SwiftUI
import NordicDFU

/// Singleton that provides list of detected Devices
/// (either via Bluetooth or from a list in the Cloud)
public class DeviceManager : ObservableObject {
    /// Singleton accessor for class
    public static let shared = DeviceManager()
    
    public enum Constants {
        static let MINIMUM_PREDICTION_SETPOINT_CELSIUS = 0.0
        static let MAXIMUM_PREDICTION_SETPOINT_CELSIUS = 102.0
    }
    
    /// Dictionary of discovered devices.
    /// key = string representation of device identifier (UUID)
    @Published public private(set) var devices : [String: Device] = [String: Device]()
    
    /// Dictionary of discovered probes (subset of devices).
    /// key = string representation of device identifier (UUID)
    private var probes : [String: Probe] {
        get {
            devices.filter { $0.value is Probe }.mapValues { $0 as! Probe }
        }
        set {
            devices = newValue
        }
    }

    // Struct to store when BLE message was send and the completion handler for message
    private struct MessageHandler {
        let timeSent: Date
        let handler: (Bool) -> Void
    }
    
    // Completion handlers for Set ID, Set Color, and Set Prediction BLE messages
    private var setIDCompetionHandlers : [String: MessageHandler] = [:]
    private var setColorCompetionHandlers : [String: MessageHandler] = [:]
    private var setPredictionCompetionHandlers : [String: MessageHandler] = [:]
    
    public func addSimulatedProbe() {
        addDevice(device: SimulatedProbe())
    }
    
    /// Private initializer to enforce singleton
    private init() {
        BleManager.shared.delegate = self
        
        // Start a timer to set stale flag on devices
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] _ in
            for key in devices.keys {
                devices[key]?.updateDeviceStale()
            }
        }
        
        // Start a timer to check for BLE message timeouts
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] _ in
            checkForMessageTimeout(messageHandlers: &setIDCompetionHandlers)
            checkForMessageTimeout(messageHandlers: &setColorCompetionHandlers)
            checkForMessageTimeout(messageHandlers: &setPredictionCompetionHandlers)
        }
    }
    
    /// Adds a device to the local list.
    /// - parameter device: Add device to list of known devices.
    private func addDevice(device: Device) {
        devices[device.identifier] = device
    }
    
    /// Removes all found devices from the list.
    func clearDevices() {
        devices.removeAll(keepingCapacity: false)
    }
    
    /// Returns list of probes
    /// - returns: List of all known probes.
    public func getProbes() -> [Probe] {
        return Array(probes.values)
    }
    
    /// Returns the nearest probe.
    /// - returns: Nearest probe, if any.
    public func getNearestProbe() -> Probe? {
        return getProbes().max{ $0.rssi < $1.rssi }
    }
    
    /// Returns list of devices.
    /// - returns: List of all known devices.
    public func getDevices() -> [Device] {
        return Array(devices.values)
    }
    
    /// Returns the nearest device.
    /// - returns: Nearest device, if any.
    public func getNearestDevice() -> Device? {
        return getDevices().max{ $0.rssi < $1.rssi }
    }
    
    func connectToDevice(_ device: Device) {
        if let _ = device as? SimulatedProbe, let uuid = UUID(uuidString: device.identifier) {
            didConnectTo(identifier: uuid)
        }
        else {
            BleManager.shared.connect(identifier: device.identifier)
        }
    }
    
    func disconnectFromDevice(_ device: Device) {
        if let _ = device as? SimulatedProbe, let uuid = UUID(uuidString: device.identifier) {
            didDisconnectFrom(identifier: uuid)
        }
        else {
            BleManager.shared.disconnect(identifier: device.identifier)
        }
    }
    
    /// Request log messages from the specified device.
    /// - parameter device: Device from which to request messages
    /// - parameter minSequence: Minimum sequence number to request
    /// - parameter maxSequence: Maximum sequence number to request
    func requestLogsFrom(_ device: Device, minSequence: UInt32, maxSequence: UInt32) {
        let request = LogRequest(minSequence: minSequence,
                                 maxSequence: maxSequence)
        BleManager.shared.sendRequest(identifier: device.identifier, request: request)
    }
    
    /// Set Probe ID on specified device.
    /// - parameter device: Device to set ID on
    /// - parameter ProbeID: New Probe ID
    /// - parameter completionHandler: Completion handler to be called operation is complete
    public func setProbeID(_ device: Device, id: ProbeID, completionHandler: @escaping (Bool) -> Void ) {
        setIDCompetionHandlers[device.identifier] = MessageHandler(timeSent: Date(), handler: completionHandler)
        
        let request = SetIDRequest(id: id)
        BleManager.shared.sendRequest(identifier: device.identifier, request: request)
    }
    
    /// Set Probe Color on specified device.
    /// - parameter device: Device to set Color on
    /// - parameter ProbeColor: New Probe color
    /// - parameter completionHandler: Completion handler to be called operation is complete
    public func setProbeColor(_ device: Device, color: ProbeColor, completionHandler: @escaping (Bool) -> Void) {
        setColorCompetionHandlers[device.identifier] = MessageHandler(timeSent: Date(), handler: completionHandler)

        let request = SetColorRequest(color: color)
        BleManager.shared.sendRequest(identifier: device.identifier, request: request)
    }
    
    /// Sends a request to the device to set/change the set point temperature for the time to
    /// removal prediction.  If a prediction is not currently active, it will be started.  If a
    /// removal prediction is currently active, then the set point will be modified.  If another
    /// type of prediction is active, then the probe will start predicting removal.
    ///
    /// - parameter device: Device to set prediction on
    /// - parameter removalTemperatureC: the target removal temperature in Celsius
    /// - parameter completionHandler: Completion handler to be called operation is complete
    public func setRemovalPrediction(_ device: Device, removalTemperatureC: Double, completionHandler: @escaping (Bool) -> Void) {
        guard removalTemperatureC < Constants.MAXIMUM_PREDICTION_SETPOINT_CELSIUS,
              removalTemperatureC > Constants.MINIMUM_PREDICTION_SETPOINT_CELSIUS else {
            completionHandler(false)
            return
        }
        
        setPredictionCompetionHandlers[device.identifier] = MessageHandler(timeSent: Date(), handler: completionHandler)

        let request = SetPredictionRequest(setPointCelsius: removalTemperatureC, mode: .timeToRemoval)
        BleManager.shared.sendRequest(identifier: device.identifier, request: request)
    }
    
    
    /// Sends a request to the device to set the prediction mode to none, stopping any active prediction.
    ///
    /// - parameter device: Device to cancel prediction on
    /// - parameter completionHandler: Completion handler to be called operation is complete
    public func cancelPrediction(_ device: Device, completionHandler: @escaping (Bool) -> Void) {
        setPredictionCompetionHandlers[device.identifier] = MessageHandler(timeSent: Date(), handler: completionHandler)
        
        let request = SetPredictionRequest(setPointCelsius: 0.0, mode: .none)
        BleManager.shared.sendRequest(identifier: device.identifier, request: request)
    }


    public func runSoftwareUpgrade(_ device: Device, otaFile: URL) -> Bool {
        do {
            let dfu = try DFUFirmware(urlToZipFile: otaFile)
            BleManager.shared.startFirmwareUpdate(device: device, dfu: dfu)
            return true
        }
        catch {
            return false
        }
    }
    
    private func checkForMessageTimeout(messageHandlers: inout [String: MessageHandler]) {
        let currentTime = Date()
        
        var keysToRemove = [String]()
        
        for key in messageHandlers.keys {
            if let messageHandler = messageHandlers[key],
               Int(currentTime.timeIntervalSince(messageHandler.timeSent)) > 3 {
                
                // More than three seconds have elapsed, therefore call handler with failure
                messageHandler.handler(false)
                
                // Save key to remove
                keysToRemove.append(key)
            }
        }
        
        // Remove keys that timed out
        for key in keysToRemove {
            messageHandlers.removeValue(forKey: key)
        }
    }
}

extension DeviceManager : BleManagerDelegate {
    func didConnectTo(identifier: UUID) {
        guard let _ = devices[identifier.uuidString] else { return }
        devices[identifier.uuidString]?.updateConnectionState(.connected)
    }
    
    func didFailToConnectTo(identifier: UUID) {
        guard let _ = devices[identifier.uuidString] else { return }
        devices[identifier.uuidString]?.updateConnectionState(.failed)
    }
    
    func didDisconnectFrom(identifier: UUID) {
        guard let _ = devices[identifier.uuidString] else { return }
        devices[identifier.uuidString]?.updateConnectionState(.disconnected)
        
        // Clear any pending completion handlers
        setColorCompetionHandlers.removeValue(forKey: identifier.uuidString)
        setIDCompetionHandlers.removeValue(forKey: identifier.uuidString)
    }
    
    func updateDeviceWithStatus(identifier: UUID, status: ProbeStatus) {
        if let probe = devices[identifier.uuidString] as? Probe {
            probe.updateProbeStatus(deviceStatus: status)
        }
    }
    
    func updateDeviceWithAdvertising(advertising: AdvertisingData, isConnectable: Bool, rssi: NSNumber, identifier: UUID) {
        if devices[identifier.uuidString] != nil {
            if let probe = devices[identifier.uuidString] as? Probe {
                probe.updateWithAdvertising(advertising, isConnectable: isConnectable, RSSI: rssi)
            }
        }
        else {
            let device = Probe(advertising, isConnectable: isConnectable, RSSI: rssi, identifier: identifier)
            addDevice(device: device)
        }
    }
    
    func updateDeviceFwVersion(identifier: UUID, fwVersion: String) {
        if let device = devices[identifier.uuidString]  {
            device.firmareVersion = fwVersion
            
            // TODO : remove this at some point
            // Prior to v0.8.0, the firmware did not support the Session ID command
            // Therefore, add a hardcoded session for backwards compatibility
            if(Version.isBefore(deviceFirmware: fwVersion, comparison: "v0.8.0")) {
                let fakeSessionInfo = SessionInformation(sessionID: 0, samplePeriod: 1000)
                updateDeviceWithSessionInformation(identifier: identifier, sessionInformation: fakeSessionInfo)
            }
        }
    }
    
    func updateDeviceHwRevision(identifier: UUID, hwRevision: String) {
        if let device = devices[identifier.uuidString]  {
            device.hardwareRevision = hwRevision
        }
    }
    
    func handleUARTResponse(identifier: UUID, response: Response) {
        if let logResponse = response as? LogResponse {
            updateDeviceWithLogResponse(identifier: identifier, logResponse: logResponse)
        }
        else if let setIDResponse = response as? SetIDResponse {
            handleSetIDResponse(identifier: identifier, success: setIDResponse.success)
        }
        else if let setColorResponse = response as? SetColorResponse {
            handleSetColorResponse(identifier: identifier, success: setColorResponse.success)
        }
        else if let sessionResponse = response as? SessionInfoResponse {
            if(sessionResponse.success) {
                updateDeviceWithSessionInformation(identifier: identifier, sessionInformation: sessionResponse.info)
            }
        }
        else if let setPredictionResponse = response as? SetPredictionResponse {
            handleSetPredictionRespone(identifier: identifier, success: setPredictionResponse.success)
        }
    }
    
    private func updateDeviceWithLogResponse(identifier: UUID, logResponse: LogResponse) {
        guard logResponse.success else { return }
        
        if let probe = devices[identifier.uuidString] as? Probe {
            probe.processLogResponse(logResponse: logResponse)
        }
    }
    
    private func updateDeviceWithSessionInformation(identifier: UUID, sessionInformation: SessionInformation) {
        if let probe = devices[identifier.uuidString] as? Probe {
            probe.updateWithSessionInformation(sessionInformation)
        }
    }
    
    private func handleSetIDResponse(identifier: UUID, success: Bool) {
        setIDCompetionHandlers[identifier.uuidString]?.handler(success)
        
        setIDCompetionHandlers.removeValue(forKey: identifier.uuidString)
    }
    
    private func handleSetColorResponse(identifier: UUID, success: Bool) {
        setColorCompetionHandlers[identifier.uuidString]?.handler(success)
        
        setColorCompetionHandlers.removeValue(forKey: identifier.uuidString)
    }
    
    private func handleSetPredictionRespone(identifier: UUID, success: Bool) {
        setPredictionCompetionHandlers[identifier.uuidString]?.handler(success)
        
        setPredictionCompetionHandlers.removeValue(forKey: identifier.uuidString)
    }
}
