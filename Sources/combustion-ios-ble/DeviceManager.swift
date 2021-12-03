//
//  DeviceManager.swift
//  Needle
//  Singleton that provides list of detected Devices (either via Bluetooth or from a list in the Cloud)
//
//  Created by Jason Machacek on 2/5/20.
//  Copyright © 2020 Jason Machacek. All rights reserved.
//

import Foundation
import SwiftUI


class DeviceManager : ObservableObject {
    /// Singleton accessor for class
    static let shared = DeviceManager()
    
    /// Dictionary of discovered devices.
    /// key = string representation of device identifier (UUID)
    @Published var devices : [String: Device] = [String: Device]()
    
    /// Private initializer to enforce singleton
    private init() {
        // Force instantiation of BleManager
        BleManager.shared.begin()
        BleManager.shared.delegate = self
        
        // Start a timer to set stale flag on devices
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] _ in
            for key in devices.keys {
                devices[key]?.updateDeviceStale()
            }
        }
    }
    
    
    /// Adds a device to the local list.
    /// - param device: Add device to list of known devices.
    private func addDevice(device: Device) {
        devices[device.id] = device
    }
    
    /// Removes all found devices from the list.
    func clearDevices() {
        devices.removeAll(keepingCapacity: false)
    }
    
    /// Returns list of devices.
    /// - return List of all known devices.
    func getDevices() -> [Device] {
        return Array(devices.values)
    }
    
    /// Returns the nearest device.
    /// - return Nearest device, if any.
    func getNearestDevice() -> Device? {
        return getDevices().max{ $0.rssi < $1.rssi }
    }
    
    func connectToDevice(_ device: Device) {
        // print("Connect to : \(device.serialNumber)")
        BleManager.shared.connect(id: device.id)
    }
    
    func disconnectFromDevice(_ device: Device) {
        // print("Disconnect from : \(device.serialNumber)")
        BleManager.shared.disconnect(id: device.id)
    }
    
    /// Request log messages from the specified device.
    /// - param device: Device from which to request messages
    /// - param minSequence: Minimum sequence number to request
    /// - param maxSequence: Maximum sequence number to request
    func requestLogsFrom(_ device: Device, minSequence: UInt32, maxSequence: UInt32) {
        let request = LogRequest(minSequence: minSequence,
                                 maxSequence: maxSequence)
        BleManager.shared.sendRequest(id: device.id, request: request)
    }
}

extension DeviceManager : BleManagerDelegate {
    func didConnectTo(id: UUID) {
        guard let _ = devices[id.uuidString] else { return }
        // print("Connected to : \(device.id)")
        devices[id.uuidString]?.updateConnectionState(.connected)
    }
    
    func didFailToConnectTo(id: UUID) {
        guard let _ = devices[id.uuidString] else { return }
        // print("Failed to connect to : \(device.id)")
        devices[id.uuidString]?.updateConnectionState(.failed)
    }
    
    func didDisconnectFrom(id: UUID) {
        guard let _ = devices[id.uuidString] else { return }
        // print("Disconnected from : \(device.id)")
        devices[id.uuidString]?.updateConnectionState(.disconnected)
    }
    
    func updateDeviceWithStatus(id: UUID, status: DeviceStatus) {
        // print("New device status ", status)
        devices[id.uuidString]?.updateDeviceStatus(deviceStatus: status)
    }
    
    func updateDeviceWithLogResponse(id: UUID, logResponse: LogResponse) {
        devices[id.uuidString]?.processLogResponse(logResponse: logResponse)
    }
    
    func updateDeviceWithAdvertising(advertising: AdvertisingData, rssi: NSNumber, id: UUID) {
        if devices[id.uuidString] != nil {
            devices[id.uuidString]?.updateWithAdvertising(advertising, RSSI: rssi)
            // print("Updated device: \(devices[id.uuidString]?.serialNumber) : rssi = \(rssi)")
        }
        else {
            // print("Adding New Device: \(advertising.serialNumber)")
            let device = Device(advertising, RSSI: rssi, id: id)
            addDevice(device: device)
        }
    }
}
