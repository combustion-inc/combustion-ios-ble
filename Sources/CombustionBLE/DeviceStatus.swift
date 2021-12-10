//  DeviceStatus.swift

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

/// Message containing Probe status information.
public struct DeviceStatus {
    /// Minimum sequence number of records in Probe's memory.
    public let minSequenceNumber: UInt32
    /// Maximum sequence number of records in Probe's memory.
    public let maxSequenceNumber: UInt32
    /// Current temperatures sent by Probe.
    public let temperatures: ProbeTemperatures
}

extension DeviceStatus {
    init?(fromData data: Data) {
        guard data.count >= 21 else { return nil }
        
        let minRaw = data.subdata(in: 0..<4)
        minSequenceNumber = minRaw.withUnsafeBytes {
            $0.load(as: UInt32.self)
        }
        
        let maxRaw = data.subdata(in: 4..<8)
        maxSequenceNumber = maxRaw.withUnsafeBytes {
            $0.load(as: UInt32.self)
        }
        
        // Temperatures (8 13-bit) values
        let tempData = data.subdata(in: 8..<21)
        temperatures = ProbeTemperatures.fromRawData(data: tempData)
    }
}
