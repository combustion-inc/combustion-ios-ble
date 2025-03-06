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
    func updateBluetoothState(state: CBManagerState)
    func didConnectTo(identifier: UUID)
    func didFailToConnectTo(identifier: UUID)
    func didDisconnectFrom(identifier: UUID)
    func handleBootloaderAdvertising(advertisingName: String, rssi: NSNumber, peripheral: CBPeripheral)
    func updateDeviceWithAdvertising(advertising: AdvertisingData, isConnectable: Bool, rssi: NSNumber, identifier: UUID)
    func updateDeviceWithStatus(identifier: UUID, status: ProbeStatus)
    func handleUARTData(identifier: UUID, data: Data)
    func updateDeviceFwVersion(identifier: UUID, fwVersion: String)
    func updateDeviceHwRevision(identifier: UUID, hwRevision: String)
    func updateDeviceSerialNumber(identifier: UUID, serialNumber: String)
    func updateDeviceModelInfo(identifier: UUID, modelInfo: String)
}

/// Manages Core Bluetooth interface with the rest of the app.
class BleManager : NSObject {
    /// Singleton accessor for class
    static let shared = BleManager()
    
    weak var delegate: BleManagerDelegate?
    
    private(set) var peripherals = Set<CBPeripheral>()
    
    private var characteristics: [String: [BleCharacteristic: CBCharacteristic]] = [:]
    
    private var manager: CBCentralManager?
    
    private enum Constants {
        static let DEVICE_INFO_SERVICE  = CBUUID(string: "180a")
        static let DFU_SERVICE          = CBUUID(string: "FE59")
        static let NEEDLE_SERVICE       = CBUUID(string: "00000100-CAAB-3792-3D44-97AE51C1407A")
        static let UART_SERVICE         = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
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
    
    func sendRequest(identifier: String?, request: Request) {
        guard let identifier = identifier else { return }
        
        if let connectionPeripheral = getConnectedPeripheral(identifier: identifier),
           let uartChar = getCharacteristicFor(identifier, type: .uartRx) {
            connectionPeripheral.writeValue(request.data, for: uartChar, type: .withoutResponse)
        }
    }
    
    func sendDFURequest(identifier: String?, request: DFURequest) {
        guard let identifier = identifier else { return }
        
        print("JDJ sendDFURequest")
        
        if let connectedPeripheral = getConnectedPeripheral(identifier: identifier),
           let dfuChar = getCharacteristicFor(identifier, type: .dfu) {
            
            print("JDJ sendDFURequest - found peripheral")
            
            connectedPeripheral.writeValue(request.data,
                                            for: dfuChar,
                                            type: .withResponse)
        }
    }
    
    func sendRequestToNodes(_ nodes: [MeatNetNode], request: NodeRequest) {
        for node in nodes {
            if let identifier = node.bleIdentifier,
               let connectionPeripheral = getConnectedPeripheral(identifier: identifier),
               let uartChar = getCharacteristicFor(identifier, type: .uartRx) {
                connectionPeripheral.writeValue(request.data, for: uartChar, type: .withoutResponse)
            }
        }
    }
    
    func readFirmwareRevision(identifier: String?) {
        guard let identifier = identifier else { return }
        
        if let connectionPeripheral = getConnectedPeripheral(identifier: identifier),
           let characteristic = getCharacteristicFor(identifier, type: .firmwareVersion) {
            // Initiate read of firmware revision
            connectionPeripheral.readValue(for: characteristic)
        }
    }
    
    func readHardwareRevision(identifier: String?) {
        guard let identifier = identifier else { return }
        
        if let connectionPeripheral = getConnectedPeripheral(identifier: identifier),
           let characteristic = getCharacteristicFor(identifier, type: .hardwareRevision) {
            // Initiate read of hardware revision
            connectionPeripheral.readValue(for: characteristic)
        }
    }
    
    func readSerialNumber(identifier: String) {
        if let connectionPeripheral = getConnectedPeripheral(identifier: identifier),
           let characteristic = getCharacteristicFor(identifier, type: .serialNumber) {
            // Initiate read of serial number
            connectionPeripheral.readValue(for: characteristic)
        }
    }
    
    func readModelNumber(identifier: String?) {
        guard let identifier = identifier else { return }
        
        if let connectionPeripheral = getConnectedPeripheral(identifier: identifier),
           let characteristic = getCharacteristicFor(identifier, type: .modelNumber) {
            // Initiate read of hardware revision
            connectionPeripheral.readValue(for: characteristic)
        }
    }
    
    func startFirmwareUpdate(device: Device, dfu: DFUFirmware) -> DFUServiceController? {
        guard let bleIdentifier = device.bleIdentifier, 
                let connectedPeripheral = getConnectedPeripheral(identifier: bleIdentifier) else { return nil }
        
        return DFUManager.shared.startDFU(peripheral: connectedPeripheral, device: device, firmware: dfu)
    }
    
    func retryFirmwareUpdate(device: BootloaderDevice) {
        guard let bleIdentifier = device.bleIdentifier else { return }
        
        // Find booloader ble peripheral
        let uuid = UUID(uuidString: bleIdentifier )
        let devicePeripherals = peripherals.filter { $0.identifier == uuid }
        guard let peripheral = devicePeripherals.first else {
            // print("Failed to find peripherals")
            return
        }

        DFUManager.shared.restartDfuOnUnknownBootloader(peripheral: peripheral, device: device)
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
    
    private func storeCharacteristicFor(_ device: CBPeripheral, type: BleCharacteristic, characteristic: CBCharacteristic) {
        // Creat dictionary for device if it doesnt exists
        if characteristics[device.identifier.uuidString] == nil {
            characteristics[device.identifier.uuidString] = [:]
        }
        
        // Store characteristic
        characteristics[device.identifier.uuidString]?[type] = characteristic
    }
    
    private func getCharacteristicFor(_ peripheralIdentifier: String, type: BleCharacteristic) -> CBCharacteristic? {
        return characteristics[peripheralIdentifier]?[type]
    }
}

// MARK: - CBCantralManagerDelegate

extension BleManager: CBCentralManagerDelegate{
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Update the state
        delegate?.updateBluetoothState(state: central.state)
        
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
        
        if let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
           DFUManager.bootloaderTypeFrom(advertisingName: advName) != .unknown {
            
            print("JDJ bootloader name \(advName)")
            
            // Store peripheral reference for later use
            peripherals.insert(peripheral)
            
            delegate?.handleBootloaderAdvertising(advertisingName: advName, rssi: RSSI, peripheral: peripheral)
        }
        else if let advData = ProbeAdvertisingData(fromData: manufatureData)  {
            // Store peripheral reference for later use
            peripherals.insert(peripheral)
            
            delegate?.updateDeviceWithAdvertising(advertising: advData,
                                                  isConnectable: isConnectable,
                                                  rssi: RSSI,
                                                  identifier: peripheral.identifier)
        }
        else if let advData = NodeAdvertisingData.create(fromData: manufatureData) {
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
        guard let services = peripheral.services else { return }
        
        print("JDJ didDiscoverServices")
        
        for service in services {
            print("JDJ -- discovered service : \(service.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        print("JDJ didDiscoverCharacteristicsFor : \(service.uuid.uuidString)")
        
        for characteristic in characteristics {
            print("JDJ -- discovered characteristic : \(characteristic.uuid.uuidString)")
            
            if let type = BleCharacteristic.from(characteristic) {
                
                // Store characteristic
                storeCharacteristicFor(peripheral, type: type, characteristic: characteristic)
                
                // Read FW version, HW revision, and serial number when the characteristics are discovered
                if(type == BleCharacteristic.firmwareVersion ||
                   type == BleCharacteristic.hardwareRevision ||
                   type == BleCharacteristic.modelNumber ||
                   type == BleCharacteristic.serialNumber) {
                    peripheral.readValue(for: characteristic)
                }
            }
            
            peripheral.discoverDescriptors(for: characteristic)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {

    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        print("JDJ didUpdateNotificationStateFor : \(characteristic.uuid.uuidString)")
        
        if(characteristic.uuid == BleCharacteristic.uartTx.uuid),
          let statusChar = getCharacteristicFor(peripheral.identifier.uuidString, type: .deviceStatus) {
            // After enabling UART notification
            // Enable notifications for Device status characteristic
            peripheral.setNotifyValue(true, for: statusChar)
        }
        else if(characteristic.uuid == BleCharacteristic.deviceStatus.uuid),
               let statusChar = getCharacteristicFor(peripheral.identifier.uuidString, type: .dfu) {
            // After enabling STATUS notification
            // Enable notifications for DFU characteristic
            peripheral.setNotifyValue(true, for: statusChar)
        }
        else if(characteristic.uuid == BleCharacteristic.dfu.uuid) {
            // After enabling DFU notification
            // Send request the session ID from device
            sendRequest(identifier: peripheral.identifier.uuidString, request: SessionInfoRequest())
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        switch(characteristic.uuid) {
        case BleCharacteristic.uartTx.uuid:
            handleUartData(data: data, identifier: peripheral.identifier)
            
        case BleCharacteristic.deviceStatus.uuid:
            if let status = ProbeStatus(fromData: data) {
                delegate?.updateDeviceWithStatus(identifier: peripheral.identifier, status: status)
            }
            
        case BleCharacteristic.serialNumber.uuid:
            let serialNumber = String(decoding: data, as: UTF8.self)
            delegate?.updateDeviceSerialNumber(identifier: peripheral.identifier, serialNumber: serialNumber)
            
        case BleCharacteristic.firmwareVersion.uuid:
            let fwVersion = String(decoding: data, as: UTF8.self)
            delegate?.updateDeviceFwVersion(identifier: peripheral.identifier, fwVersion: fwVersion)
            
        case BleCharacteristic.hardwareRevision.uuid:
            let hwRevision = String(decoding: data, as: UTF8.self)
            delegate?.updateDeviceHwRevision(identifier: peripheral.identifier, hwRevision: hwRevision)
            
        case  BleCharacteristic.modelNumber.uuid:
            let modelInfo = String(decoding: data, as: UTF8.self)
            delegate?.updateDeviceModelInfo(identifier: peripheral.identifier, modelInfo: modelInfo)
         
        case BleCharacteristic.dfu.uuid:
            print("JDJ didUpdateValueFor DFU_CHAR")
            
        default:
            break
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        guard let descriptors = characteristic.descriptors, !descriptors.isEmpty else { return }
        
        print("JDJ didDiscoverDescriptorsFor : \(characteristic.uuid.uuidString)")
        
        for _ in descriptors {
            // Always enable notifications for UART TX characteristic
            if(characteristic.uuid == BleCharacteristic.uartTx.uuid) {
                print("JDJ setNotifyValue : Constants.UART_TX_CHAR")
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    private func handleUartData(data: Data, identifier: UUID) {
        delegate?.handleUARTData(identifier: identifier, data: data)
    }
}
