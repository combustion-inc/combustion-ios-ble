/*--
MIT License

Copyright (c) 2025 Combustion Inc.

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
SOFTWARE.
--*/

import CoreBluetooth

/// Class to store the discovered BLE services and characteristics
/// for a peripheral device
class CombustionPeripheral {
    private(set) var peripheral: CBPeripheral
    private(set) var discoveredServices: Set<BleService> = []
    private(set) var discoveredCharacteristicForService: Set<BleService> = []
    private(set) var characteristics: [BleCharacteristic: CBCharacteristic] = [:]
    
    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
    }
    
    /// Discovered service for this peripheral
    /// - Parameter service: discovered service
    func discoveredService(_ service: CBService) {
        guard let serviceType = BleService.from(service) else { return }
        discoveredServices.insert(serviceType)
    }
    
    /// Characteristics have been discovered for the given service
    /// - Parameter service: service
    func discoveredCharacteristicsFor(_ service: CBService) {
        guard let serviceType = BleService.from(service) else { return }
        discoveredCharacteristicForService.insert(serviceType)
    }
    
    /// Discovered characteristic for this peripheral
    /// - Parameter characteristic: discovered characteristic
    func discoveredCharacteristic(characteristic: CBCharacteristic) {
        guard let type = BleCharacteristic.from(characteristic) else { return }

        characteristics[type] = characteristic
    }
    
    /// Checks if characteristics have been discovered for all discovered services
    /// - Returns: true if characteristics have been discovered for all discovered services
    func haveDiscoveredCharacteristicForAllServices() -> Bool {
        return discoveredServices.count == discoveredCharacteristicForService.count
    }
}
