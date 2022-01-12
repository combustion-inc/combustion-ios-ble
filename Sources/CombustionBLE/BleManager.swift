//  BleManager.swift
//  Singleton manager for app's BLE interface.

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
import CoreBluetooth

protocol BleManagerDelegate: AnyObject {
    func didConnectTo(id: UUID)
    func didFailToConnectTo(id: UUID)
    func didDisconnectFrom(id: UUID)
    func updateDeviceWithStatus(id: UUID, status: DeviceStatus)
    func updateDeviceWithAdvertising(advertising: AdvertisingData, rssi: NSNumber, id: UUID)
    func updateDeviceWithLogResponse(id: UUID, logResponse: LogResponse)
    func updateDeviceFwVersion(id: UUID, fwVersion: String)
}

/// Manages Core Bluetooth interface with the rest of the app.
class BleManager : NSObject {
    /// Singleton accessor for class
    static let shared = BleManager()
    
    weak var delegate: BleManagerDelegate?
    
    private(set) var peripherals = Set<CBPeripheral>()
    
    private var uartCharacteristics: [String: CBCharacteristic] = [:]
    private var deviceStatusCharacteristics: [String: CBCharacteristic] = [:]
    
    private var manager: CBCentralManager!
    
    private enum Constants {
        static let DEVICE_INFO_SERVICE  = CBUUID(string: "180a")
        static let NEEDLE_SERVICE       = CBUUID(string: "00000100-CAAB-3792-3D44-97AE51C1407A")
        static let UART_SERVICE         = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
        
        static let FW_VERSION_CHAR      = CBUUID(string: "2a26")
        static let DEVICE_STATUS_CHAR   = CBUUID(string: "00000101-CAAB-3792-3D44-97AE51C1407A")
        static let UART_RX_CHAR         = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
        static let UART_TX_CHAR         = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    }
    
    /// Private initializer to enforce singleton
    private override init() {
        super.init()
        
        manager = CBCentralManager(delegate: self, queue: nil)
    }
    
    private func startScanning() {
        manager.scanForPeripherals(withServices: [Constants.NEEDLE_SERVICE],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }
    
    func sendRequest(id: String, request: Request) {
        if let connectionPeripheral = getConnectedPeripheral(id: id), let uartChar = uartCharacteristics[id] {
            connectionPeripheral.writeValue(request.data, for: uartChar, type: .withoutResponse)
        }
    }
    
    private func getConnectedPeripheral(id: String) -> CBPeripheral? {
        let uuid = UUID(uuidString: id)
        let devicePeripherals = peripherals.filter { $0.identifier == uuid }
        guard !devicePeripherals.isEmpty else {
            // print("Failed to find peripherals")
            return nil
        }
        
        if let connectedPeripheral = devicePeripherals.first(where: { $0.state == .connected }) {
            return connectedPeripheral
        }
        
        // print("Failed to find connection")
        return nil
    }
}

// MARK: - CBCantralManagerDelegate

extension BleManager: CBCentralManagerDelegate{
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            // print("\(#function): poweredOn")
            startScanning()
        default:
            // print("\(#function): default")
            break
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String : Any], rssi RSSI: NSNumber) {
        
        let manufatureData: Data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data ?? Data()

        if let advData = AdvertisingData(fromData: manufatureData) {
            // For now, only add probes.
            if advData.type == .PROBE {

                // Store peripheral reference for later use
                peripherals.insert(peripheral)

                delegate?.updateDeviceWithAdvertising(advertising: advData, rssi: RSSI, id: peripheral.identifier)
            } else {
                // print("Ignoring device with type \(advData.type)")
            }
        }
    }
    
    /// Connect to device with the specified name.
    public func connect(id: String) {
        let uuid = UUID(uuidString: id)
        let devicePeripherals = peripherals.filter { $0.identifier == uuid }
        guard !devicePeripherals.isEmpty else {
            print("Failed to find peripheral")
            return
        }
        
        for peripheral in devicePeripherals {
            // print("Connecting to peripheral: \(peripheral.name) : \(peripheral.identifier)")
            manager.connect(peripheral, options: nil)
        }
    }
    
    /// Disconnect from device with the specified name.
    public func disconnect(id: String) {
        if let connectedPeripheral = getConnectedPeripheral(id: id) {
            manager.cancelPeripheralConnection(connectedPeripheral)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // print("\(#function)")

        peripheral.delegate = self
        peripheral.discoverServices(nil)
        
        delegate?.didConnectTo(id: peripheral.identifier)
    }
    
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        // print("\(#function)")
        
        delegate?.didFailToConnectTo(id: peripheral.identifier)
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // print("\(#function)")
        
        delegate?.didDisconnectFrom(id: peripheral.identifier)
    }
    
}


// MARK: - CBPeripheralDelegate

extension BleManager: CBPeripheralDelegate {
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        // print("\(#function)")
        guard let services = peripheral.services else { return }
        
        for service in services {
            // print("discovered service : \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            // print("discovered characteristic : \(characteristic.uuid) : \(characteristic.uuid.uuidString) :\(characteristic.descriptors)")
            
            if(characteristic.uuid == Constants.UART_RX_CHAR) {
                uartCharacteristics[peripheral.identifier.uuidString] = characteristic
            } else if(characteristic.uuid == Constants.DEVICE_STATUS_CHAR) {
                deviceStatusCharacteristics[peripheral.identifier.uuidString] = characteristic
            } else if(characteristic.uuid == Constants.FW_VERSION_CHAR) {
                peripheral.readValue(for: characteristic)
            }
            
            peripheral.discoverDescriptors(for: characteristic)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        // print("\(#function)")
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        // print("\(#function): \(characteristic)")
        
        // Always enable notifications for Device status characteristic
        if(characteristic.uuid == Constants.UART_TX_CHAR),
            let statusChar = deviceStatusCharacteristics[peripheral.identifier.uuidString]  {
            peripheral.setNotifyValue(true, for: statusChar)
        }
        
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
//         print("didUpdateValueFor: \(characteristic): data size = \(data.count)")
        
        if characteristic.uuid == Constants.UART_TX_CHAR {
            if let logResponse = Response.fromData(data) as? LogResponse {
                // print("Got log response: \(logResponse.success), sequence: \(logResponse.sequenceNumber)")
                if(logResponse.success) {
                    delegate?.updateDeviceWithLogResponse(id: peripheral.identifier, logResponse: logResponse)
                } else {
                    // print("Ignoring unsuccessful log response")
                }
            }
        }
        else if characteristic.uuid == Constants.DEVICE_STATUS_CHAR {
            if let status = DeviceStatus(fromData: data) {
                delegate?.updateDeviceWithStatus(id: peripheral.identifier, status: status)
            }
        }
        else if characteristic.uuid == Constants.FW_VERSION_CHAR {
            let fwVersion = String(decoding: data, as: UTF8.self)
            delegate?.updateDeviceFwVersion(id: peripheral.identifier, fwVersion: fwVersion)
        }
        else {
            // print("didUpdateValueFor: \(characteristic): unknown service")
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        guard let descriptors = characteristic.descriptors, !descriptors.isEmpty else { return }
        
        // print("didDiscoverDescriptorsFor : \(characteristic.uuid)")
        
        for _ in descriptors {
            // print("discovered descriptor : \(descriptor.uuid)")
            
            // Always enable notifications for UART TX characteristic
            if(characteristic.uuid == Constants.UART_TX_CHAR) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
}
