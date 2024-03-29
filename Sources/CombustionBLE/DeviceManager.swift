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

/// Singleton that provides list of detected Devices
/// (either via Bluetooth or from a list in the Cloud)
public class DeviceManager : ObservableObject {
    
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

    // Struct to store when BLE message was send and the completion handler for message
    private struct MessageHandler {
        let timeSent: Date
        let handler: (Bool) -> Void
    }
    
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
    
    /// Gets the best Node for communicating with a Probe.
    func getBestNodeForProbe(serialNumber: UInt32) -> MeatNetNode? {
        var foundNode : MeatNetNode? = nil
        var foundRssi = Device.MIN_RSSI
        
        let meatnetNodes = getMeatnetNodes()
        
        for node in meatnetNodes {
            // Check Nodes to which we are connected to see if they have a route to the Probe
            if node.connectionState == .connected {
                // Choose node with the best RSSI that has connection to probe
                if node.hasConnectionToProbe(serialNumber) && node.rssi > foundRssi {
                    foundNode = node
                    foundRssi = node.rssi
                }
            }
        }
        
        return foundNode
    }
    
    /// Returns the best device to which to send a request to a Probe, if there is one.
    public func getBestRouteToProbe(serialNumber: UInt32) -> Device? {
        var foundDevice : Device? = nil
        
        if let probe = findProbeBySerialNumber(serialNumber: serialNumber), probe.connectionState == .connected {
            // If we're directly connected to this probe, send the request directly.
            foundDevice = probe
        } else {
            foundDevice = getBestNodeForProbe(serialNumber: serialNumber)
        }
        
        return foundDevice
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
    func requestLogsFrom(_ device: Device, minSequence: UInt32, maxSequence: UInt32) {
        if let device = device as? Probe {
            let targetDevice = getBestRouteToProbe(serialNumber: device.serialNumber)
            
            if let probe = targetDevice as? Probe, let bleIdentifier = probe.bleIdentifier {
            
                // Request logs directly from Probe.
                let request = LogRequest(minSequence: minSequence,
                                         maxSequence: maxSequence)
                
                BleManager.shared.sendRequest(identifier: bleIdentifier, request: request)
                
            } else if let node = targetDevice as? MeatNetNode, let bleIdentifier = node.bleIdentifier {
                // If the best route is through a Node, send it that way.
                
                // Send request to device
                let request = NodeReadLogsRequest(serialNumber: device.serialNumber,
                                                  minSequence: minSequence,
                                                  maxSequence: maxSequence)
                BleManager.shared.sendRequest(identifier: bleIdentifier, request: request)
            }
        }
    }
    
    /// Set Probe ID on specified device.
    /// - parameter device: Device to set ID on
    /// - parameter ProbeID: New Probe ID
    /// - parameter completionHandler: Completion handler to be called operation is complete
    public func setProbeID(_ device: Device, id: ProbeID, completionHandler: @escaping MessageHandlers.SuccessCompletionHandler) {
        // TODO - Send request via Node.
        
        // Store completion handler
        messageHandlers.addSetIDCompletionHandler(device, completionHandler: completionHandler)
        
        // Send request to device
        if let device = device as? Probe, let bleIdentifier = device.bleIdentifier {
            let request = SetIDRequest(id: id)
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
        
        // Store completion handler
        messageHandlers.addSetColorCompletionHandler(device, completionHandler: completionHandler)

        // Send request to device
        if let device = device as? Probe, let bleIdentifier = device.bleIdentifier {
            let request = SetColorRequest(color: color)
            BleManager.shared.sendRequest(identifier: bleIdentifier, request: request)
        }
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
        
        if let device = device as? Probe {
            
            let targetDevice = getBestRouteToProbe(serialNumber: device.serialNumber)
            
            if let probe = targetDevice as? Probe, let bleIdentifier = probe.bleIdentifier {
                // If the best route is directly to the Probe, send it that way.
             
                // Store completion handler
                messageHandlers.addSetPredictionCompletionHandler(device, completionHandler: completionHandler)
                
                // Send request to device
                let request = SetPredictionRequest(setPointCelsius: removalTemperatureC, mode: .timeToRemoval)
                BleManager.shared.sendRequest(identifier: bleIdentifier, request: request)
                
            } else if let node = targetDevice as? MeatNetNode, let bleIdentifier = node.bleIdentifier {
                // If the best route is through a Node, send it that way.
                
                // Store completion handler
                messageHandlers.addNodeSetPredictionCompletionHandler(node, completionHandler: completionHandler)
                
                // Send request to device
                let request = NodeSetPredictionRequest(serialNumber: device.serialNumber,
                                                       setPointCelsius: removalTemperatureC,
                                                       mode: .timeToRemoval)
                BleManager.shared.sendRequest(identifier: bleIdentifier, request: request)
            }
           
        }
    }
    
    
    /// Sends a request to the device to set the prediction mode to none, stopping any active prediction.
    ///
    /// - parameter device: Device to cancel prediction on
    /// - parameter completionHandler: Completion handler to be called operation is complete
    public func cancelPrediction(_ device: Device, completionHandler: @escaping MessageHandlers.SuccessCompletionHandler) {
        
        if let device = device as? Probe {
            
            let targetDevice = getBestRouteToProbe(serialNumber: device.serialNumber)
            
            if let probe = targetDevice as? Probe, let bleIdentifier = probe.bleIdentifier {
                // If the best route is directly to the Probe, send it that way.
             
                // Store completion handler
                messageHandlers.addSetPredictionCompletionHandler(device, completionHandler: completionHandler)
                
                // Send request to device
                let request = SetPredictionRequest(setPointCelsius: 0.0, mode: .none)
                BleManager.shared.sendRequest(identifier: bleIdentifier, request: request)
                
            } else if let node = targetDevice as? MeatNetNode, let bleIdentifier = node.bleIdentifier {
                // If the best route is through a Node, send it that way.
                
                // Store completion handler
                messageHandlers.addNodeSetPredictionCompletionHandler(node, completionHandler: completionHandler)
                
                // Send request to device
                let request = NodeSetPredictionRequest(serialNumber: device.serialNumber,
                                                       setPointCelsius: 0.0,
                                                       mode: .none)
                BleManager.shared.sendRequest(identifier: bleIdentifier, request: request)
            }
           
        }
    }
    
    
    /// Sends a request to the probe to read the session information.
    ///
    /// - parameter device: Device to read session info
    /// - parameter completionHandler: Completion handler to be called operation is complete
    public func readSessionInfo(probe: Probe) {
        
        let targetDevice = getBestRouteToProbe(serialNumber: probe.serialNumber)
        
        if let targetProbe = targetDevice as? Probe, let bleIdentifier = targetProbe.bleIdentifier {
            // If the best route is directly to the Probe, send it that way.
         
            // Send request to device
            let request = SessionInfoRequest()
            BleManager.shared.sendRequest(identifier: bleIdentifier, request: request)
            
        } else if let node = targetDevice as? MeatNetNode, let bleIdentifier = node.bleIdentifier {
            // If the best route is through a Node, send it that way.
            
            // Send request to device
            let request = NodeReadSessionInfoRequest(serialNumber: probe.serialNumber)
            BleManager.shared.sendRequest(identifier: bleIdentifier, request: request)
        }
    }
    
    /// Sends request to the device to read the probe firmware version.
    ///
    /// - parameter probe: Probe for which to read firmware version
    public func readFirmwareVersion(probe: Probe) {
        if let targetDevice = getBestRouteToProbe(serialNumber: probe.serialNumber) {
            if let targetProbe = targetDevice as? Probe, let bleIdentifier = targetProbe.bleIdentifier {
                // If the best route is directly to the Probe, send it that way.
                BleManager.shared.readFirmwareRevision(identifier: bleIdentifier)
            } else if let node = targetDevice as? MeatNetNode, let bleIdentifier = node.bleIdentifier {
                // If the best route is through a Node, send it that way.
                
                let request = NodeReadFirmwareRevisionRequest(serialNumber: probe.serialNumber)
                BleManager.shared.sendRequest(identifier: bleIdentifier, request: request)
            }
        }
    }
    
    /// Sends request to the device to read the probe hardware version.
    ///
    /// - parameter probe: Probe for which to read hardware version
    public func readHardwareVersion(probe: Probe) {
        if let targetDevice = getBestRouteToProbe(serialNumber: probe.serialNumber) {
            if let targetProbe = targetDevice as? Probe, let bleIdentifier = targetProbe.bleIdentifier {
                // If the best route is directly to the Probe, send it that way.
                BleManager.shared.readHardwareRevision(identifier: bleIdentifier)
            } else if let node = targetDevice as? MeatNetNode, let bleIdentifier = node.bleIdentifier {
                // If the best route is through a Node, send it that way.
                
                let request = NodeReadHardwareRevisionRequest(serialNumber: probe.serialNumber)
                BleManager.shared.sendRequest(identifier: bleIdentifier, request: request)
            }
        }
    }
    
    /// Sends request to read the probe model info.
    ///
    /// - parameter probe: Probe for which to read model info.
    public func readModelInfoForProbe(_ probe: Probe) {
        if let targetDevice = getBestRouteToProbe(serialNumber: probe.serialNumber) {
            if let targetProbe = targetDevice as? Probe, let bleIdentifier = targetProbe.bleIdentifier {
                // If the best route is directly to the Probe, send it that way.
                BleManager.shared.readModelNumber(identifier: bleIdentifier)
            } else if let node = targetDevice as? MeatNetNode, let bleIdentifier = node.bleIdentifier {
                // If the best route is through a Node, send it that way.
                
                let request = NodeReadModelInfoRequest(serialNumber: probe.serialNumber)
                BleManager.shared.sendRequest(identifier: bleIdentifier, request: request)
            }
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
        
        if let device = device as? Probe, let bleIdentifier = device.bleIdentifier {
            // Store completion handler
            messageHandlers.addReadOverTemperatureCompletionHandler(device, completionHandler: completionHandler)
            
            // Send request to device
            let request = ReadOverTemperatureRequest()
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
}

extension DeviceManager : BleManagerDelegate {
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
        
        connectionManager.receivedStatusFor(probe, directConnection: true)
    }
    
    func updateDeviceWithNodeStatus(serialNumber: UInt32, status: ProbeStatus, hopCount: HopCount) {
        guard let probe = findProbeBySerialNumber(serialNumber: serialNumber) else { return }
        probe.updateProbeStatus(deviceStatus: status, hopCount: hopCount)
        
        connectionManager.receivedStatusFor(probe, directConnection: false)
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
            
            // Add probe to meatnet node
            meatnetNode.updateNetworkedProbe(probe: probe)
            
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
        
        if let setPredictionResponse = response as? NodeSetPredictionResponse {
            messageHandlers.callNodeSetPredictionCompletionHandler(identifier, response: setPredictionResponse)
        } else if let readFirmwareResponse = response as? NodeReadFirmwareRevisionResponse {
            if let probe = findProbeBySerialNumber(serialNumber: readFirmwareResponse.probeSerialNumber) {
                probe.firmareVersion = readFirmwareResponse.fwRevision
            }
        } else if let readHardwareResponse = response as? NodeReadHardwareRevisionResponse {
            if let probe = findProbeBySerialNumber(serialNumber: readHardwareResponse.probeSerialNumber) {
                probe.hardwareRevision = readHardwareResponse.hwRevision
            }
        } else if let readModelInfoResponse = response as? NodeReadModelInfoResponse {
            if let probe = findProbeBySerialNumber(serialNumber: readModelInfoResponse.probeSerialNumber) {
                probe.updateWithModelInfo(readModelInfoResponse.modelInfo)
            }
        } else if let sessionInfoResponse = response as? NodeReadSessionInfoResponse {
            if let probe = findProbeBySerialNumber(serialNumber: sessionInfoResponse.probeSerialNumber) {
                probe.updateWithSessionInformation(sessionInfoResponse.info)
            }
        } else if let readLogsResponse = response as? NodeReadLogsResponse {
            if let probe = findProbeBySerialNumber(serialNumber: readLogsResponse.probeSerialNumber) {
                probe.processLogResponse(logResponse: readLogsResponse)
            }
        }
    }
    
    private func handleNodeUARTRequest(identifier: UUID, request: NodeRequest) {
//        print("CombustionBLE : Received Request from Node: \(request)")
        if let statusRequest = request as? NodeProbeStatusRequest, let probeStatus = statusRequest.probeStatus, let hopCount = statusRequest.hopCount {
            // Update the Probe based on the information that was received
            updateDeviceWithNodeStatus(serialNumber: statusRequest.serialNumber,
                                       status: probeStatus,
                                       hopCount: hopCount)
            
            // Ensure the Node that sent this item has the Probe in its list of repeated devices.
            if let node = findDeviceByBleIdentifier(bleIdentifier: identifier) as? MeatNetNode,
               let probe = findProbeBySerialNumber(serialNumber: statusRequest.serialNumber) {
                // Add the probe to the node's list of networked probes
                node.updateNetworkedProbe(probe: probe)
            }
        }
        else if let heartBeatRequest = request as? NodeHeartbeatRequest {
            // TODO handle heartBeatRequest
        }
    }
    
}
