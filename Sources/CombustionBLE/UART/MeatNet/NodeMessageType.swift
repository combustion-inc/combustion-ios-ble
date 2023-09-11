//  NodeMessageType.swift

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

enum NodeMessageType: UInt8  {
    case setID = 1
    case setColor = 2
    case sessionInfo = 3
    case log = 4
    case setPrediction = 5
    case readOverTemperature = 6
    
    case connected = 0x40
    case disconnected = 0x41
    case readNodeList = 0x42
    case readNetworkTopology = 0x43
    case readProbeList = 0x44
    case probeStatus = 0x45
    case probeFirmwareRevision = 0x46
    case probeHardwareRevision = 0x47
    case probeModelInformation = 0x48
    case heartbeat = 0x49
    case syncThermometerList = 0x4B
}
