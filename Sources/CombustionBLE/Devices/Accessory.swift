//  Accessory.swift
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
import Combine

/// Representation of a meat net nodes native abilites, such as Grill Gauge
public protocol Accessory {
    
    associatedtype SerialNumberType
        
    var parent: Device? { get }
    
    var type: ProductType { get }
     
    var serialNumber: SerialNumberType { get }
    
    var serialNumberString: String { get }
    
    /// Tracks whether status notification data has become stale.
    var statusNotificationsStale: Bool { get }
    
    var deviceTemperatureLogs: [DeviceTemperatureLog] { get }
        
    func updateDeviceStatus(deviceStatus: DeviceStatus, hopCount: HopCount?)
    
    func updateWithAdvertising(_ advertising: any AdvertisingData)
    
    func updateWithSessionInformation(_ sessionInfo: SessionInformation)
    
    func updateLastUpdateTime() 
    
    var lastUpdateTimePublisher: AnyPublisher<Date, Never> { get }
    
    // forwarding publishers for parent values
    var firmareVersionPublisher: AnyPublisher<String?, Never> { get }
    var hardwareRevisionPublisher: AnyPublisher<String?, Never> { get }
    var skuPublisher: AnyPublisher<String?, Never> { get }
    var manufacturingLotPublisher: AnyPublisher<String?, Never> { get }
}

public extension Accessory {
    
    func updateDeviceStatus(deviceStatus: DeviceStatus, hopCount: HopCount? = nil) {
        self.updateDeviceStatus(deviceStatus: deviceStatus, hopCount: hopCount)
    }
}
