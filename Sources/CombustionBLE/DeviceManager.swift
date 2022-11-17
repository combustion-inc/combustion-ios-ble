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

    // Struct to store when BLE message was send and the completion handler for message
    private struct MessageHandler {
        let timeSent: Date
        let handler: (Bool) -> Void
    }
    
    private let messageHandlers = MessageHandlers()
    
    public func addSimulatedProbe() {
        addDevice(device: SimulatedProbe())
    }
    
    public func initBluetooth() {
        BleManager.shared.initBluetooth()
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
            messageHandlers.checkForTimeout()
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
        return Array(devices.values).compactMap { device in
            return device as? Probe
        }
    }
    
    /// Returns list of displays
    /// - returns: List of all kitchen timers
    public func getDisplays() -> [Display] {
        return Array(devices.values).compactMap { device in
            return device as? Display
        }
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
    public func setProbeID(_ device: Device, id: ProbeID, completionHandler: @escaping MessageHandlers.SuccessCompletionHandler) {
        // Store completion handler
        messageHandlers.addSetIDCompletionHandler(device, completionHandler: completionHandler)
        
        // Send request to device
        let request = SetIDRequest(id: id)
        BleManager.shared.sendRequest(identifier: device.identifier, request: request)
    }
    
    /// Set Probe Color on specified device.
    /// - parameter device: Device to set Color on
    /// - parameter ProbeColor: New Probe color
    /// - parameter completionHandler: Completion handler to be called operation is complete
    public func setProbeColor(_ device: Device,
                              color: ProbeColor,
                              completionHandler: @escaping MessageHandlers.SuccessCompletionHandler) {
        // Store completion handler
        messageHandlers.addSetColorCompletionHandler(device, completionHandler: completionHandler)

        // Send request to device
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
    public func setRemovalPrediction(_ device: Device,
                                     removalTemperatureC: Double,
                                     completionHandler: @escaping MessageHandlers.SuccessCompletionHandler) {
        guard removalTemperatureC < Constants.MAXIMUM_PREDICTION_SETPOINT_CELSIUS,
              removalTemperatureC > Constants.MINIMUM_PREDICTION_SETPOINT_CELSIUS else {
            completionHandler(false)
            return
        }
        
        // Store completion handler
        messageHandlers.addSetPredictionCompletionHandler(device, completionHandler: completionHandler)

        // Send request to device
        let request = SetPredictionRequest(setPointCelsius: removalTemperatureC, mode: .timeToRemoval)
        BleManager.shared.sendRequest(identifier: device.identifier, request: request)
    }
    
    
    /// Sends a request to the device to set the prediction mode to none, stopping any active prediction.
    ///
    /// - parameter device: Device to cancel prediction on
    /// - parameter completionHandler: Completion handler to be called operation is complete
    public func cancelPrediction(_ device: Device, completionHandler: @escaping MessageHandlers.SuccessCompletionHandler) {
        // Store completion handler
        messageHandlers.addSetPredictionCompletionHandler(device, completionHandler: completionHandler)
        
        // Send request to device
        let request = SetPredictionRequest(setPointCelsius: 0.0, mode: .none)
        BleManager.shared.sendRequest(identifier: device.identifier, request: request)
    }
    
    /// Sends a request to the device to read Over Temperature flag
    ///
    /// - parameter device: Device to read flag from
    /// - parameter completionHandler: Completion handler to be called operation is complete
    public func readOverTemperatureFlag(_ device: Device,
                                        completionHandler: @escaping MessageHandlers.ReadOverTemperatureCompletionHandler) {
        // Store completion handler
        messageHandlers.addReadOverTemperatureCompletionHandler(device, completionHandler: completionHandler)
        
        // Send request to device
        let request = ReadOverTemperatureRequest()
        BleManager.shared.sendRequest(identifier: device.identifier, request: request)
    }
    
    /// Set the DFU file to be used on displays with failed software upgrade.
    /// A failed upgrade will occur if the user kills the application in the middle of
    /// the software upgrade process.  After this method is called, DFU will be initiated
    /// when a device with failed software upgrade is detected.
    ///
    /// - displayDFUFile: Display device DFU file
    public func restartFailedUpgradesWith(displayDFUFile: URL) {
        DFUManager.shared.setDisplayDFU(displayDFUFile: displayDFUFile)
    }
}

extension DeviceManager : BleManagerDelegate {
    func didConnectTo(identifier: UUID) {
        guard let device = devices[identifier.uuidString] else { return }
        
        device.updateConnectionState(.connected)
    }
    
    func didFailToConnectTo(identifier: UUID) {
        guard let device = devices[identifier.uuidString] else { return }
        
        device.updateConnectionState(.failed)
    }
    
    func didDisconnectFrom(identifier: UUID) {
        guard let device = devices[identifier.uuidString] else { return }
        
        device.updateConnectionState(.disconnected)
        
        // Clear any pending message handlers
        messageHandlers.clearHandlersForDevice(identifier)
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
            else if let timer = devices[identifier.uuidString] as? Display {
                // Automatically connect to kitchen timer
                if(timer.connectionState == .disconnected) {
                    timer.connect()
                }
            }
        }
        else {
            switch(advertising.type) {
            case .probe:
                let device = Probe(advertising, isConnectable: isConnectable, RSSI: rssi, identifier: identifier)
                addDevice(device: device)
                
            case .display:
                let device = Display(identifier: identifier, RSSI: rssi)
                addDevice(device: device)
                
            case .unknown:
                print("Found device with unknown type")
            }


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
    
    func updateDeviceSerialNumber(identifier: UUID, serialNumber: String) {
        if let timer = devices[identifier.uuidString] as? Display {
            timer.serialNumberString = serialNumber
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
            messageHandlers.callSetIDCompletionHandler(identifier, response: setIDResponse)
        }
        else if let setColorResponse = response as? SetColorResponse {
            messageHandlers.callSetColorCompletionHandler(identifier, response: setColorResponse)
        }
        else if let sessionResponse = response as? SessionInfoResponse {
            if(sessionResponse.success) {
                updateDeviceWithSessionInformation(identifier: identifier, sessionInformation: sessionResponse.info)
            }
        }
        else if let setPredictionResponse = response as? SetPredictionResponse {
            messageHandlers.callSetPredictionCompletionHandler(identifier, response: setPredictionResponse)
        }
        else if let readOverTemperatureResponse = response as? ReadOverTemperatureResponse {
            messageHandlers.callReadOverTemperatureCompletionHandler(identifier, response: readOverTemperatureResponse)
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
}
