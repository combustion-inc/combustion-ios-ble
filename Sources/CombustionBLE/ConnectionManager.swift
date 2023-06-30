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
    
    private var connectionTimers: [String: Timer] = [:]
    private var lastStatusUpdate: [String: Date] = [:]
    
    /// Number of seconds after which a direct connection should be made to probe
    private let PROBE_STATUS_STALE_TIMEOUT = 10.0
    
    func receivedProbeAdvertising(_ probe: Probe?) {
        guard let probe = probe else { return }
        
        var probeStatusStale = true
        
        if let lastUpdateTime = lastStatusUpdate[probe.serialNumberString] {
            probeStatusStale = Date().timeIntervalSince(lastUpdateTime) > PROBE_STATUS_STALE_TIMEOUT
        }
        
        // If MeatNet is enabled and the probe data is stale, then connect to it
        if meatNetEnabled &&
            probeStatusStale &&
            (probe.connectionState != .connected) &&
            (connectionTimers[probe.serialNumberString] == nil) {
            
            // Start timer to connect to probe after delay
            connectionTimers[probe.serialNumberString] = Timer.scheduledTimer(withTimeInterval: 3, repeats: false, block: { [weak self] _ in
                print("JDJ Connect to probe")
                
                if let probe = self?.getProbeWithSerial(probe.serialNumberString) {
                    probe.connect()
                }
                
                // Clear timer
                self?.connectionTimers[probe.serialNumberString] = nil
            })
        }
    }
    
    func receivedProbeAdvertising(_ probe: Probe?, from node: MeatNetNode) {
        // When meatnet is enabled, try to connect to all Nodes.
        if meatNetEnabled {
            node.connect()
        }
    }
    
    func receivedStatusFor(_ probe: Probe, directConnection: Bool) {
        lastStatusUpdate[probe.serialNumberString] = Date()
        
        // if receiving status from meatnet, then disconnect from probe
        if !directConnection,
           let probe = getProbeWithSerial(probe.serialNumberString),
           probe.connectionState == .connected {
            print("JDJ diconnect from probe")
            probe.disconnect()
        }
    }
    
    private func getProbeWithSerial(_ serial: String) -> Probe? {
        let probes = DeviceManager.shared.getProbes()
        
        return probes.filter { $0.serialNumberString == serial}.first
    }
}
