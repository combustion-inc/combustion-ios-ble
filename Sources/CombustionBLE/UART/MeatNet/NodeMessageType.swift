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

enum NodeMessageType: UInt8, CaseIterable  {
    case setID = 0x01
    case setColor = 0x02
    case sessionInfo = 0x03
    case log = 0x04
    case setPrediction = 0x05
    case readOverTemperature = 0x06
    case configureFoodSafe = 0x07
    case resetFoodSafe = 0x08
    
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
    case associateNode = 0x4A
    case syncThermometerList = 0x4B
}
