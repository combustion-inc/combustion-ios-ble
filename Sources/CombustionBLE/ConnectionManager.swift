//  ConnectionManager.swift

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

class ConnectionManager {
    
    /// Tracks whether MeatNet is enabled.
    var meatNetEnabled : Bool = false
    
    /// Tracks whether DFU mode is enabled.
    var dfuModeEnabled : Bool = false
    
    /// List of thermometer serial numbers to connect to
    private(set) var thermometerAllowList: Set<String>? = nil
    
    private var connectionTimers: [String: Timer] = [:]
    private var lastStatusUpdate: [String: Date] = [:]
    
    /// Number of seconds after which a direct connection should be made to probe
    private let PROBE_STATUS_STALE_TIMEOUT = 10.0
    
    /// Sets the allow list for thermometers.  Framework will only connect to thermometers
    /// in the allow list and nodes that are advertising data from thermometer in whitelist.
    /// - param whiteList: White list of probes serial numbers
    func setThermometerAllowList(_ allowList: Set<String>) {
        thermometerAllowList = allowList
    }
    
    func receivedProbeAdvertising(_ probe: Probe?) {
        // Nothing to do if already connected to probe
        guard let probe = probe,
              probe.connectionState != .connected else { return }
        
        var probeStatusStale = true
        if let lastUpdateTime = lastStatusUpdate[probe.serialNumberString] {
            probeStatusStale = Date().timeIntervalSince(lastUpdateTime) > PROBE_STATUS_STALE_TIMEOUT
        }
        
        if dfuModeEnabled { // In DFU mode, connect to probe if its in allow list
            if probeInAllowList(probe) {
                probe.connect()
            }
        }
        else if !meatNetEnabled { // If meatnet is not enabled, always connect to probe
            probe.connect()
        }
        else { // When MeatNet is enabled and the probe data is stale, then connect to it
            if probeInAllowList(probe) &&
                probeStatusStale &&
                (connectionTimers[probe.serialNumberString] == nil) {
                
                // Start timer to connect to probe after delay
                connectionTimers[probe.serialNumberString] = Timer.scheduledTimer(withTimeInterval: 3, repeats: false, block: { [weak self] _ in
                    
                    if let probe = self?.getProbeWithSerial(probe.serialNumberString) {
                        probe.connect()
                    }
                    
                    // Clear timer
                    self?.connectionTimers[probe.serialNumberString] = nil
                })
            }
        }
    }
    
    func receivedProbeAdvertising(_ probe: Probe?, from node: MeatNetNode) {
        // Nothing to do if already connected to node
        guard node.connectionState != .connected else { return }
        
        if dfuModeEnabled { // DFU mode
            // Connect to node if its within the DFU range
            if node.withinProximityRange {
                node.connect()
            }
            // Or if node is probe is in allow list
            else if let probe = probe, probeInAllowList(probe) {
                node.connect()
            }
        }
        else if meatNetEnabled { // Meatnet is enabled
            // Connect to all Nodes that are advertising probes in allow list
            if let probe = probe,
                    meatNetEnabled,
                    probeInAllowList(probe) {
                node.connect()
            }
        }
    }
    
    func receivedStatusFor(_ probe: Probe, node: MeatNetNode?) {
        let directConnection = node == nil
        
        lastStatusUpdate[probe.serialNumberString] = Date()
        
        // Track that data was recieved for probe on node
        node?.dataReceivedFromProbe(probe)
        
        // if receiving status from meatnet and DFU disabled, then disconnect from probe
        if !directConnection && meatNetEnabled && !dfuModeEnabled {
            
            if let probe = getProbeWithSerial(probe.serialNumberString),
               probe.connectionState == .connected {
                probe.disconnect()
            }
        }
    }
    
    private func getProbeWithSerial(_ serial: String) -> Probe? {
        let probes = DeviceManager.shared.getProbes()
        
        return probes.filter { $0.serialNumberString == serial}.first
    }
    
    private func probeInAllowList(_ probe: Probe) -> Bool {
        // If allowList is nil, then return true
        guard let allowList = thermometerAllowList else { return true}
        
        return allowList.contains(probe.serialNumberString)
    }
}
