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
    @available(*, deprecated, message: "Use CancellableDeviceManagerProtocol.cancelPredictionCommand(_:completionHandler:) for cancellable MeatNet retry behavior.")
    func cancelPrediction(_ probe: Probe,
                          completionHandler: @escaping (_ success: Bool) -> Void)

    @available(*, deprecated, message: "Use CancellableDeviceManagerProtocol.setRemovalPredictionCommand(_:removalTemperatureC:completionHandler:) for cancellable MeatNet retry behavior.")
    func setRemovalPrediction(_ probe: Probe,
                              removalTemperatureC: Double,
                              completionHandler: @escaping (_ success: Bool) -> Void)
    
    @discardableResult
    func cancelPredictionCommand(_ probe: Probe,
                                 completionHandler: @escaping CommandCompletionHandler) -> CommandHandle?

    @discardableResult
    func setRemovalPredictionCommand(_ probe: Probe,
                                     removalTemperatureC: Double,
                                     completionHandler: @escaping CommandCompletionHandler) -> CommandHandle?
}

public protocol DeviceResponseHandlerProtocol: AnyObject {
    func handleResponse(identifier: UUID, response: NodeResponse)
    func handleRequest(identifier: UUID, request: NodeRequest)
}

public protocol MeatNetActionDelegate: AnyObject {
    
    /// Adds a device to the local list.
    /// - parameter global: whether to silence all alarms
    /// - parameter productType: if not global, then the product type of the alarm to dismiss
    /// - parameter probeSerialNumber: the probe serial number that has alarms to silence, nil if global
    /// - parameter nodeSerialNumber: the node serial number that has alarms to silence, nil if global
    func silenceAlarms(global: Bool, productType: ProductType?, probeSerialNumber: String?, nodeSerialNumber: String?)
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

    private var dfuManager = DFUManager.shared
    
    private var cancellables: Set<AnyCancellable> = []
    
    // Per-probe cancellables to observe published changes like `id`
    private var probeIdCancellables: [String: AnyCancellable] = [:]
    
    /// Handler for messages from Probe
    private let commandCoordinator = CommandCoordinator()
    
    /// Connection manager to handle BLE connection logic
    private let connectionManager = ConnectionManager()
    
    public weak var deviceResponseHandler: DeviceResponseHandlerProtocol?
    public weak var meatNetActionDelegate: MeatNetActionDelegate?
    
    public func addSimulatedProbe() {
        addDevice(device: SimulatedProbe())
    }
    
    public func addSimulatedGauge() {
        addDevice(device: SimulatedGauge())
    }

    public func addSimulatedEngine() {
        let engine = SimulatedEngine()
        addDevice(device: engine)
        
        if let accessory = engine.accessory {
            addAccessory(accessory: accessory)
        }
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
            commandCoordinator.checkForTimeout()
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
        
        if let probe = device as? Probe {
            // Start observing id changes for collision handling
            observeProbeIdChanges(probe)
        }
    }
    
    /// Observe a probe's published `id` and trigger collision resolution when it changes.
    private func observeProbeIdChanges(_ probe: Probe) {
        // Cancel existing subscription for this probe if present
        probeIdCancellables[probe.uniqueIdentifier]?.cancel()
        
        // Subscribe to id changes
        let cancellable = probe.$id
            .removeDuplicates()
            .sink { [weak self, weak probe] newId in
                guard let self = self, let probe = probe else { return }
                // Run single-collision resolution for this probe
                self.resolveProbeIdCollision(for: probe, incomingId: newId)
            }
        
        probeIdCancellables[probe.uniqueIdentifier] = cancellable
    }
    
    /// Removes device from the list.
    func clearDevice(device: Device) {
        devices.removeValue(forKey: device.uniqueIdentifier)
        
        if let device = device as? MeatNetNode, let accessory = device.accessory {
            clearAccessory(accessory: accessory)
        }
        
        // Cancel id observation if this was a probe
        if device is Probe {
            probeIdCancellables[device.uniqueIdentifier]?.cancel()
            probeIdCancellables.removeValue(forKey: device.uniqueIdentifier)
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

    private func activeProbes() -> [Probe] {
        return getProbes().filter { probe in
            return probe.connectionState == .connected || isDeviceConnectedToMeatnet(probe)
        }
    }

    private func lowestAvailableProbeId(excluding active: [Probe]) -> ProbeID? {
        let usedIds = Set(active.map { $0.id })
        return ProbeID.allCases.first { !usedIds.contains($0) }
    }

    /// Resolves incoming ID collisions by keeping the requested ID and reassigning
    /// the highest-serial probe in the collision set to the lowest available ID.
    private func resolveProbeIdCollision(for probe: Probe, incomingId: ProbeID) {
        let active = activeProbes()

        var hasCollision = false
        var highest: Probe? = nil
        var usedIds = Set<ProbeID>()
        
        // Single pass: build usedIds, detect collisions, and track highest-serial candidate among colliders.
        for p in active {
            usedIds.insert(p.id)
            
            guard p.id == incomingId else { continue }
            
            // A collision exists if another probe (different uniqueIdentifier) has the same ID.
            if p.uniqueIdentifier != probe.uniqueIdentifier {
                hasCollision = true
            }
            
            if highest == nil || p.serialNumber > highest!.serialNumber {
                highest = p
            }
        }
        
        // No other probe holds the same incoming ID; nothing to do.
        guard hasCollision else { return }
        
        // Include the incoming probe in the candidate pool even if it wasn't in 'active'.
        if highest == nil || probe.serialNumber > highest!.serialNumber {
            highest = probe
        }
        guard let highestSerialProbe = highest else { return }
        
        // Find the lowest available ID using the usedIds
        guard let lowestAvailableId = ProbeID.allCases.first(where: { !usedIds.contains($0) }) else { return }
        guard highestSerialProbe.id != lowestAvailableId else { return }
        
        setProbeID(highestSerialProbe, id: lowestAvailableId) { _ in }
    }
    
    /// Returns list of gauges
    /// - returns: List of all known gauges.
    public func getGauges() -> [GrillGauge] {
        return Array(accessories.values).compactMap { accessory in
            return accessory as? GrillGauge
        }
    }

    /// Returns list of engines
    /// - returns: List of all known engines.
    public func getEngines() -> [Engine] {
        return Array(accessories.values).compactMap { accessory in
            return accessory as? Engine
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
            let request: NodeRequest?
            if accessory is Engine {
                request = NodeEngineReadLogsRequest(serialNumber: accessory.serialNumberString,
                                                    minSequence: minSequence,
                                                    maxSequence: maxSequence)
            } else {
                request = NodeGaugeReadLogsRequest(serialNumber: accessory.serialNumberString,
                                                   minSequence: minSequence,
                                                   maxSequence: maxSequence)
            }
            guard let request = request else { return }
            
            BleManager.shared.sendRequest(identifier: device.bleIdentifier, request: request)
        }
        else {
            // Send message to all nodes that have a route to the device
            let nodesConnectedToDevice = getNodesConnectedToDevice(identifier: accessory.serialNumberString)
            let request: NodeRequest?
            if accessory is Engine {
                request = NodeEngineReadLogsRequest(serialNumber: accessory.serialNumberString,
                                                    minSequence: minSequence,
                                                    maxSequence: maxSequence)
            } else {
                request = NodeGaugeReadLogsRequest(serialNumber: accessory.serialNumberString,
                                                   minSequence: minSequence,
                                                   maxSequence: maxSequence)
            }
            guard let request = request else { return }
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
    public func setProbeID(_ device: Device, id: ProbeID, completionHandler: @escaping (_ success: Bool) -> Void) {
        if let probe = device as? Probe, shouldSendMessageDirectlyTo(probe: probe) {
            let request = SetIDRequest(serialNumber: probe.serialNumber, id: id)
            sendDirectRequestWithSuccessHandler(probe, request: request, completionHandler: completionHandler)
        }
        else if let probe = device as? Probe {
            let request = NodeSetIDRequest(serialNumber: probe.serialNumber, id: id)
            sendNodeRequestWithSuccessHandler(probe, request: request, completionHandler: completionHandler)
        }
    }
    
    /// Set Probe Color on specified device.
    /// - parameter device: Device to set Color on
    /// - parameter ProbeColor: New Probe color
    /// - parameter completionHandler: Completion handler to be called operation is complete
    public func setProbeColor(_ device: Device,
                              color: ProbeColor,
                              completionHandler: @escaping (_ success: Bool) -> Void) {
        if let probe = device as? Probe, shouldSendMessageDirectlyTo(probe: probe) {
            let request = SetColorRequest(color: color)
            sendDirectRequestWithSuccessHandler(probe, request: request, completionHandler: completionHandler)
        }
        else if let probe = device as? Probe {
            let request = NodeSetColorRequest(serialNumber: probe.serialNumber, color: color)
            sendNodeRequestWithSuccessHandler(probe, request: request, completionHandler: completionHandler)
        }
    }
    
    /// Set probe power mode on a specified node
    /// - parameter probe: Probe to set the power mode on
    /// - parameter powerMode: new power mode
    /// - parameter completionHandler: Completion handler to be called once operation is complete
    @available(*, deprecated, message: "Use setProbePowerModeCommand(_:powerMode:completionHandler:) for cancellable MeatNet retry behavior.")
    public func setProbePowerMode(_ probe: Probe, powerMode: ProbePowerMode, completionHandler: @escaping (_ success: Bool) -> Void) {
        setProbePowerModeCommand(probe, powerMode: powerMode) { result in
            completionHandler(result == .success)
        }
    }

    @discardableResult
    public func setProbePowerModeCommand(_ probe: Probe, powerMode: ProbePowerMode, completionHandler: @escaping CommandCompletionHandler) -> CommandHandle? {
        if shouldSendMessageDirectlyTo(probe: probe) {
            let request = SetPowerModeRequest(serialNumber: probe.serialNumber, mode: powerMode)
            return sendDirectRequestWithCommandHandler(probe, request: request, completionHandler: completionHandler)
        }
        else {
            let request = NodeSetPowerModeRequest(serialNumber: probe.serialNumber, mode: powerMode)
            return sendNodeRequestWithCommandHandler(probe, request: request, completionHandler: completionHandler)
        }
    }
    
    // Set probe high low alarms
    /// - parameter probe: Probe to set the power mode on
    /// - parameter highAlarms: high alarms to set
    /// - parameter lowAlarms: low alarms to set
    /// - parameter completionHandler: Completion handler to be called once operation is complete
    @available(*, deprecated, message: "Use setProbeHighLowAlarmsCommand(_:highAlarms:lowAlarms:completionHandler:) for cancellable MeatNet retry behavior.")
    public func setProbeHighLowAlarms(_ probe: Probe, highAlarms: [AlarmStatus], lowAlarms: [AlarmStatus], completionHandler: @escaping (_ success: Bool) -> Void) {
        setProbeHighLowAlarmsCommand(probe, highAlarms: highAlarms, lowAlarms: lowAlarms) { result in
            completionHandler(result == .success)
        }
    }

    @discardableResult
    public func setProbeHighLowAlarmsCommand(_ probe: Probe, highAlarms: [AlarmStatus], lowAlarms: [AlarmStatus], completionHandler: @escaping CommandCompletionHandler) -> CommandHandle? {
        if shouldSendMessageDirectlyTo(probe: probe) {
            let request = SetHighLowAlarmsRequest(serialNumber: probe.serialNumber,
                                                  highAlarms: highAlarms,
                                                  lowAlarms: lowAlarms)
            return sendDirectRequestWithCommandHandler(probe, request: request, completionHandler: completionHandler)
        }
        else {
            let request = NodeSetProbeHighLowAlarmRequest(serialNumber: probe.serialNumber,
                                                          highAlarms: highAlarms,
                                                          lowAlarms: lowAlarms)
            return sendNodeRequestWithCommandHandler(probe,
                                                     request: request,
                                                     completionHandler: completionHandler)
        }
    }
    
    // Silence alarms on all devices
    public func silenceAllAlarms() {
        let meatNetNodes = getMeatnetNodes()
        let probes = getProbes()
        
        let silenceAlarmRequest = NodeSilenceAlarmsRequest(global: true)
        
        for node in meatNetNodes {
            guard node.connectionState == .connected else {
                continue
            }
            
            sendNodeRequest(node: node, request: silenceAlarmRequest)
        }
        
        for probe in probes {
            guard probe.connectionState == .connected else {
                continue
            }
            
            let request = SilenceAlarmsRequest()
            BleManager.shared.sendRequest(identifier: probe.bleIdentifier,
                                          request: request)
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
    @available(*, deprecated, message: "Use setRemovalPredictionCommand(_:removalTemperatureC:completionHandler:) for cancellable MeatNet retry behavior.")
    public func setRemovalPrediction(_ probe: Probe,
                                     removalTemperatureC: Double,
                                     completionHandler: @escaping (_ success: Bool) -> Void) {
        setRemovalPredictionCommand(probe, removalTemperatureC: removalTemperatureC) { result in
            completionHandler(result == .success)
        }
    }

    @discardableResult
    public func setRemovalPredictionCommand(_ probe: Probe,
                                            removalTemperatureC: Double,
                                            completionHandler: @escaping CommandCompletionHandler) -> CommandHandle? {
        guard removalTemperatureC < Constants.MAXIMUM_PREDICTION_SETPOINT_CELSIUS,
              removalTemperatureC > Constants.MINIMUM_PREDICTION_SETPOINT_CELSIUS else {
            completionHandler(.failure)
            return nil
        }
        
        if shouldSendMessageDirectlyTo(probe: probe) {
            // If the best route is directly to the Probe, send it that way.
            let request = SetPredictionRequest(serialNumber: probe.serialNumber,
                                               setPointCelsius: removalTemperatureC,
                                               mode: .timeToRemoval)
            return sendDirectRequestWithCommandHandler(probe, request: request, completionHandler: completionHandler)
        }
        else {
            // Send message to all nodes that have a route to the probe
            let request = NodeSetPredictionRequest(serialNumber: probe.serialNumber,
                                                   setPointCelsius: removalTemperatureC,
                                                   mode: .timeToRemoval)
            return sendNodeRequestWithCommandHandler(probe, request: request, completionHandler: completionHandler)
        }
    }
    
    
    /// Sends a request to the device to set the prediction mode to none, stopping any active prediction.
    ///
    /// - parameter probe: Probe to cancel prediction on
    /// - parameter completionHandler: Completion handler to be called operation is complete
    @available(*, deprecated, message: "Use cancelPredictionCommand(_:completionHandler:) for cancellable MeatNet retry behavior.")
    public func cancelPrediction(_ probe: Probe, completionHandler: @escaping (_ success: Bool) -> Void) {
        cancelPredictionCommand(probe) { result in
            completionHandler(result == .success)
        }
    }

    @discardableResult
    public func cancelPredictionCommand(_ probe: Probe, completionHandler: @escaping CommandCompletionHandler) -> CommandHandle? {
        
        if shouldSendMessageDirectlyTo(probe: probe) {
            // If the best route is directly to the Probe, send it that way.
            let request = SetPredictionRequest(serialNumber: probe.serialNumber,
                                               setPointCelsius: 0.0,
                                               mode: .none)
            return sendDirectRequestWithCommandHandler(probe, request: request, completionHandler: completionHandler)
        }
        else {
            // Send message to all nodes that have a route to the probe
            let request = NodeSetPredictionRequest(serialNumber: probe.serialNumber,
                                                   setPointCelsius: 0.0,
                                                   mode: .none)
            return sendNodeRequestWithCommandHandler(probe, request: request, completionHandler: completionHandler)
        }
    }
    
    /// Sends a request to the device to configure Food Safe
    ///
    /// - parameter probe: Probe to cancel prediction on
    /// - parameter foodSafeData: Food Safe data
    /// - parameter completionHandler: Completion handler to be called operation is complete
    @available(*, deprecated, message: "Use configureFoodSafeCommand(_:foodSafeData:completionHandler:) for cancellable MeatNet retry behavior.")
    public func configureFoodSafe(_ probe: Probe,
                            foodSafeData: FoodSafeData,
                            completionHandler: @escaping (_ success: Bool) -> Void) {
        configureFoodSafeCommand(probe, foodSafeData: foodSafeData) { result in
            completionHandler(result == .success)
        }
    }

    @discardableResult
    public func configureFoodSafeCommand(_ probe: Probe,
                                         foodSafeData: FoodSafeData,
                                         completionHandler: @escaping CommandCompletionHandler) -> CommandHandle? {
        
        if shouldSendMessageDirectlyTo(probe: probe) {
            // If the best route is directly to the Probe, send it that way.
            let request = ConfigureFoodSafeRequest(serialNumber: probe.serialNumber, foodSafeData: foodSafeData)
            return sendDirectRequestWithCommandHandler(probe, request: request, completionHandler: completionHandler)
        }
        else {
            // Send message to all nodes that have a route to the probe
            let request = NodeConfigureFoodSafeRequest(serialNumber: probe.serialNumber,
                                                       foodSafeData: foodSafeData)
            return sendNodeRequestWithCommandHandler(probe, request: request, completionHandler: completionHandler)
        }
    }
    
    /// Sends a request to the device to reset Food Safe
    ///
    /// - parameter probe: Probe to cancel prediction on
    /// - parameter completionHandler: Completion handler to be called operation is complete
    @available(*, deprecated, message: "Use resetFoodSafeCommand(_:completionHandler:) for cancellable MeatNet retry behavior.")
    public func resetFoodSafe(_ probe: Probe,
                            completionHandler: @escaping (_ success: Bool) -> Void) {
        resetFoodSafeCommand(probe) { result in
            completionHandler(result == .success)
        }
    }

    @discardableResult
    public func resetFoodSafeCommand(_ probe: Probe,
                                     completionHandler: @escaping CommandCompletionHandler) -> CommandHandle? {
        
        if shouldSendMessageDirectlyTo(probe: probe) {
            // If the best route is directly to the Probe, send it that way.
            let request = ResetFoodSafeRequest(serialNumber: probe.serialNumber)
            return sendDirectRequestWithCommandHandler(probe, request: request, completionHandler: completionHandler)
        }
        else {
            // Send message to all nodes that have a route to the probe
            let request = NodeResetFoodSafeRequest(serialNumber: probe.serialNumber)
            return sendNodeRequestWithCommandHandler(probe, request: request, completionHandler: completionHandler)
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
                                        completionHandler: @escaping (_ success: Bool, _ overTemperature: Bool) -> Void) {
        // TODO - Send request via Node.
        
        let request = ReadOverTemperatureRequest()
        
        if let device = device as? Probe, let bleIdentifier = device.bleIdentifier {
            commandCoordinator.addReadOverTemperatureHandler(identifier: bleIdentifier, completionHandler: completionHandler)
            BleManager.shared.sendRequest(identifier: bleIdentifier, request: request)
        }
    }
    
    /// Sends a request to reset the current session for a probe
    ///  - Parameter probe: The probe to reset
    ///  - parameter completionHandler: Completion handler to be called operation is complete
    @available(*, deprecated, message: "Use resetSessionCommand(_:completionHandler:) for cancellable MeatNet retry behavior.")
    public func resetSession(_ probe: Probe, completionHandler: @escaping (_ success: Bool) -> Void) {
        resetSessionCommand(probe) { result in
            completionHandler(result == .success)
        }
    }

    @discardableResult
    public func resetSessionCommand(_ probe: Probe, completionHandler: @escaping CommandCompletionHandler) -> CommandHandle? {
        if shouldSendMessageDirectlyTo(probe: probe) {
            let request = ResetSessionRequest()
            return sendDirectRequestWithCommandHandler(probe, request: request, completionHandler: completionHandler)
        }
        else {
            let request = NodeResetSessionRequest(serialNumber: probe.serialNumber)
            return sendNodeRequestWithCommandHandler(probe, request: request, completionHandler: completionHandler)
        }
    }
    
    /// Sends a request to set high low alarms for a device
    ///
    /// - parameter device: the device to update with high low alarms
    @available(*, deprecated, message: "Use setHighLowAlarmsCommand(_:status:completionHandler:) for cancellable MeatNet retry behavior.")
    public func setHighLowAlarms(_ device: MeatNetNode,
                                 status: HighLowAlarmStatus,
                                 completionHandler: @escaping (_ success: Bool) -> Void) {
        setHighLowAlarmsCommand(device, status: status) { result in
            completionHandler(result == .success)
        }
    }

    @discardableResult
    public func setHighLowAlarmsCommand(_ device: MeatNetNode,
                                        status: HighLowAlarmStatus,
                                        completionHandler: @escaping CommandCompletionHandler) -> CommandHandle? {
        // cannot send request if no serial number present
        guard let serialNumberString = device.accessory?.serialNumberString,
              let request = SetNodeHighLowAlarmRequest(serialNumber: serialNumberString, status: status) else {
            completionHandler(.failure)
            return nil
        }
       
        return sendNodeRequestWithCommandHandler(device, request: request, completionHandler: completionHandler)
    }

    /// Sends a request to set an engine's control device to a probe.
    ///
    /// - parameter device: the node advertising the engine accessory
    /// - parameter probeSerialNumber: probe serial number to set as control device
    /// - parameter completionHandler: completion handler to be called once operation is complete
    @available(*, deprecated, message: "Use setEngineControlDeviceCommand(_:probeSerialNumber:completionHandler:) for cancellable MeatNet retry behavior.")
    public func setEngineControlDevice(_ device: MeatNetNode,
                                       probeSerialNumber: UInt32,
                                       completionHandler: @escaping (_ success: Bool) -> Void) {
        setEngineControlDeviceCommand(device, probeSerialNumber: probeSerialNumber) { result in
            completionHandler(result == .success)
        }
    }

    @discardableResult
    public func setEngineControlDeviceCommand(_ device: MeatNetNode,
                                              probeSerialNumber: UInt32,
                                              completionHandler: @escaping CommandCompletionHandler) -> CommandHandle? {
        guard let serialNumberString = device.accessory?.serialNumberString,
              let request = NodeSetEngineControlDeviceRequest(serialNumber: serialNumberString,
                                                              probeSerialNumber: probeSerialNumber) else {
            completionHandler(.failure)
            return nil
        }

        return sendNodeRequestWithCommandHandler(device, request: request, completionHandler: completionHandler)
        
    }

    /// Sends a request to set an engine's control device to a gauge.
    ///
    /// - parameter device: the node advertising the engine accessory
    /// - parameter gaugeSerialNumber: gauge serial number to set as control device
    /// - parameter completionHandler: completion handler to be called once operation is complete
    @available(*, deprecated, message: "Use setEngineControlDeviceCommand(_:gaugeSerialNumber:completionHandler:) for cancellable MeatNet retry behavior.")
    public func setEngineControlDevice(_ device: MeatNetNode,
                                       gaugeSerialNumber: String,
                                       completionHandler: @escaping (_ success: Bool) -> Void) {
        setEngineControlDeviceCommand(device, gaugeSerialNumber: gaugeSerialNumber) { result in
            completionHandler(result == .success)
        }
    }

    @discardableResult
    public func setEngineControlDeviceCommand(_ device: MeatNetNode,
                                              gaugeSerialNumber: String,
                                              completionHandler: @escaping CommandCompletionHandler) -> CommandHandle? {
        guard let serialNumberString = device.accessory?.serialNumberString,
              let request = NodeSetEngineControlDeviceRequest(serialNumber: serialNumberString,
                                                              gaugeSerialNumber: gaugeSerialNumber) else {
            completionHandler(.failure)
            return nil
        }

        return sendNodeRequestWithCommandHandler(device, request: request, completionHandler: completionHandler)
    }

    /// Sends a request to set an engine's target temperature.
    ///
    /// - parameter device: the node advertising the engine accessory
    /// - parameter temperatureCelsius: target temperature in Celsius
    /// - parameter completionHandler: completion handler to be called once operation is complete
    @available(*, deprecated, message: "Use setEngineTargetTemperatureCommand(_:temperatureCelsius:completionHandler:) for cancellable MeatNet retry behavior.")
    public func setEngineTargetTemperature(_ device: MeatNetNode,
                                           temperatureCelsius: Double,
                                           completionHandler: @escaping (_ success: Bool) -> Void) {
        setEngineTargetTemperatureCommand(device, temperatureCelsius: temperatureCelsius) { result in
            completionHandler(result == .success)
        }
    }

    @discardableResult
    public func setEngineTargetTemperatureCommand(_ device: MeatNetNode,
                                                  temperatureCelsius: Double,
                                                  completionHandler: @escaping CommandCompletionHandler) -> CommandHandle? {
        guard let serialNumberString = device.accessory?.serialNumberString,
              let request = NodeSetEngineTargetTemperatureRequest(serialNumber: serialNumberString,
                                                                  temperatureCelsius: temperatureCelsius) else {
            completionHandler(.failure)
            return nil
        }

        return sendNodeRequestWithCommandHandler(device, request: request, completionHandler: completionHandler)
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
                                   completionHandler: @escaping (_ success: Bool) -> Void) {
        sendDirectRequestWithCommandHandler(probe, request: request) { result in
            completionHandler(result == .success)
        }
    }

    @discardableResult
    private func sendDirectRequestWithCommandHandler(_ probe: Probe,
                                                     request: Request,
                                                     completionHandler: @escaping CommandCompletionHandler) -> CommandHandle? {
        guard let identifier = probe.bleIdentifier else {
            completionHandler(.failure)
            return nil
        }

        return commandCoordinator.addDirectCommandHandler(identifier: identifier,
                                                       request: request,
                                                       send: {
            BleManager.shared.sendRequest(identifier: identifier, request: request)
        },
                                                       completionHandler: completionHandler)
    }
    
    private func sendNodeRequestWithSuccessHandler(_ probe: Probe,
                                   request: NodeRequest,
                                   completionHandler: @escaping (_ success: Bool) -> Void) {
        sendNodeRequestWithCommandHandler(probe, request: request) { result in
            completionHandler(result == .success)
        }
    }

    @discardableResult
    private func sendNodeRequestWithCommandHandler(_ probe: Probe,
                                                   request: NodeRequest,
                                                   completionHandler: @escaping CommandCompletionHandler) -> CommandHandle {
        return commandCoordinator.addNodeCommandHandler(request: request,
                                                     send: { [weak self, weak probe] in
            guard let self,
                  let probe else { return }

            let nodesConnectedToProbe = self.getNodesConnectedToDevice(identifier: probe.uniqueIdentifier)
            BleManager.shared.sendRequestToNodes(nodesConnectedToProbe, request: request)
        },
                                                     completionHandler: completionHandler)
    }
    
    public func sendNodeRequest(node: MeatNetNode,
                                           request: NodeRequest) {
        BleManager.shared.sendRequestToNodes([node], request: request)
    }
    
    private func sendNodeRequestWithSuccessHandler(_ device: MeatNetNode,
                                   request: NodeRequest,
                                   completionHandler: @escaping (_ success: Bool) -> Void) {
        sendNodeRequestWithCommandHandler(device, request: request) { result in
            completionHandler(result == .success)
        }
    }

    @discardableResult
    private func sendNodeRequestWithCommandHandler(_ device: MeatNetNode,
                                                   request: NodeRequest,
                                                   completionHandler: @escaping CommandCompletionHandler) -> CommandHandle {
        return commandCoordinator.addNodeCommandHandler(request: request,
                                                     send: { [weak self, weak device] in
            guard let self,
                  let device else { return }

            if self.shouldSendMessageDirectlyTo(device: device) {
                BleManager.shared.sendRequestToNodes([device], request: request)
            }
            else {
                let nodesConnectedToDevice = self.getNodesConnectedToDevice(identifier: device.uniqueIdentifier)
                BleManager.shared.sendRequestToNodes(nodesConnectedToDevice, request: request)
            }
        },
                                                     completionHandler: completionHandler)
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
        
        if let probe = device as? Probe {
            observeProbeIdChanges(probe)
        }
    }
    
    func didFailToConnectTo(identifier: UUID) {
        guard let device = findDeviceByBleIdentifier(bleIdentifier: identifier) else { return }
        
        device.updateConnectionState(.failed)
    }
    
    func didDisconnectFrom(identifier: UUID) {
        guard let device = findDeviceByBleIdentifier(bleIdentifier: identifier) else { return }
        
        device.updateConnectionState(.disconnected)
        
        // Clear any pending message handlers
        commandCoordinator.clearCommandsForDevice(identifier)
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
        let previousId = probe.id
        probe.updateProbeStatus(deviceStatus: status)
        commandCoordinator.confirmCommandStatus(serialNumber: String(probe.serialNumber), status: status)

        if previousId != probe.id {
            resolveProbeIdCollision(for: probe, incomingId: probe.id)
        }
        
        connectionManager.receivedStatusFor(probe, node: nil)
    }
    
    private func updateDeviceWithNodeStatus(serialNumber: UInt32, status: ProbeStatus, hopCount: HopCount, node: MeatNetNode) {
        guard let probe = findProbeBySerialNumber(serialNumber: serialNumber) else { return }

        let previousId = probe.id
        probe.updateProbeStatus(deviceStatus: status, hopCount: hopCount)
        commandCoordinator.confirmCommandStatus(serialNumber: String(serialNumber), status: status)

        if previousId != probe.id {
            resolveProbeIdCollision(for: probe, incomingId: probe.id)
        }
        
        connectionManager.receivedStatusFor(probe, node: node)
    }
    
    private func updateDeviceWithNodeStatus(serialNumber: String, status: DeviceStatus, hopCount: HopCount, node: MeatNetNode) {
        // accesory already created
        if let accessory = findAccesoryBySerialNumber(serialNumber: serialNumber) {
            if let parent = accessory.parent as? MeatNetNode {
                parent.updateDeviceStatus(deviceStatus: status, hopCount: hopCount)
            }
            else {
                accessory.updateDeviceStatus(deviceStatus: status, hopCount: hopCount)
            }
            
            connectionManager.receivedStatusFor(accessory, node: node)
        }
        else if let device = self.findDeviceBySerialNumber(serialNumber: serialNumber) as? MeatNetNode {
            device.updateDeviceStatus(deviceStatus: status, hopCount: hopCount)
            connectionManager.receivedStatusFor(device, node: node)
        }
        else if let status = status as? GaugeStatus {
            let gauge = GrillGauge(status: status,
                                   hopCount: hopCount)
            addAccessory(accessory: gauge)
            
            connectionManager.receivedStatusFor(gauge, node: node)
        }
        else if let status = status as? EngineStatus {
            let engine = Engine(status: status,
                                hopCount: hopCount)
            addAccessory(accessory: engine)

            connectionManager.receivedStatusFor(engine, node: node)
        }

        commandCoordinator.confirmCommandStatus(serialNumber: serialNumber, status: status)
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
            let uniqueIdentifier = Probe.serialNumberToString(advertising.serialNumber)
            if let probe = devices[uniqueIdentifier] as? Probe {
                // If we already have an entry for this Probe, update its information.
                probe.updateWithAdvertising(advertising, isConnectable: isConnectable, RSSI: rssi, bleIdentifier: identifier)
                
                // Ensure observing id changes for existing probe
                observeProbeIdChanges(probe)
                
                foundProbe = probe
            } else {
                // If we don't yet have an entry for this Probe, create one.
                let device = Probe(advertising, isConnectable: isConnectable, RSSI: rssi, identifier: identifier)
                addDevice(device: device)
                
                // Ensure observing id changes for new probe
                observeProbeIdChanges(device)
                
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
            if !connectionManager.meatNetEnabled {
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
            
            if let advertising = advertising as? ProbeAdvertisingData {
                // Update the probe associated with this advertising data
                let probe = updateProbeWithAdvertising(advertising: advertising, isConnectable: nil, rssi: nil, identifier: nil)
                
                // Notify connection manager
                connectionManager.receivedDeviceAdvertising(probe, from: meatnetNode)
                
                // Track that data was recieved for probe on node
                meatnetNode.dataReceivedFromDevice(probe)
            }
        case .gauge, .engine:
            let meatNetNode: MeatNetNode
            
            // Update gauge if it is in device list
            if let node = devices[identifier.uuidString] as? MeatNetNode {
                meatNetNode = node
                node.updateWithAdvertising(advertising, isConnectable: isConnectable, RSSI: rssi)
            }
            // Create node and add to device list
            else {
                meatNetNode = MeatNetNode(advertising, isConnectable: isConnectable, RSSI: rssi, identifier: identifier)
                
                addDevice(device: meatNetNode)
            }
            
            switch advertising.type {
            case .gauge:
                if let existingGauge = meatNetNode.accessory as? GrillGauge {
                    existingGauge.updateWithAdvertising(advertising)
                }
                else if let accessory = self.accessories[advertising.serialNumberString] as? GrillGauge {
                    meatNetNode.accessory = accessory
                    accessory.setParent(meatNetNode)
                    accessory.updateWithAdvertising(advertising)
                }
                else {
                    let gauge = GrillGauge(parent: meatNetNode, advertising: advertising)
                    meatNetNode.accessory = gauge
                    
                    addAccessory(accessory: gauge)
                }
            case .engine:
                if let existingEngine = meatNetNode.accessory as? Engine {
                    existingEngine.updateWithAdvertising(advertising)
                }
                else if let accessory = self.accessories[advertising.serialNumberString] as? Engine {
                    meatNetNode.accessory = accessory
                    accessory.setParent(meatNetNode)
                    accessory.updateWithAdvertising(advertising)
                }
                else {
                    let engine = Engine(parent: meatNetNode, advertising: advertising)
                    meatNetNode.accessory = engine
                    
                    addAccessory(accessory: engine)
                }
            default:
                print("unhandled accessory")
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
        
        if let probe = devices[Probe.serialNumberToString(serialNumber)] as? Probe {
            // Probes are stored using their serial number encoded as a String as their key.
            foundProbe = probe
        }
        
        return foundProbe
    }
    
    private func findAccesoryBySerialNumber(serialNumber: String) -> (any Accessory)? {
        return self.accessories[serialNumber]
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
                commandCoordinator.callReadOverTemperatureHandler(identifier: identifier, response: readOverTemperatureResponse)
            }
        // Messages with success completion handlers
        case .configureFoodSafe, 
                .resetFoodSafe,
                .setColor,
                .setPowerMode,
                .setID,
                .setPrediction,
                .setHighLowAlarms,
                .silenceAlarms,
                .resetSession:
                commandCoordinator.callDirectCommandHandler(identifier: identifier, response: response)
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
        else if let deviceParent = findDeviceByBleIdentifier(bleIdentifier: identifier) as? MeatNetNode, let accessory = deviceParent.accessory {
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
            if let readGaugeLogsResponse = response as? NodeGaugeReadLogsResponse,
               let accessory = findAccesoryBySerialNumber(serialNumber: readGaugeLogsResponse.gaugeSerialNumber) as? GrillGauge {
                accessory.processLogResponse(logResponse: readGaugeLogsResponse)
            }
        case .engineLog:
            if let readEngineLogsResponse = response as? NodeEngineReadLogsResponse,
               let accessory = findAccesoryBySerialNumber(serialNumber: readEngineLogsResponse.engineSerialNumber) as? Engine {
                accessory.processLogResponse(logResponse: readEngineLogsResponse)
            }
        case .getFeatureFlags:
            if let featureFlagsResponse = response as? NodeReadFeatureFlagsResponse,
               let device = findDeviceBySerialNumber(serialNumber: featureFlagsResponse.nodeSerialNumber) as? MeatNetNode {
                device.updateFeatureFlags(featureFlagsResponse.flags)
            }
        case .setPrediction, .configureFoodSafe, .resetFoodSafe, .setPowerMode, .resetSession, .setHighLowAlarm, .setProbeHighLowAlarm, .silenceAlarms, .setEngineControlDevice, .setEngineTargetTemperature:
            commandCoordinator.callNodeCommandHandler(response: response)
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
            if let gaugeStatus = statusRequest.gaugeStatus {
                if let node = findDeviceByBleIdentifier(bleIdentifier: identifier) as? MeatNetNode,
                   let hopCount = statusRequest.hopCount {
                    // Update the Gauge based on the information that was received
                    
                    updateDeviceWithNodeStatus(serialNumber: statusRequest.serialNumber,
                                               status: gaugeStatus,
                                               hopCount: hopCount,
                                               node: node)
                }
                // if gauge status has been repeated across meatnet, node may not have been created yet.
                else {
                    let meatNetNode = MeatNetNode(isConnectable: false,
                                                  RSSI: 0,
                                                  identifier: UUID())
                    
                    self.addDevice(device: meatNetNode)
                    
                    let gauge = GrillGauge(parent: meatNetNode,
                                           status: gaugeStatus,
                                           hopCount: statusRequest.hopCount)
                    addAccessory(accessory: gauge)
                }
            }
        }
        else if let statusRequest = request as? NodeEngineStatusRequest {
            if let engineStatus = statusRequest.engineStatus {
                if let node = findDeviceByBleIdentifier(bleIdentifier: identifier) as? MeatNetNode,
                   let hopCount = statusRequest.hopCount {
                    updateDeviceWithNodeStatus(serialNumber: statusRequest.serialNumber,
                                               status: engineStatus,
                                               hopCount: hopCount,
                                               node: node)
                }
                else {
                    let meatNetNode = MeatNetNode(isConnectable: false,
                                                  RSSI: 0,
                                                  identifier: UUID())

                    self.addDevice(device: meatNetNode)

                    let engine = Engine(parent: meatNetNode,
                                        status: engineStatus,
                                        hopCount: statusRequest.hopCount)
                    addAccessory(accessory: engine)
                }
            }
        }
        else if let silenceAlarmRequest = request as? NodeSilenceAlarmsRequest {
            meatNetActionDelegate?.silenceAlarms(global: silenceAlarmRequest.global,
                                                 productType: silenceAlarmRequest.productType,
                                                 probeSerialNumber: silenceAlarmRequest.probeSerialNumber,
                                                 nodeSerialNumber: silenceAlarmRequest.nodeSerialNumber)
        }
        else if let heartBeatRequest = request as? NodeHeartbeatRequest {
            // TODO handle heartBeatRequest
        }
        else if let request = request as? NodeCustomRequest {
            deviceResponseHandler?.handleRequest(identifier: identifier, request: request)
        }
    }
    
}
