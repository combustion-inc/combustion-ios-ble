//  MeatNetNode.swift

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

/// Representation of a Node on the MeatNet BLE repeater network. Various products
/// can be a MeatNet Node.
public class MeatNetNode: Device {
    
    /// Serial Number
    @Published public internal(set) var serialNumberString: String?
    
    /// Dictionary of Probes connected to this Node's Network
    @Published public var probes: [UInt32 : Probe] = [:]
    
    /// DFU device type
    @Published public internal(set) var dfuType: DFUDeviceType = .unknown
    
    /// Meatnet node name
    public var name: String {
        let serialNumber = serialNumberString ?? ""
        
        switch(dfuType) {
        case .display:
            return "Display \(serialNumber)"
            
        case .charger:
            return "Booster \(serialNumber)"
            
        case .unknown:
            return "Repeater \(serialNumber)"
            
        case .thermometer:
            // Node should not have a DFU type of thermometer
            return "Unknown \(serialNumber)"
        }

    }
    
    /// Dictionary of last time data was received for each connected probe
    /// key = Probe serial
    /// value = Last time advertising or status was recieved from probe over this node
    private var lastTimeDataRecieved: [UInt32: Date] = [:]
    
    private enum Constants {
        /// Number of seconds after which probe should be removed from Node list
        static let PROBE_REMOVE_CONNECTION_TIMEOUT = 30.0
    }
    
    init(_ advertising: AdvertisingData, isConnectable: Bool, RSSI: NSNumber, identifier: UUID) {
        super.init(uniqueIdentifier: identifier.uuidString, bleIdentifier: identifier, RSSI: RSSI)
        updateWithAdvertising(advertising, isConnectable: isConnectable, RSSI: RSSI)
    }
    
    func updateWithAdvertising(_ advertising: AdvertisingData, isConnectable: Bool, RSSI: NSNumber) {
        // Always update probe RSSI and isConnectable flag
        self.rssi = RSSI.intValue
        self.isConnectable = isConnectable
    }
    
    func dataReceivedFromProbe(_ probe: Probe?) {
        guard let probe = probe else { return }
        
        // Add connection to probe
        probes[probe.serialNumber] = probe
        
        // Update last time data was recieved for probe
        lastTimeDataRecieved[probe.serialNumber] = Date()
    }
    
    /// Removes probe from probe list
    private func removeConnectionToProbe(_ serialNumber: UInt32) {
        probes[serialNumber] = nil
    }
    
    /// Returns true if node has connection to probe.
    func hasConnectionToProbe(_ serialNumber: UInt32) -> Bool {
        return probes[serialNumber] != nil
    }
    
    /// Updates whether the device is stale. Called on a timer interval by DeviceManager.
    override func updateDeviceStale() {
        for probeSerial in probes.keys {
            if let lastUpdateTime = lastTimeDataRecieved[probeSerial] {
                // If not data has been received from probe for timeout length, then remove from list
                if(Date().timeIntervalSince(lastUpdateTime) > Constants.PROBE_REMOVE_CONNECTION_TIMEOUT) {
                    removeConnectionToProbe(probeSerial)
                }
            }
            else {
                // This should not happen, but if no update time for probe, then remove from list
                removeConnectionToProbe(probeSerial)
            }
        }
    }

    /// Special handling for MeatNetNode model info.  Need to decode model info string
    /// to determine DFU type
    override func updateWithModelInfo(_ modelInfo: String) {
        super.updateWithModelInfo(modelInfo)
        
        if(modelInfo.contains("Timer")) {
            dfuType = .display
        }
        else if(modelInfo.contains("Charger")) {
            dfuType = .charger
        }
    }
}
