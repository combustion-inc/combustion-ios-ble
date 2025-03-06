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
--*/

import CoreBluetooth

enum BleCharacteristic: String {
    case deviceStatus = "00000101-CAAB-3792-3D44-97AE51C1407A"
    case dfu = "8EC90003-F315-4F60-9FB8-838830DAEA50"
    case firmwareVersion = "2a26"
    case hardwareRevision = "2a27"
    case modelNumber = "2a24"
    case serialNumber = "2a25"
    case uartRx = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
    case uartTx = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
}

extension BleCharacteristic {
    var uuid: CBUUID {
        return CBUUID(string: rawValue)
    }

    static func from(_ char: CBCharacteristic) -> BleCharacteristic? {
        return BleCharacteristic(rawValue: char.uuid.uuidString)
    }
}
