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

/// Singleton that provides list of detected Devices
/// (either via Bluetooth or from a list in the Cloud)
public class DeviceManager : DeviceManagerProtocol, ObservableObject {
    
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
    @Published public private(set) var devices : [String: Device] = [String: Device]()
    
    // Bluetooth manager state
    @Published public private(set) var bluetoothState: CBManagerState = .unknown
    
    /// Flag that tracks if any DFUs are currently in progress
    @Published public private(set) var dfuIsInProgress = false

    // Struct to store when BLE message was send and the completion handler for message
    private struct MessageHandler {
        let timeSent: Date
        let handler: (Bool) -> Void
    }
    
    private var cancellables: Set<AnyCancellable> = []
    
    /// Handler for messages from Probe
    private let messageHandlers = MessageHandlers()
    
    /// Connection manager to handle BLE connection logic
    private let connectionManager = ConnectionManager()
    
    public func addSimulatedProbe() {
        addDevice(device: SimulatedProbe())
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
    
    /// Sets the white list for thermometers.  Framework will only connect to thermometers
    /// in the white list and nodes that are advertising data from thermometer in whitelist.
    /// - param whiteList: White list of probes serial numbers
    public func setThermometerWhiteList(_ whiteList: Set<String>) {
        connectionManager.setThermometerWhiteList(whiteList)
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
        DFUManager.shared.$dfuIsInProgress
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
    }
    
    /// Returns list of probes
    /// - returns: List of all known probes.
    public func getProbes() -> [Probe] {
        return Array(devices.values).compactMap { device in
            return device as? Probe
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
    
    /// Checks if specified probe is connected to any meatnet node
    func isProbeConnectedToMeatnet(_ probe: Probe) -> Bool {
        let meatnetNodes = getMeatnetNodes()
        
        for node in meatnetNodes {
            if(node.hasConnectionToProbe(probe.serialNumber)) {
                return true
            }
        }
        
        return false
    }
    
    private func getNodesConnectedToProbe(serialNumber: UInt32) -> [MeatNetNode] {
        var nodesWithProbe: [MeatNetNode] = []
        
        let meatnetNodes = getMeatnetNodes()
        
        for node in meatnetNodes {
            // Check Nodes to which we are connected to see if they have a route to the Probe
            if node.connectionState == .connected, node.hasConnectionToProbe(serialNumber) {
                nodesWithProbe.append(node)
            }
        }
        
        return nodesWithProbe
    }
    
    private func shouldSendMessageDirectlyTo(probe: Probe) -> Bool {
        return probe.connectionState == .connected
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
    func requestLogsFrom(_ probe: Probe, minSequence: UInt32, maxSequence: UInt32) {
        if shouldSendMessageDirectlyTo(probe: probe) {
            // Request logs directly from Probe.
            let request = LogRequest(minSequence: minSequence,
                                     maxSequence: maxSequence)
            
            BleManager.shared.sendRequest(identifier: probe.bleIdentifier, request: request)
            
        }
        else {
            // Send message to all nodes that have a route to the probe
            let nodesConnectedToProbe = getNodesConnectedToProbe(serialNumber: probe.serialNumber)
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
            let nodesConnectedToProbe = getNodesConnectedToProbe(serialNumber: probe.serialNumber)
            
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
            let nodesConnectedToProbe = getNodesConnectedToProbe(serialNumber: probe.serialNumber)
            
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
            let nodesConnectedToProbe = getNodesConnectedToProbe(serialNumber: probe.serialNumber)
            
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
            let nodesConnectedToProbe = getNodesConnectedToProbe(serialNumber: probe.serialNumber)
            
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
    
    /// Set the DFU file to be used on devices with failed software upgrade.
    /// A failed upgrade will occur if the user kills the application in the middle of
    /// the software upgrade process.  After this method is called, DFU will be initiated
    /// when a device with failed software upgrade is detected.
    ///
    /// - dfuFiles: DFU files for each DFU type
    public func restartFailedUpgradesWith(dfuFiles: [DFUDeviceType: URL]) {
        for (type, dfuFile) in dfuFiles {
            DFUManager.shared.setDefaultDFUForType(dfuFile: dfuFile, dfuType: type)
        }
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
        let nodesConnectedToProbe = getNodesConnectedToProbe(serialNumber: probe.serialNumber)
        
        // Store completion handler
        messageHandlers.addNodeSuccessCompletionHandler(request: request, completionHandler: completionHandler)
        
        // Send request to device
        BleManager.shared.sendRequestToNodes(nodesConnectedToProbe, request: request)
    }
}

extension DeviceManager : BleManagerDelegate {
    func updateBluetoothState(state: CBManagerState) {
        bluetoothState = state
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
    
    func handleBootloaderAdvertising(advertisingName: String, rssi: NSNumber, peripheral: CBPeripheral) {
        // If Bootloader is associated with currently running DFU,
        // then check if DFU needs to be restarted
        if let uniqueIdentifier = DFUManager.shared.uniqueIdentifierFrom(advertisingName: advertisingName) {
            if let device = devices[uniqueIdentifier] {
                DFUManager.shared.checkForStuckDFU(peripheral: peripheral, advertisingName: advertisingName, device: device)
            }
        }
        else {
            // If Bootloader is NOT associated with a currently running DFU,
            // then send data to Device manager to save device and start DFU
            let device = BootloaderDevice(advertisingName: advertisingName,  RSSI: rssi, identifier: peripheral.identifier)
            addDevice(device: device)
            BleManager.shared.retryFirmwareUpdate(device: device)
        }
    }
    
    /// Searches for or creates a Device record for the Probe represented by specified AdvertisingData.
    /// - param advertising - Advertising data for the specified Probe
    /// - param isConnectable - Whether the Probe is currently connectable (only present if advertising is directly from Probe)
    /// - param rssi - Signal strength to Probe (only present if advertising is directly from Probe)
    /// - param identifier - BLE identifier (only present if advertising is directly from Probe)
    /// - return Probe that was updated or added, if any
    private func updateProbeWithAdvertising(advertising: AdvertisingData, isConnectable: Bool?,
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
    func updateDeviceWithAdvertising(advertising: AdvertisingData, isConnectable: Bool, rssi: NSNumber, identifier: UUID) {
        switch(advertising.type) {
        case .probe:
            
            // Create or update probe with advertising data
            let probe = updateProbeWithAdvertising(advertising: advertising, isConnectable: isConnectable, rssi: rssi, identifier: identifier)
            
            // Notify connection manager
            connectionManager.receivedProbeAdvertising(probe)
            
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
            }
            
            // Update the probe associated with this advertising data
            let probe = updateProbeWithAdvertising(advertising: advertising, isConnectable: nil, rssi: nil, identifier: nil)
            
            // Notify connection manager
            connectionManager.receivedProbeAdvertising(probe, from: meatnetNode)

        case .unknown:
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
    
    private func findProbeBySerialNumber(serialNumber: UInt32) -> Probe? {
        var foundProbe : Probe? = nil
        
        if let probe = devices[String(serialNumber)] as? Probe {
            // Probes are stored using their serial number encoded as a String as their key.
            foundProbe = probe
        }
        
        return foundProbe
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
                .setID,
                .setPrediction:
                messageHandlers.callSuccessHandler(identifier, response: response)
        }
    }
    
    private func updateDeviceWithLogResponse(identifier: UUID, logResponse: LogResponse) {
        guard logResponse.success else { return }
        
        if let probe = findDeviceByBleIdentifier(bleIdentifier: identifier) as? Probe {
            probe.processLogResponse(logResponse: logResponse)
        }
    }
    
    private func updateDeviceWithSessionInformation(identifier: UUID, sessionInformation: SessionInformation) {
        if let probe = findDeviceByBleIdentifier(bleIdentifier: identifier) as? Probe {
            probe.updateWithSessionInformation(sessionInformation)
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
            
        case .setPrediction, .configureFoodSafe, .resetFoodSafe:
            messageHandlers.callNodeSuccessCompletionHandler(response: response)
            
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
        else if let heartBeatRequest = request as? NodeHeartbeatRequest {
            // TODO handle heartBeatRequest
        }
    }
    
}
