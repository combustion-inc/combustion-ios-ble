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
import CoreBluetooth
import Combine

// Device Manager protocol to support unit testing
public protocol DeviceManagerProtocol {
    func cancelPrediction(_ probe: Probe,
                          completionHandler: @escaping MessageHandlers.SuccessCompletionHandler)
    
    func setRemovalPrediction(_ probe: Probe,
                              removalTemperatureC: Double,
                              completionHandler: @escaping MessageHandlers.SuccessCompletionHandler)
}

public protocol DeviceResponseHandlerProtocol: AnyObject {
    func handleResponse(identifier: UUID, response: NodeResponse)
    func handleRequest(identifier: UUID, request: NodeRequest)
}

/// Singleton that provides list of detected Devices
/// (either via Bluetooth or from a list in the Cloud)
open class DeviceManager : DeviceManagerProtocol, ObservableObject {
    
    /// Singleton accessor for class
    public static let shared = DeviceManager()
    
    public enum Constants {
        public static let MINIMUM_PREDICTION_SETPOINT_CELSIUS = 0.0
        public static let MAXIMUM_PREDICTION_SETPOINT_CELSIUS = 100.0
        
        /// Serial Number value indicating 'No Probe'
        static let INVALID_PROBE_SERIAL_NUMBER = 0
    }
    
    /// Dictionary of discovered devices.
    /// key = string representation of device identifier (UUID)
    @Published public private(set) var devices : [String: Device] = [:]
    
    @Published public private(set) var accessories: [String: any Accessory] = [:]
    
    // Bluetooth manager state
    @Published public private(set) var bluetoothState: CBManagerState = .unknown
    
    /// Flag that tracks if any DFUs are currently in progress
    @Published public private(set) var dfuIsInProgress = false

    // Struct to store when BLE message was send and the completion handler for message
    private struct MessageHandler {
        let timeSent: Date
        let handler: (Bool) -> Void
    }
    
    private var dfuManager = DFUManager.shared
    
    private var cancellables: Set<AnyCancellable> = []
    
    /// Handler for messages from Probe
    private let messageHandlers = MessageHandlers()
    
    /// Connection manager to handle BLE connection logic
    private let connectionManager = ConnectionManager()
    
    public weak var deviceResponseHandler: DeviceResponseHandlerProtocol?
    
    public func addSimulatedProbe() {
        addDevice(device: SimulatedProbe())
    }
    
    public func addSimulatedGauge() {
        addDevice(device: SimulatedGauge())
    }
    
    public func initBluetooth() {
        BleManager.shared.initBluetooth()
    }
    
    /// Enables MeatNet repeater network.
    public func enableMeatNet() {
        connectionManager.meatNetEnabled = true
    }
    
    /// Enables DFU mode
    public func enableDFUMode(_ enable: Bool) {
        connectionManager.dfuModeEnabled = enable
    }
    
    /// Sets the allow list for thermometers.  Framework will only connect to thermometers
    /// in the allow list and nodes that are advertising data from thermometer in whitelist.
    /// - param allowList: Allow list of probes serial numbers
    /// /// Deprecated. Legacy value - raw, unfiltered instant read reading.
    @available(*, deprecated)
    public func setThermometerAllowList(_ allowList: Set<String>) {
        connectionManager.setDeviceAllowList(allowList)
    }
    
    public func setDeviceAllowList(_ allowList: Set<String>) {
        connectionManager.setDeviceAllowList(allowList)
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
        
        // Observe flag on DFU manager
        dfuManager.$dfuIsInProgress
            .sink { dfuIsInProgress in
                self.dfuIsInProgress = dfuIsInProgress
            }
            .store(in: &cancellables)
    }
    
    /// Adds a device to the local list.
    /// - parameter device: Add device to list of known devices.
    private func addDevice(device: Device) {
        devices[device.uniqueIdentifier] = device
    }
    
    /// Removes device from the list.
    func clearDevice(device: Device) {
        devices.removeValue(forKey: device.uniqueIdentifier)
        
        if let device = device as? MeatNetNode, let accessory = device.accessory {
            clearAccessory(accessory: accessory)
        }
    }
    
    /// Adds a accessory to the local list.
    /// - parameter accessory: Add accessory to list of known accessory.
    private func addAccessory(accessory: any Accessory) {
        accessories[accessory.serialNumberString] = accessory
    }
    
    /// Removes accessory from the list.
    func clearAccessory(accessory: any Accessory) {
        devices.removeValue(forKey: accessory.serialNumberString)
    }
    
    /// Returns list of probes
    /// - returns: List of all known probes.
    public func getProbes() -> [Probe] {
        return Array(devices.values).compactMap { device in
            return device as? Probe
        }
    }
    
    /// Returns list of gauges
    /// - returns: List of all known gauges.
    public func getGauges() -> [GrillGauge] {
        return Array(devices.values).compactMap { device in
            return device as? GrillGauge
        }
    }
    
    /// Returns list of MeatNet nodes
    /// - returns: List of all MeatNet nodes
    public func getMeatnetNodes() -> [MeatNetNode] {
        if connectionManager.meatNetEnabled {
            return Array(devices.values).compactMap { device in
                return device as? MeatNetNode
            }
        } else {
            return []
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
    
    /// Checks if specified probe is connected to any connected meatnet node
    func isDeviceConnectedToMeatnet(_ device: Device) -> Bool {
        let nodesConnectedToDevice = getNodesConnectedToDevice(identifier: device.uniqueIdentifier)
        
        return !nodesConnectedToDevice.isEmpty
    }
    
    private func getNodesConnectedToDevice(identifier: String) -> [MeatNetNode] {
        var nodesWithDevice: [MeatNetNode] = []
        
        let meatnetNodes = getMeatnetNodes()
        
        for node in meatnetNodes {
            // Check Nodes to which we are connected to see if they have a route to the Device
            if node.connectionState == .connected, node.hasConnectionToDevice(identifier) {
                nodesWithDevice.append(node)
            }
        }
        
        return nodesWithDevice
    }
    
    private func shouldSendMessageDirectlyTo(probe: Probe) -> Bool {
        return probe.connectionState == .connected
    }
    
    private func shouldSendMessageDirectlyTo(device: MeatNetNode) -> Bool {
        return device.connectionState == .connected
    }
    
    func connectToDevice(_ device: Device) {
        if let _ = device as? SimulatedProbe, let bleIdentifier = device.bleIdentifier, let uuid = UUID(uuidString: bleIdentifier) {
            // If this device is a Simulated Probe, use a simulated connection.
            didConnectTo(identifier: uuid)
        }
        else if let bleIdentifier = device.bleIdentifier {
            // If this device has a BLE identifier (advertisements are directly detected rather than through MeatNet),
            // attempt to connect to it.
            BleManager.shared.connect(identifier: bleIdentifier)
        }
    }
    
    func disconnectFromDevice(_ device: Device) {
        if let _ = device as? SimulatedProbe, let bleIdentifier = device.bleIdentifier, let uuid = UUID(uuidString: bleIdentifier) {
            // If this device is a Simulated Probe, use a simulated disconnect.
            didDisconnectFrom(identifier: uuid)
        }
        else if let bleIdentifier = device.bleIdentifier {
            // If this device has a BLE identifier (advertisements are directly detected rather than through MeatNet),
            // attempt to disconnect from it.
            BleManager.shared.disconnect(identifier: bleIdentifier)
        }
    }
    
    /// Request log messages from the specified device.
    /// - parameter device: Device from which to request messages
    /// - parameter minSequence: Minimum sequence number to request
    /// - parameter maxSequence: Maximum sequence number to request
    func requestLogsFrom(_ device: MeatNetNode, minSequence: UInt32, maxSequence: UInt32) {
        guard let accessory = device.accessory else { return }
        
        if shouldSendMessageDirectlyTo(device: device) {
            // Request logs directly from Device.
            guard let request = NodeGaugeReadLogsRequest(serialNumber: accessory.serialNumberString,
                                          minSequence: minSequence,
                                                    maxSequence: maxSequence) else {
                return
            }
            
            BleManager.shared.sendRequest(identifier: device.bleIdentifier, request: request)
        }
        else {
            // Send message to all nodes that have a route to the device
            let nodesConnectedToDevice = getNodesConnectedToDevice(identifier: accessory.serialNumberString)
            guard let request = NodeGaugeReadLogsRequest(serialNumber: accessory.serialNumberString,
                                              minSequence: minSequence,
                                                         maxSequence: maxSequence) else { return }
            BleManager.shared.sendRequestToNodes(nodesConnectedToDevice, request: request)
        }
    }
    
    /// Request log messages from the specified device.
    /// - parameter device: Device from which to request messages
    /// - parameter minSequence: Minimum sequence number to request
    /// - parameter maxSequence: Maximum sequence number to request
    func requestLogsFrom(_ probe: Probe, minSequence: UInt32, maxSequence: UInt32) {
        if shouldSendMessageDirectlyTo(probe: probe) {
            // Request logs directly from Probe.
            let request = LogRequest(minSequence: minSequence,
                                     maxSequence: maxSequence)
            
            BleManager.shared.sendRequest(identifier: probe.bleIdentifier, request: request)
            
        }
        else {
            // Send message to all nodes that have a route to the probe
            let nodesConnectedToProbe = getNodesConnectedToDevice(identifier: probe.uniqueIdentifier)
            let request = NodeReadLogsRequest(serialNumber: probe.serialNumber,
                                              minSequence: minSequence,
                                              maxSequence: maxSequence)
            BleManager.shared.sendRequestToNodes(nodesConnectedToProbe, request: request)
        }
    }
    
    /// Set Probe ID on specified device.
    /// - parameter device: Device to set ID on
    /// - parameter ProbeID: New Probe ID
    /// - parameter completionHandler: Completion handler to be called operation is complete
    public func setProbeID(_ device: Device, id: ProbeID, completionHandler: @escaping MessageHandlers.SuccessCompletionHandler) {
        // TODO - Send request via Node.
        
        let request = SetIDRequest(id: id)
        
        // Store completion handler
        messageHandlers.addSuccessCompletionHandler(device, request: request, completionHandler: completionHandler)
        
        // Send request to device
        if let device = device as? Probe, let bleIdentifier = device.bleIdentifier {
            BleManager.shared.sendRequest(identifier: bleIdentifier, request: request)
        }
    }
    
    /// Set Probe Color on specified device.
    /// - parameter device: Device to set Color on
    /// - parameter ProbeColor: New Probe color
    /// - parameter completionHandler: Completion handler to be called operation is complete
    public func setProbeColor(_ device: Device,
                              color: ProbeColor,
                              completionHandler: @escaping MessageHandlers.SuccessCompletionHandler) {
        // TODO - Send request via Node.
        
        let request = SetColorRequest(color: color)
        
        // Store completion handler
        messageHandlers.addSuccessCompletionHandler(device, request: request, completionHandler: completionHandler)

        // Send request to device
        if let device = device as? Probe, let bleIdentifier = device.bleIdentifier {
            BleManager.shared.sendRequest(identifier: bleIdentifier, request: request)
        }
    }
    
    /// Set probe power mode on a specified node
    /// - parameter probe: Probe to set the power mode on
    /// - parameter powerMode: new power mode
    /// - parameter completionHandler: Completion handler to be called once operation is complete
    public func setProbePowerMode(_ probe: Probe, powerMode: ProbePowerMode, completionHandler: @escaping MessageHandlers.SuccessCompletionHandler) {
        if shouldSendMessageDirectlyTo(probe: probe) {
            let request = SetPowerModeRequest(mode: powerMode)
            sendDirectRequestWithSuccessHandler(probe, request: request, completionHandler: completionHandler)
        }
        else {
            let request = NodeSetPowerModeRequest(serialNumber: probe.serialNumber, mode: powerMode)
            sendNodeRequestWithSuccessHandler(probe, request: request, completionHandler: completionHandler)
        }
    }
    
    /// Sends a request to the device to set/change the set point temperature for the time to
    /// removal prediction.  If a prediction is not currently active, it will be started.  If a
    /// removal prediction is currently active, then the set point will be modified.  If another
    /// type of prediction is active, then the probe will start predicting removal.
    ///
    /// - parameter probe: Probe to set prediction on
    /// - parameter removalTemperatureC: the target removal temperature in Celsius
    /// - parameter completionHandler: Completion handler to be called operation is complete
    public func setRemovalPrediction(_ probe: Probe,
                                     removalTemperatureC: Double,
                                     completionHandler: @escaping MessageHandlers.SuccessCompletionHandler) {
        guard removalTemperatureC < Constants.MAXIMUM_PREDICTION_SETPOINT_CELSIUS,
              removalTemperatureC > Constants.MINIMUM_PREDICTION_SETPOINT_CELSIUS else {
            completionHandler(false)
            return
        }
        
        if shouldSendMessageDirectlyTo(probe: probe) {
            // If the best route is directly to the Probe, send it that way.
            let request = SetPredictionRequest(setPointCelsius: removalTemperatureC, mode: .timeToRemoval)
            sendDirectRequestWithSuccessHandler(probe, request: request, completionHandler: completionHandler)
        }
        else {
            // Send message to all nodes that have a route to the probe
            let request = NodeSetPredictionRequest(serialNumber: probe.serialNumber,
                                                   setPointCelsius: removalTemperatureC,
                                                   mode: .timeToRemoval)
            sendNodeRequestWithSuccessHandler(probe, request: request, completionHandler: completionHandler)
        }
    }
    
    
    /// Sends a request to the device to set the prediction mode to none, stopping any active prediction.
    ///
    /// - parameter probe: Probe to cancel prediction on
    /// - parameter completionHandler: Completion handler to be called operation is complete
    public func cancelPrediction(_ probe: Probe, completionHandler: @escaping MessageHandlers.SuccessCompletionHandler) {
        
        if shouldSendMessageDirectlyTo(probe: probe) {
            // If the best route is directly to the Probe, send it that way.
            let request = SetPredictionRequest(setPointCelsius: 0.0, mode: .none)
            sendDirectRequestWithSuccessHandler(probe, request: request, completionHandler: completionHandler)
        }
        else {
            // Send message to all nodes that have a route to the probe
            let request = NodeSetPredictionRequest(serialNumber: probe.serialNumber,
                                                   setPointCelsius: 0.0,
                                                   mode: .none)
            sendNodeRequestWithSuccessHandler(probe, request: request, completionHandler: completionHandler)
        }
    }
    
    /// Sends a request to the device to configure Food Safe
    ///
    /// - parameter probe: Probe to cancel prediction on
    /// - parameter foodSafeData: Food Safe data
    /// - parameter completionHandler: Completion handler to be called operation is complete
    public func configureFoodSafe(_ probe: Probe,
                            foodSafeData: FoodSafeData,
                            completionHandler: @escaping MessageHandlers.SuccessCompletionHandler) {
        
        if shouldSendMessageDirectlyTo(probe: probe) {
            // If the best route is directly to the Probe, send it that way.
            let request = ConfigureFoodSafeRequest(foodSafeData: foodSafeData)
            sendDirectRequestWithSuccessHandler(probe, request: request, completionHandler: completionHandler)
        }
        else {
            // Send message to all nodes that have a route to the probe
            let request = NodeConfigureFoodSafeRequest(serialNumber: probe.serialNumber,
                                                       foodSafeData: foodSafeData)
            sendNodeRequestWithSuccessHandler(probe, request: request, completionHandler: completionHandler)
        }
    }
    
    /// Sends a request to the device to reset Food Safe
    ///
    /// - parameter probe: Probe to cancel prediction on
    /// - parameter completionHandler: Completion handler to be called operation is complete
    public func resetFoodSafe(_ probe: Probe,
                            completionHandler: @escaping MessageHandlers.SuccessCompletionHandler) {
        
        if shouldSendMessageDirectlyTo(probe: probe) {
            // If the best route is directly to the Probe, send it that way.
            let request = ResetFoodSafeRequest()
            sendDirectRequestWithSuccessHandler(probe, request: request, completionHandler: completionHandler)
        }
        else {
            // Send message to all nodes that have a route to the probe
            let request = NodeResetFoodSafeRequest(serialNumber: probe.serialNumber)
            sendNodeRequestWithSuccessHandler(probe, request: request, completionHandler: completionHandler)
        }
    }
    
    /// Reads the feature flags from a meat net node device
    ///
    /// - parameter device: meat net node device to read flags from
    public func readFeatureFlags(device: MeatNetNode) {
        if let serialNumber = device.serialNumberString {
            let request = NodeReadFeatureFlagsRequest(serialNumber: serialNumber)
            BleManager.shared.sendRequestToNodes([device], request: request)
        }
        else if let bleIdentifier = device.bleIdentifier {
            BleManager.shared.readSerialNumber(identifier: bleIdentifier)
        }
    }
    
    /// Sends a request to the probe to read the session information.
    ///
    /// - parameter device: Device to read session info
    /// - parameter completionHandler: Completion handler to be called operation is complete
    public func readSessionInfo(probe: Probe) {
        
        if shouldSendMessageDirectlyTo(probe: probe) {
            // If the best route is directly to the Probe, send it that way.
            let request = SessionInfoRequest()
            BleManager.shared.sendRequest(identifier: probe.bleIdentifier, request: request)
        }
        else {
            // Send message to all nodes that have a route to the probe
            let nodesConnectedToProbe = getNodesConnectedToDevice(identifier: probe.uniqueIdentifier)
            
            // Send request to device
            let request = NodeReadSessionInfoRequest(serialNumber: probe.serialNumber)
            BleManager.shared.sendRequestToNodes(nodesConnectedToProbe, request: request)
        }
    }
    
    /// Sends request to the device to read the probe firmware version.
    ///
    /// - parameter probe: Probe for which to read firmware version
    public func readFirmwareVersion(probe: Probe) {
        if shouldSendMessageDirectlyTo(probe: probe) {
            // If the best route is directly to the Probe, send it that way.
            BleManager.shared.readFirmwareRevision(identifier: probe.bleIdentifier)
        }
        else {
            // Send message to all nodes that have a route to the probe
            let nodesConnectedToProbe = getNodesConnectedToDevice(identifier: probe.uniqueIdentifier)
            
            let request = NodeReadFirmwareRevisionRequest(serialNumber: probe.serialNumber)
            BleManager.shared.sendRequestToNodes(nodesConnectedToProbe, request: request)
        }
    }
    
    /// Sends request to the device to read the probe hardware version.
    ///
    /// - parameter probe: Probe for which to read hardware version
    public func readHardwareVersion(probe: Probe) {
        if shouldSendMessageDirectlyTo(probe: probe) {
            // If the best route is directly to the Probe, send it that way.
            BleManager.shared.readHardwareRevision(identifier: probe.bleIdentifier)
        }
        else {
            // Send message to all nodes that have a route to the probe
            let nodesConnectedToProbe = getNodesConnectedToDevice(identifier: probe.uniqueIdentifier)
            
            let request = NodeReadHardwareRevisionRequest(serialNumber: probe.serialNumber)
            BleManager.shared.sendRequestToNodes(nodesConnectedToProbe, request: request)
        }
    }
    
    /// Sends request to read the probe model info.
    ///
    /// - parameter probe: Probe for which to read model info.
    public func readModelInfoForProbe(_ probe: Probe) {
        if shouldSendMessageDirectlyTo(probe: probe) {
            // If the best route is directly to the Probe, send it that way.
            BleManager.shared.readModelNumber(identifier: probe.bleIdentifier)
        }
        else {
            // Send message to all nodes that have a route to the probe
            let nodesConnectedToProbe = getNodesConnectedToDevice(identifier: probe.uniqueIdentifier)
            
            let request = NodeReadModelInfoRequest(serialNumber: probe.serialNumber)
            BleManager.shared.sendRequestToNodes(nodesConnectedToProbe, request: request)
        }
    }
    
    /// Sends request to read the MeatNetNode model info.
    ///
    /// - parameter node: MeatNetNode for which to read model info.
    public func readModelInfoForNode(_ node: MeatNetNode) {
        BleManager.shared.readModelNumber(identifier: node.uniqueIdentifier)
    }
    
    /// Sends a request to the device to read Over Temperature flag
    ///
    /// - parameter device: Device to read flag from
    /// - parameter completionHandler: Completion handler to be called operation is complete
    public func readOverTemperatureFlag(_ device: Device,
                                        completionHandler: @escaping MessageHandlers.ReadOverTemperatureCompletionHandler) {
        // TODO - Send request via Node.
        
        let request = ReadOverTemperatureRequest()
        
        if let device = device as? Probe, let bleIdentifier = device.bleIdentifier {
            // Store completion handler
            messageHandlers.addReadOverTemperatureCompletionHandler(device, request: request, completionHandler: completionHandler)
            
            // Send request to device
            BleManager.shared.sendRequest(identifier: bleIdentifier, request: request)
        }
    }
    
    /// Sends a request to reset the current session for a probe
    ///  - Parameter probe: The probe to reset
    ///  - parameter completionHandler: Completion handler to be called operation is complete
    public func resetSession(_ probe: Probe, completionHandler: @escaping MessageHandlers.SuccessCompletionHandler) {
        if shouldSendMessageDirectlyTo(probe: probe) {
            let request = ResetSessionRequest()
            sendDirectRequestWithSuccessHandler(probe, request: request, completionHandler: completionHandler)
        }
        else {
            let request = NodeResetSessionRequest(serialNumber: probe.serialNumber)
            sendNodeRequestWithSuccessHandler(probe, request: request, completionHandler: completionHandler)
        }
    }
    
    /// Sends a request to set high low alarms for a device
    ///
    /// - parameter device: the device to update with high low alarms
    public func setHighLowAlarms(_ device: MeatNetNode,
                                 status: HighLowAlarmStatus,
                                 completionHandler: @escaping MessageHandlers.SuccessCompletionHandler) {
        // cannot send request if no serial number present
        guard let serialNumberString = device.accessory?.serialNumberString,
              let request = SetNodeHighLowAlarmRequest(serialNumber: serialNumberString, status: status) else {
            completionHandler(false)
            return
        }
       
        sendNodeRequestWithSuccessHandler(device, request: request, completionHandler: completionHandler)
    }
    
    /// Set the DFU file to be used on devices with failed software upgrade.
    /// A failed upgrade will occur if the user kills the application in the middle of
    /// the software upgrade process.  After this method is called, DFU will be initiated
    /// when a device with failed software upgrade is detected.
    ///
    /// - dfuFiles: DFU files for each DFU type
    public func restartFailedUpgradesWith(dfuFiles: [ProductType: URL]) {
        for (type, dfuFile) in dfuFiles {
            dfuManager.setDefaultDFUForType(dfuFile: dfuFile, dfuType: type)
        }
    }
    
    /// Set the analtics logger
    ///  - Parameter logger: Analtyics logger to be used
    public func setAnalyticsLogger(_ logger: AnalyticsLogger) {
        dfuManager.setAnalyticsLogger(logger)
    }
    
    private func sendDirectRequestWithSuccessHandler(_ probe: Probe,
                                   request: Request,
                                   completionHandler: @escaping MessageHandlers.SuccessCompletionHandler) {
        // Store completion handler
        messageHandlers.addSuccessCompletionHandler(probe, request: request, completionHandler: completionHandler)
        
        // Send request to device
        BleManager.shared.sendRequest(identifier: probe.bleIdentifier, request: request)
    }
    
    private func sendNodeRequestWithSuccessHandler(_ probe: Probe,
                                   request: NodeRequest,
                                   completionHandler: @escaping MessageHandlers.SuccessCompletionHandler) {
        // Send message to all nodes that have a route to the probe
        let nodesConnectedToProbe = getNodesConnectedToDevice(identifier: probe.uniqueIdentifier)
        
        // Store completion handler
        messageHandlers.addNodeSuccessCompletionHandler(request: request, completionHandler: completionHandler)
        
        print("DEVIN: sending \(nodesConnectedToProbe.count)")
        
        // Send request to device
        BleManager.shared.sendRequestToNodes(nodesConnectedToProbe, request: request)
    }
    
    public func sendNodeRequest(node: MeatNetNode,
                                           request: NodeRequest) {
        BleManager.shared.sendRequestToNodes([node], request: request)
    }
    
    private func sendNodeRequestWithSuccessHandler(_ device: MeatNetNode,
                                   request: NodeRequest,
                                   completionHandler: @escaping MessageHandlers.SuccessCompletionHandler) {
        messageHandlers.addNodeSuccessCompletionHandler(request: request, completionHandler: completionHandler)
        
        if shouldSendMessageDirectlyTo(device: device) {
            // Send request to device
            BleManager.shared.sendRequestToNodes([device], request: request)
        }
        else {
            // Send message to all nodes that have a route to the device
            let nodesConnectedToDevice = getNodesConnectedToDevice(identifier: device.uniqueIdentifier)
            BleManager.shared.sendRequestToNodes(nodesConnectedToDevice, request: request)
        }
    }
}

extension DeviceManager : BleManagerDelegate {
    func updateBluetoothState(state: CBManagerState) {
        bluetoothState = state
        
        // Set all devices to `disconnected` if bluetooth manager
        // is not powered on
        if state != .poweredOn {
            for device in devices.values {
                device.updateConnectionState(.disconnected)
            }
        }

    }
    
    func didConnectTo(identifier: UUID) {
        guard let device = findDeviceByBleIdentifier(bleIdentifier: identifier) else { return }
        
        device.updateConnectionState(.connected)
    }
    
    func didFailToConnectTo(identifier: UUID) {
        guard let device = findDeviceByBleIdentifier(bleIdentifier: identifier) else { return }
        
        device.updateConnectionState(.failed)
    }
    
    func didDisconnectFrom(identifier: UUID) {
        guard let device = findDeviceByBleIdentifier(bleIdentifier: identifier) else { return }
        
        device.updateConnectionState(.disconnected)
        
        // Clear any pending message handlers
        messageHandlers.clearHandlersForDevice(identifier)
    }
    
    func didCompleteDiscovery(identifier: UUID, maximumWriteValueLength: Int) {
        if let device = findDeviceWithBootloaderIdentifier(identifier) {
            // Save max write length value
            device.setMaximumWriteValueLength(maximumWriteValueLength)
            
            // Enable notifications on Bootloader DFU characteristic
            BleManager.shared.enableNotificationsFor(identifier.uuidString, type: .dfuControlPoint)
        }
        else {
            // Enable notifications on DFU characteristic
            BleManager.shared.enableNotificationsFor(identifier.uuidString, type: .dfu)
        }
    }
    
    func didEnableNotificationsFor(identifier: UUID, characteristic: BleCharacteristic) {
        if let device = findDeviceWithBootloaderIdentifier(identifier) {
            if(characteristic == BleCharacteristic.dfuControlPoint) {
                dfuManager.bootloaderDiscoveryComplete(device)
            }
        }
        else if let device = findDeviceByBleIdentifier(bleIdentifier: identifier) {
            if device is Probe {
                if(characteristic == BleCharacteristic.dfu) {
                    BleManager.shared.enableNotificationsFor(identifier.uuidString, type: .uartTx)
                }
                else if(characteristic == BleCharacteristic.uartTx) {
                    BleManager.shared.enableNotificationsFor(identifier.uuidString, type: .deviceStatus)
                }
                else if(characteristic == BleCharacteristic.deviceStatus)  {
                    BleManager.shared.sendRequest(identifier: identifier.uuidString, request: SessionInfoRequest())
                }
            }
            else if device is MeatNetNode {
                if(characteristic == BleCharacteristic.dfu) {
                    BleManager.shared.enableNotificationsFor(identifier.uuidString, type: .uartTx)
                }
            }
        }
    }
    
    func updateDeviceWithStatus(identifier: UUID, status: ProbeStatus) {
        // Update Probe Device from direct status notification
        guard let probe = findDeviceByBleIdentifier(bleIdentifier: identifier) as? Probe else { return }
        probe.updateProbeStatus(deviceStatus: status)
        
        connectionManager.receivedStatusFor(probe, node: nil)
    }
    
    private func updateDeviceWithNodeStatus(serialNumber: UInt32, status: ProbeStatus, hopCount: HopCount, node: MeatNetNode) {
        guard let probe = findProbeBySerialNumber(serialNumber: serialNumber) else { return }
        
        probe.updateProbeStatus(deviceStatus: status, hopCount: hopCount)
        
        connectionManager.receivedStatusFor(probe, node: node)
    }
    
    private func updateDeviceWithNodeStatus(serialNumber: String, status: DeviceStatus, hopCount: HopCount, node: MeatNetNode) {
        guard let device = findAccesoryBySerialNumber(serialNumber: serialNumber) else { return }
        
        device.updateDeviceStatus(deviceStatus: status, hopCount: hopCount)
        
        connectionManager.receivedStatusFor(device, node: node)
    }
    
    func handleDFUData(identifier: UUID, characteristic: BleCharacteristic, data: Data) {
        if characteristic == .dfu, let device = findDeviceByBleIdentifier(bleIdentifier: identifier) {
            dfuManager.handleDataFromAppFor(device, data: data)
        }
        else if characteristic == .dfuControlPoint, let device = findDeviceWithBootloaderIdentifier(identifier) {
            dfuManager.handleDataFromBootloaderFor(device, data: data)
        }
    }

    func handleBootloaderAdvertising(identifier: UUID, advertisingName: String, rssi: NSNumber) {
        let foundDevice = devices.values.first { $0.dfuAdvertisingName == advertisingName}
        
        if let foundDevice {
            // Save bootloader identifier for device
            foundDevice.bootloaderIdentifier = identifier.uuidString
            
            dfuManager.handleAdvertisingBootloader(device: foundDevice,
                                                   advertisingName: advertisingName)
        }
        else {
            let bootloaderDevice = BootloaderDevice(advertisingName: advertisingName,
                                                    RSSI: rssi,
                                                    identifier: identifier)
            addDevice(device: bootloaderDevice)
            print("DEVIN: Adding bootloader")
        }
    }
    
    /// Searches for or creates a Device record for the Probe represented by specified AdvertisingData.
    /// - param advertising - Advertising data for the specified Probe
    /// - param isConnectable - Whether the Probe is currently connectable (only present if advertising is directly from Probe)
    /// - param rssi - Signal strength to Probe (only present if advertising is directly from Probe)
    /// - param identifier - BLE identifier (only present if advertising is directly from Probe)
    /// - return Probe that was updated or added, if any
    private func updateProbeWithAdvertising(advertising: ProbeAdvertisingData, isConnectable: Bool?,
                                            rssi: NSNumber?, identifier: UUID?) -> Probe? {
        var foundProbe : Probe? = nil
        
        // If this advertising data was from a Probe, attempt to find its Device entry by its serial number.
        if advertising.serialNumber != Constants.INVALID_PROBE_SERIAL_NUMBER {
            let uniqueIdentifier = String(advertising.serialNumber)
            if let probe = devices[uniqueIdentifier] as? Probe {
                // If we already have an entry for this Probe, update its information.
                probe.updateWithAdvertising(advertising, isConnectable: isConnectable, RSSI: rssi, bleIdentifier: identifier)
                foundProbe = probe
            } else {
                // If we don't yet have an entry for this Probe, create one.
                let device = Probe(advertising, isConnectable: isConnectable, RSSI: rssi, identifier: identifier)
                addDevice(device: device)
                print("DEVIN: Adding probe from direct advertising")
                foundProbe = device
            }
        }
        
        return foundProbe
    }
    
    /// Determines which Device to create/update based on received AdvertisingData.
    /// - param advertising - Advertising data for the specified Probe
    /// - param isConnectable - Whether the advertising device is currently connectable
    /// - param rssi - Signal strength to advertising device
    /// - param identifier - BLE identifier of advertising device
    func updateDeviceWithAdvertising(advertising: any AdvertisingData, isConnectable: Bool, rssi: NSNumber, identifier: UUID) {
        switch(advertising.type) {
        case .probe:
            guard let advertising = advertising as? ProbeAdvertisingData else {
                return
            }
            
            // Create or update probe with advertising data
            let probe = updateProbeWithAdvertising(advertising: advertising, isConnectable: isConnectable, rssi: rssi, identifier: identifier)
            
            // Notify connection manager
            connectionManager.receivedDeviceAdvertising(probe)
            
        case .meatNetNode:

            // if meatnet is not enabled, then ignore advertising from meatnet nodes
            if(!connectionManager.meatNetEnabled) {
                return
            }
            
            let meatnetNode: MeatNetNode
            
            // Update node if it is in device list
            if let node = devices[identifier.uuidString] as? MeatNetNode {
                node.updateWithAdvertising(advertising, isConnectable: isConnectable, RSSI: rssi)
                meatnetNode = node
            } else {
                // Create node and add to device list
                meatnetNode = MeatNetNode(advertising, isConnectable: isConnectable, RSSI: rssi, identifier: identifier)
                addDevice(device: meatnetNode)
                print("DEVIN: Adding meat net node")
            }
            
            if let advertising = advertising as? ProbeAdvertisingData {
                // Update the probe associated with this advertising data
                let probe = updateProbeWithAdvertising(advertising: advertising, isConnectable: nil, rssi: nil, identifier: nil)
                
                // Notify connection manager
                connectionManager.receivedDeviceAdvertising(probe, from: meatnetNode)
                
                // Track that data was recieved for probe on node
                meatnetNode.dataReceivedFromDevice(probe)
            }
            
        case .gauge:
            let meatNetNode: MeatNetNode
            
            // Update gauge if it is in device list
            if let node = devices[identifier.uuidString] as? MeatNetNode {
                meatNetNode = node
                node.updateWithAdvertising(advertising, isConnectable: isConnectable, RSSI: rssi)
            }
            else {
                // Create node and add to device list
                meatNetNode = MeatNetNode(advertising, isConnectable: isConnectable, RSSI: rssi, identifier: identifier)
                addDevice(device: meatNetNode)
                print("DEVIN: Adding meat net node gauge")
            }
            
            if let existingGauge = meatNetNode.accessory as? GrillGauge {
                existingGauge.updateWithAdvertising(advertising)
            }
            else {
                let gauge = GrillGauge(parent: meatNetNode, advertising: advertising)
                meatNetNode.accessory = gauge
                
                addAccessory(accessory: gauge)
            }
            
            connectionManager.receivedDeviceAdvertising(meatNetNode)
        case .unknown, .charger, .display:
            print("Found device with unknown type")
        }
    }
    
    /// Finds Device (Node or Probe) by specified BLE identifier.
    private func findDeviceByBleIdentifier(bleIdentifier: UUID) -> Device? {
        var foundDevice : Device? = nil
        if let device = devices[bleIdentifier.uuidString]  {
            // This was a MeatNet Node as it was stored by its BLE UUID.
            foundDevice = device
        } else {
            // Search through Devices to see if any Probes have a matching BLE identifier.
            for(_, device) in devices {
                if let deviceBleIdentifier = device.bleIdentifier {
                    if bleIdentifier.uuidString == deviceBleIdentifier {
                        // We found a device matching this identifier, so break
                        foundDevice = device
                        break
                    }
                }
            }
        }
        
        return foundDevice
    }
    
    private func findDeviceWithBootloaderIdentifier(_ bleIdentifier: UUID) -> Device? {
        for device in devices.values {
            if device.bootloaderIdentifier == bleIdentifier.uuidString {
                return device
            }
        }
        
        return nil
    }
    
    /// Finds Device by serial number string
    private func findDeviceBySerialNumber(serialNumber: String) -> Device? {
        var foundDevice : Device? = nil
        
        // Search through Devices to see if any devices have matching serial number
        for(_, device) in devices {
            if let device = device as? MeatNetNode, let serialNumberString = device.serialNumberString {
                if serialNumberString == serialNumber {
                    // We found a device matching this identifier, so break
                    foundDevice = device
                    break
                }
            }
            else if let device = device as? Probe {
                if device.serialNumberString == serialNumber {
                    // We found a device matching this identifier, so break
                    foundDevice = device
                    break
                }
            }
        }
        
        return foundDevice
    }
    
    private func findProbeBySerialNumber(serialNumber: UInt32) -> Probe? {
        var foundProbe : Probe? = nil
        
        if let probe = devices[String(serialNumber)] as? Probe {
            // Probes are stored using their serial number encoded as a String as their key.
            foundProbe = probe
        }
        
        return foundProbe
    }
    
    private func findAccesoryBySerialNumber(serialNumber: String) -> MeatNetNode? {
        var foundDevice : MeatNetNode? = nil
        
        if let device = devices.first(where: { ($0.value as? MeatNetNode)?.accessory?.serialNumberString == serialNumber })?.value as? MeatNetNode {
            foundDevice = device
        }
        
        return foundDevice
    }
    
    func updateDeviceFwVersion(identifier: UUID, fwVersion: String) {
        if let device = findDeviceByBleIdentifier(bleIdentifier: identifier) {
            device.firmareVersion = fwVersion
        }
    }
    
    func updateDeviceSerialNumber(identifier: UUID, serialNumber: String) {
        if let node = findDeviceByBleIdentifier(bleIdentifier: identifier) as? MeatNetNode {
            node.serialNumberString = serialNumber
        }
    }
    
    func updateDeviceHwRevision(identifier: UUID, hwRevision: String) {
        if let device = findDeviceByBleIdentifier(bleIdentifier: identifier)  {
            device.hardwareRevision = hwRevision
        }
    }
    
    func updateDeviceModelInfo(identifier: UUID, modelInfo: String) {
        if let device = findDeviceByBleIdentifier(bleIdentifier: identifier)  {
            device.updateWithModelInfo(modelInfo)
        }
    }
    
    /// Processes data received over UART, which could be Responses and/or Requests depending on the source.
    func handleUARTData(identifier: UUID, data: Data) {
        if let device = findDeviceByBleIdentifier(bleIdentifier: identifier) {
            if let _ = device as? Probe {
                // If this was a Probe, treat all the Data as Responses.
                let responses = Response.fromData(data)
                for response in responses {
                    handleProbeUARTResponse(identifier: identifier, response: response)
                }
            } else if let _ = device as? MeatNetNode {
                // If this was a Node, the data could be Responses and/or Requests.
                let messages = NodeUARTMessage.fromData(data)
                for message in messages {
                    if let request = message as? NodeRequest {
                        // Process Node request
                        handleNodeUARTRequest(identifier: identifier, request: request)
                    } else if let response = message as? NodeResponse {
                        // Process node response
                        handleNodeUARTResponse(identifier: identifier, response: response)
                    }
                }
            }
            
        }
    }
    
    //////////////////////////////////////////////
    /// - MARK: Probe Direct Message Handling
    //////////////////////////////////////////////
    
    private func handleProbeUARTResponse(identifier: UUID, response: Response) {
        switch(response.messageType) {
        case .log:
            if let logResponse = response as? LogResponse {
                updateDeviceWithLogResponse(identifier: identifier, logResponse: logResponse)
            }
        case .sessionInfo:
            if let sessionResponse = response as? SessionInfoResponse {
                if(sessionResponse.success) {
                    updateDeviceWithSessionInformation(identifier: identifier, sessionInformation: sessionResponse.info)
                }
            }
            
        case .readOverTemperature:
            if let readOverTemperatureResponse = response as? ReadOverTemperatureResponse {
                messageHandlers.callReadOverTemperatureCompletionHandler(identifier, response: readOverTemperatureResponse)
            }
        // Messages with success completion handlers
        case .configureFoodSafe, 
                .resetFoodSafe,
                .setColor,
                .setPowerMode,
                .setID,
                .setPrediction,
                .resetSession:
                messageHandlers.callSuccessHandler(identifier, response: response)
        }
    }
    
    private func updateDeviceWithLogResponse(identifier: UUID, logResponse: LogResponse) {
        guard logResponse.success else { return }
        
        if let probe = findDeviceByBleIdentifier(bleIdentifier: identifier) as? Probe {
            probe.processLogResponse(logResponse: logResponse)
        }
    }
    
    private func updateDeviceWithLogResponse(identifier: UUID, logResponse: NodeGaugeReadLogsResponse) {
        guard logResponse.success else { return }
        
        if let gauge = findDeviceByBleIdentifier(bleIdentifier: identifier) as? GrillGauge {
            gauge.processLogResponse(logResponse: logResponse)
        }
    }
    
    private func updateDeviceWithSessionInformation(identifier: UUID, sessionInformation: SessionInformation) {
        if let probe = findDeviceByBleIdentifier(bleIdentifier: identifier) as? Probe {
            probe.updateWithSessionInformation(sessionInformation)
        }
        else if let gaugeParent = findDeviceByBleIdentifier(bleIdentifier: identifier) as? MeatNetNode, let accessory = gaugeParent.accessory {
            accessory.updateWithSessionInformation(sessionInformation)
        }
    }
    
    ///////////////////////////////////////
    /// - MARK: Node/MeatNet Direct Message Handling
    ///////////////////////////////////////
    
    private func handleNodeUARTResponse(identifier: UUID, response: NodeResponse) {
//        print("Received Response from Node: \(response)")
        
        switch(response.messageType) {
        case .probeFirmwareRevision:
            if let readFirmwareResponse = response as? NodeReadFirmwareRevisionResponse,
               let probe = findProbeBySerialNumber(serialNumber: readFirmwareResponse.probeSerialNumber) {
                    probe.firmareVersion = readFirmwareResponse.fwRevision
                }
            
        case .probeHardwareRevision:
            if let readHardwareResponse = response as? NodeReadHardwareRevisionResponse,
               let probe = findProbeBySerialNumber(serialNumber: readHardwareResponse.probeSerialNumber) {
                    probe.hardwareRevision = readHardwareResponse.hwRevision
                }
            
        case .probeModelInformation:
            if let readModelInfoResponse = response as? NodeReadModelInfoResponse,
                let probe = findProbeBySerialNumber(serialNumber: readModelInfoResponse.probeSerialNumber) {
                    probe.updateWithModelInfo(readModelInfoResponse.modelInfo)
                }
            
        case .sessionInfo:
            if let sessionInfoResponse = response as? NodeReadSessionInfoResponse,
               let probe = findProbeBySerialNumber(serialNumber: sessionInfoResponse.probeSerialNumber) {
                    probe.updateWithSessionInformation(sessionInfoResponse.info)
                }
            
        case .log:
            if let readLogsResponse = response as? NodeReadLogsResponse,
               let probe = findProbeBySerialNumber(serialNumber: readLogsResponse.probeSerialNumber) {
                    probe.processLogResponse(logResponse: readLogsResponse)
                }
        case .gaugeLog:
            if let readGaugeLogsResponse = response as? NodeGaugeReadLogsResponse, let gauge = findAccesoryBySerialNumber(serialNumber: readGaugeLogsResponse.gaugeSerialNumber)?.accessory as? GrillGauge {
                gauge.processLogResponse(logResponse: readGaugeLogsResponse)
            }
        case .getFeatureFlags:
            if let featureFlagsResponse = response as? NodeReadFeatureFlagsResponse,
               let device = findDeviceBySerialNumber(serialNumber: featureFlagsResponse.nodeSerialNumber) as? MeatNetNode {
                device.updateFeatureFlags(featureFlagsResponse.flags)
            }
        case .setPrediction, .configureFoodSafe, .resetFoodSafe, .setPowerMode, .resetSession, .setHighLowAlarm:
            messageHandlers.callNodeSuccessCompletionHandler(response: response)
        case .custom(_):
            deviceResponseHandler?.handleResponse(identifier: identifier, response: response)
        default: break
        }

    }
    
    private func handleNodeUARTRequest(identifier: UUID, request: NodeRequest) {
//        print("CombustionBLE : Received Request from Node: \(request)")
        if let statusRequest = request as? NodeProbeStatusRequest {
            
            if let probeStatus = statusRequest.probeStatus,
               let node = findDeviceByBleIdentifier(bleIdentifier: identifier) as? MeatNetNode,
               let hopCount = statusRequest.hopCount {
                
                // Update the Probe based on the information that was received
                updateDeviceWithNodeStatus(serialNumber: statusRequest.serialNumber,
                                           status: probeStatus,
                                           hopCount: hopCount,
                                           node: node)
            }
        }
        else if let statusRequest = request as? NodeGaugeStatusRequest {
            
            if let gaugeStatus = statusRequest.gaugeStatus,
               let node = findDeviceByBleIdentifier(bleIdentifier: identifier) as? MeatNetNode,
               let hopCount = statusRequest.hopCount {
                
                // Update the Gauge based on the information that was received
                updateDeviceWithNodeStatus(serialNumber: statusRequest.serialNumber,
                                           status: gaugeStatus,
                                           hopCount: hopCount,
                                           node: node)
            }
        }
        else if let heartBeatRequest = request as? NodeHeartbeatRequest {
            // TODO handle heartBeatRequest
        }
        else if let request = request as? NodeCustomRequest {
            deviceResponseHandler?.handleRequest(identifier: identifier, request: request)
        }
    }
    
}
