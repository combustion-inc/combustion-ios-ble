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


/// Singleton that provides list of detected Devices
/// (either via Bluetooth or from a list in the Cloud)
public class DeviceManager : ObservableObject {
    /// Singleton accessor for class
    public static let shared = DeviceManager()
    
    /// Dictionary of discovered devices.
    /// key = string representation of device identifier (UUID)
    @Published public private(set) var devices : [String: Device] = [String: Device]()
    
    
    /// Dictionary of discovered probes (subset of devices).
    /// key = string representation of device identifier (UUID)
    public var probes : [String: Probe] {
        get {
            devices.filter { $0.value is Probe }.mapValues { $0 as! Probe }
        }
        set {
            devices = newValue
        }
    }
    
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
    public func setProbeID(_ device: Device, id: ProbeID) {
        let request = SetIDRequest(id: id)
        BleManager.shared.sendRequest(identifier: device.identifier, request: request)
    }
    
    /// Set Probe Color on specified device.
    /// - parameter device: Device to set Color on
    /// - parameter ProbeColor: New Probe color
    public func setProbeColor(_ device: Device, color: ProbeColor) {
        let request = SetColorRequest(color: color)
        BleManager.shared.sendRequest(identifier: device.identifier, request: request)
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
    }
    
    func updateDeviceWithStatus(identifier: UUID, status: DeviceStatus) {
        if let probe = devices[identifier.uuidString] as? Probe {
            probe.updateProbeStatus(deviceStatus: status)
        }
    }
    
    func updateDeviceWithLogResponse(identifier: UUID, logResponse: LogResponse) {
        if let probe = devices[identifier.uuidString] as? Probe {
            probe.processLogResponse(logResponse: logResponse)
        }
    }
    
    func updateDeviceWithAdvertising(advertising: AdvertisingData, rssi: NSNumber, identifier: UUID) {
        if devices[identifier.uuidString] != nil {
            if let probe = devices[identifier.uuidString] as? Probe {
                probe.updateWithAdvertising(advertising, RSSI: rssi)
            }
        }
        else {
            let device = Probe(advertising, RSSI: rssi, identifier: identifier)
            addDevice(device: device)
        }
    }
    
    func updateDeviceFwVersion(identifier: UUID, fwVersion: String) {
        if let device = devices[identifier.uuidString]  {
            device.firmareVersion = fwVersion
        }
    }
}
