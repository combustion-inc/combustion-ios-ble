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
import NordicDFU

protocol BleManagerDelegate: AnyObject {
    func didConnectTo(identifier: UUID)
    func didFailToConnectTo(identifier: UUID)
    func didDisconnectFrom(identifier: UUID)
    func updateDeviceWithAdvertising(advertising: AdvertisingData, isConnectable: Bool, rssi: NSNumber, identifier: UUID)
    func updateDeviceWithStatus(identifier: UUID, status: ProbeStatus)
    func handleUARTData(identifier: UUID, data: Data)
    func updateDeviceFwVersion(identifier: UUID, fwVersion: String)
    func updateDeviceHwRevision(identifier: UUID, hwRevision: String)
    func updateDeviceSerialNumber(identifier: UUID, serialNumber: String)
}

/// Manages Core Bluetooth interface with the rest of the app.
class BleManager : NSObject {
    /// Singleton accessor for class
    static let shared = BleManager()
    
    weak var delegate: BleManagerDelegate?
    
    private(set) var peripherals = Set<CBPeripheral>()
    
    private var uartCharacteristics: [String: CBCharacteristic] = [:]
    private var deviceStatusCharacteristics: [String: CBCharacteristic] = [:]
    
    private var manager: CBCentralManager?
    
    private enum Constants {
        static let DEVICE_INFO_SERVICE  = CBUUID(string: "180a")
        static let DFU_SERVICE          = CBUUID(string: "FE59")
        static let NEEDLE_SERVICE       = CBUUID(string: "00000100-CAAB-3792-3D44-97AE51C1407A")
        static let UART_SERVICE         = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
        
        static let SERIAL_NUMBER_CHAR   = CBUUID(string: "2a25")
        static let FW_VERSION_CHAR      = CBUUID(string: "2a26")
        static let HW_REVISION_CHAR     = CBUUID(string: "2a27")
        static let DEVICE_STATUS_CHAR   = CBUUID(string: "00000101-CAAB-3792-3D44-97AE51C1407A")
        static let UART_RX_CHAR         = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
        static let UART_TX_CHAR         = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    }
    
    /// Private initializer to enforce singleton
    private override init() {
        super.init()
    }
    
    func initBluetooth() {
        if(manager == nil) {
            manager = CBCentralManager(delegate: self, queue: nil)
        }
    }
    
    private func startScanning() {
        manager?.scanForPeripherals(withServices: [Constants.DFU_SERVICE],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }
    
    func sendRequest(identifier: String, request: Request) {
        if let connectionPeripheral = getConnectedPeripheral(identifier: identifier),
            let uartChar = uartCharacteristics[identifier] {
            connectionPeripheral.writeValue(request.data, for: uartChar, type: .withoutResponse)
        }
    }
    
    func sendRequest(identifier: String, request: NodeRequest) {
        if let connectionPeripheral = getConnectedPeripheral(identifier: identifier),
            let uartChar = uartCharacteristics[identifier] {
            connectionPeripheral.writeValue(request.data, for: uartChar, type: .withoutResponse)
        }
    }
    
    func startFirmwareUpdate(device: Device, dfu: DFUFirmware) -> DFUServiceController? {
        guard let bleIdentifier = device.bleIdentifier, let connectedPeripheral = getConnectedPeripheral(identifier: bleIdentifier) else { return nil }
        
        return DFUManager.shared.startDFU(peripheral: connectedPeripheral, device: device, firmware: dfu)
    }
    
    private func getConnectedPeripheral(identifier: String) -> CBPeripheral? {
        let uuid = UUID(uuidString: identifier)
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
        let isConnectable = advertisementData[CBAdvertisementDataIsConnectable] as? Bool ?? false
        
        if let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            DFUManager.shared.retryDfuOnBootloader(peripheral: peripheral, advertisingName: name)
        }
        else if let advData = AdvertisingData(fromData: manufatureData)  {
            // Store peripheral reference for later use
            peripherals.insert(peripheral)
            
            delegate?.updateDeviceWithAdvertising(advertising: advData,
                                                  isConnectable: isConnectable,
                                                  rssi: RSSI,
                                                  identifier: peripheral.identifier)
        }
    }
    
    /// Connect to device with the specified name.
    public func connect(identifier: String) {
        let uuid = UUID(uuidString: identifier)
        let devicePeripherals = peripherals.filter { $0.identifier == uuid }
        guard !devicePeripherals.isEmpty else {
            print("Failed to find peripheral")
            return
        }
        
        for peripheral in devicePeripherals {
            // print("Connecting to peripheral: \(peripheral.name) : \(peripheral.identifier)")
            manager?.connect(peripheral, options: nil)
        }
    }
    
    /// Disconnect from device with the specified name.
    public func disconnect(identifier: String) {
        if let connectedPeripheral = getConnectedPeripheral(identifier: identifier) {
            manager?.cancelPeripheralConnection(connectedPeripheral)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // print("\(#function)")

        peripheral.delegate = self
        peripheral.discoverServices(nil)
        
        delegate?.didConnectTo(identifier: peripheral.identifier)
    }
    
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        // print("\(#function)")
        
        delegate?.didFailToConnectTo(identifier: peripheral.identifier)
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // print("\(#function)")
        
        delegate?.didDisconnectFrom(identifier: peripheral.identifier)
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
            if(characteristic.uuid == Constants.UART_RX_CHAR) {
                uartCharacteristics[peripheral.identifier.uuidString] = characteristic
            } else if(characteristic.uuid == Constants.DEVICE_STATUS_CHAR) {
                deviceStatusCharacteristics[peripheral.identifier.uuidString] = characteristic
            } else if(characteristic.uuid == Constants.FW_VERSION_CHAR ||
                      characteristic.uuid == Constants.HW_REVISION_CHAR ||
                      characteristic.uuid == Constants.SERIAL_NUMBER_CHAR) {
                // Read FW version, HW revision, and serial number when the characteristics are discovered
                peripheral.readValue(for: characteristic)
            }
            
            peripheral.discoverDescriptors(for: characteristic)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {

    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if(characteristic.uuid == Constants.UART_TX_CHAR),
            let statusChar = deviceStatusCharacteristics[peripheral.identifier.uuidString]  {
            // After enabling UART notification
            // Enable notifications for Device status characteristic
            peripheral.setNotifyValue(true, for: statusChar)
            
            // Send request the session ID from device
            sendRequest(identifier: peripheral.identifier.uuidString, request: SessionInfoRequest())
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        switch(characteristic.uuid) {
        case Constants.UART_TX_CHAR:
            handleUartData(data: data, identifier: peripheral.identifier)
            
        case Constants.DEVICE_STATUS_CHAR:
            if let status = ProbeStatus(fromData: data) {
                delegate?.updateDeviceWithStatus(identifier: peripheral.identifier, status: status)
            }
            
        case Constants.SERIAL_NUMBER_CHAR:
            let serialNumber = String(decoding: data, as: UTF8.self)
            delegate?.updateDeviceSerialNumber(identifier: peripheral.identifier, serialNumber: serialNumber)
            
        case Constants.FW_VERSION_CHAR:
            let fwVersion = String(decoding: data, as: UTF8.self)
            delegate?.updateDeviceFwVersion(identifier: peripheral.identifier, fwVersion: fwVersion)
            
        case Constants.HW_REVISION_CHAR:
            let hwRevision = String(decoding: data, as: UTF8.self)
            delegate?.updateDeviceHwRevision(identifier: peripheral.identifier, hwRevision: hwRevision)
            
        default:
            break
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        guard let descriptors = characteristic.descriptors, !descriptors.isEmpty else { return }
        
        for _ in descriptors {
            // Always enable notifications for UART TX characteristic
            if(characteristic.uuid == Constants.UART_TX_CHAR) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    private func handleUartData(data: Data, identifier: UUID) {
        delegate?.handleUARTData(identifier: identifier, data: data)
    }
}
