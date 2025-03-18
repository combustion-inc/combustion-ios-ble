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
    func updateBluetoothState(state: CBManagerState)
    func didConnectTo(identifier: UUID)
    func didFailToConnectTo(identifier: UUID)
    func didDisconnectFrom(identifier: UUID)
    func didCompleteDiscovery(identifier: UUID, maximumWriteValueLength: Int)
    func didEnableNotificationsFor(identifier: UUID, characteristic: BleCharacteristic)
    func handleBootloaderAdvertising(identifier: UUID, advertisingName: String, rssi: NSNumber)
    func handleDFUData(identifier: UUID, characteristic: BleCharacteristic, data: Data)
    func handleUARTData(identifier: UUID, data: Data)
    func updateDeviceWithAdvertising(advertising: AdvertisingData, isConnectable: Bool, rssi: NSNumber, identifier: UUID)
    func updateDeviceWithStatus(identifier: UUID, status: ProbeStatus)
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
    
    private var peripherals = [String: CombustionPeripheral]()
    
    private var manager: CBCentralManager?
    
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
        manager?.scanForPeripherals(withServices: [BleService.dfu.uuid],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }
    
    func sendRequest(identifier: String?, request: Request) {
        guard let identifier = identifier else { return }
        
        if let connectionPeripheral = getConnectedPeripheral(identifier: identifier),
           let uartChar = getCharacteristicFor(identifier, type: .uartRx) {
            connectionPeripheral.writeValue(request.data, for: uartChar, type: .withoutResponse)
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
    
    func startFirmwareUpdate(device: Device, dfu: DFUFirmware) {
        guard let bleIdentifier = device.bleIdentifier,
                let connectedPeripheral = getConnectedPeripheral(identifier: bleIdentifier) else { return }
        
        DFUManager.shared.startDFU(peripheral: connectedPeripheral, device: device, firmware: dfu)
    }
    
    func enableNotificationsFor(_ identifier: String, type: BleCharacteristic) {
        guard let combustionPeripheral = peripherals[identifier],
              let char = getCharacteristicFor(identifier, type: type) else { return }
        
        combustionPeripheral.peripheral.setNotifyValue(true, for: char)
    }
    
    func sendDFURequest(identifier: String?, request: ButtonlessDFURequest) {
        guard let identifier = identifier else { return }
        
        if let connectedPeripheral = getConnectedPeripheral(identifier: identifier),
           let dfuChar = getCharacteristicFor(identifier, type: .dfu) {
            connectedPeripheral.writeValue(request.data,
                                           for: dfuChar,
                                           type: .withResponse)
        }
    }
    
    func sendRequestToBootloader(_ device: Device, request: SecureDFURequest) {
        guard let identifier = device.bootloaderIdentifier else { return }

        if let connectedPeripheral = getConnectedPeripheral(identifier: identifier),
           let bootloaderDFUChar = getCharacteristicFor(identifier, type: .dfuControlPoint) {
            
            print("JDJ sendRequestToBootloader : \(request)")
            
            connectedPeripheral.writeValue(request.data,
                                           for: bootloaderDFUChar,
                                           type: .withResponse)
        }
    }
    
    func sendPacketToBootloader(_ device: Device, data: Data) {
        guard let identifier = device.bootloaderIdentifier else { return }
        
        if let connectedPeripheral = getConnectedPeripheral(identifier: identifier),
           let dfuPacketChar = getCharacteristicFor(identifier, type: .dfuPacket) {
            
            print("JDJ sendPacketToBootloader : data count \(data.count)")
            
            connectedPeripheral.writeValue(data,
                                           for: dfuPacketChar,
                                           type: .withoutResponse)
        }
    }
    
    private func getConnectedPeripheral(identifier: String) -> CBPeripheral? {
        guard let combustionPeripheral = peripherals[identifier] else { return nil }
        
        // Check that device is connected
        guard combustionPeripheral.peripheral.state == .connected else { return nil }
        
        return combustionPeripheral.peripheral
    }
    
    private func storePeripheral(_ peripheral: CBPeripheral) {
        guard peripherals[peripheral.identifier.uuidString] == nil else { return }
        
        peripherals[peripheral.identifier.uuidString] = CombustionPeripheral(peripheral: peripheral)
    }
    
    private func combustionPeripheralFor(_ peripheral: CBPeripheral) -> CombustionPeripheral? {
        return peripherals[peripheral.identifier.uuidString]
    }
    
    private func getCharacteristicFor(_ peripheralIdentifier: String, type: BleCharacteristic) -> CBCharacteristic? {
        guard let peripheral = peripherals[peripheralIdentifier] else { return nil }
        return peripheral.characteristics[type]
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
            
            // Store peripheral reference
            storePeripheral(peripheral)
            
            delegate?.handleBootloaderAdvertising(identifier: peripheral.identifier, advertisingName: advName, rssi: RSSI)
        }
        else if let advData = ProbeAdvertisingData(fromData: manufatureData)  {
            // Store peripheral reference
            storePeripheral(peripheral)
            
            delegate?.updateDeviceWithAdvertising(advertising: advData,
                                                  isConnectable: isConnectable,
                                                  rssi: RSSI,
                                                  identifier: peripheral.identifier)
        }
        else if let advData = NodeAdvertisingData.create(fromData: manufatureData) {
            // Store peripheral reference
            storePeripheral(peripheral)
            
            delegate?.updateDeviceWithAdvertising(advertising: advData,
                                                  isConnectable: isConnectable,
                                                  rssi: RSSI,
                                                  identifier: peripheral.identifier)
        }
    }
    
    /// Connect to device with the specified name.
    public func connect(identifier: String) {
        guard let combustionPeripheral = peripherals[identifier] else { return }
        manager?.connect(combustionPeripheral.peripheral, options: nil)
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
        
        for service in services {            
            // Save discovered service
            combustionPeripheralFor(peripheral)?.discoveredService(service)
            
            // Discover characteristics for that service
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics,
            let combustionPeripheral = combustionPeripheralFor(peripheral) else { return }
        
        // Save that characteristics were discovered for the service
        combustionPeripheral.discoveredCharacteristicsFor(service)
        
        for characteristic in characteristics {
            // Save discovered characteristics
            combustionPeripheral.discoveredCharacteristic(characteristic: characteristic)
            
            if let type = BleCharacteristic.from(characteristic) {
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
        
        if combustionPeripheral.haveDiscoveredCharacteristicForAllServices() {
            delegate?.didCompleteDiscovery(
                identifier: peripheral.identifier,
                maximumWriteValueLength: peripheral.maximumWriteValueLength(for: .withoutResponse))
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {

    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard let characteristicType = BleCharacteristic.from(characteristic) else { return }
        
        delegate?.didEnableNotificationsFor(identifier: peripheral.identifier, characteristic: characteristicType)
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value,
              let bleCharacteristic = BleCharacteristic.from(characteristic) else { return }
        
        switch(bleCharacteristic) {
        case .uartTx:
            delegate?.handleUARTData(identifier: peripheral.identifier, data: data)
            
        case .deviceStatus:
            if let status = ProbeStatus(fromData: data) {
                delegate?.updateDeviceWithStatus(identifier: peripheral.identifier, status: status)
            }
            
        case .serialNumber:
            let serialNumber = String(decoding: data, as: UTF8.self)
            delegate?.updateDeviceSerialNumber(identifier: peripheral.identifier, serialNumber: serialNumber)
            
        case .firmwareVersion:
            let fwVersion = String(decoding: data, as: UTF8.self)
            delegate?.updateDeviceFwVersion(identifier: peripheral.identifier, fwVersion: fwVersion)
            
        case .hardwareRevision:
            let hwRevision = String(decoding: data, as: UTF8.self)
            delegate?.updateDeviceHwRevision(identifier: peripheral.identifier, hwRevision: hwRevision)
            
        case  .modelNumber:
            let modelInfo = String(decoding: data, as: UTF8.self)
            delegate?.updateDeviceModelInfo(identifier: peripheral.identifier, modelInfo: modelInfo)
         
        case .dfu, .dfuControlPoint:
            delegate?.handleDFUData(identifier: peripheral.identifier, characteristic: bleCharacteristic, data: data)
            
        case .dfuPacket, .uartRx:
            // Do not receive data on these characteristics
            break
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {

    }
}
