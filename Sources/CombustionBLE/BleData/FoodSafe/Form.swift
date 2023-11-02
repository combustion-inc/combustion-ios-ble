//  Form.swift

/*--
MIT License

Copyright (c) 2023 Combustion Inc.

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

enum Form: UInt8 {
    case intactCut = 0x00
    case notIntact = 0x01
    case ground = 0x02
    case stuffed = 0x03
    case liquid = 0x04
    case reserved5 = 0x05
    case reserved6 = 0x06
    case reserved7 = 0x07
    case reserved8 = 0x08
    case reserved9 = 0x09
    case reserved10 = 0x0A
    case reserved11 = 0x0B
    case reserved12 = 0x0C
    case reserved13 = 0x0D
    case reserved14 = 0x0E
    case reserved15 = 0x0F
    
    // 4 bit enum value
    static let MASK: UInt8 = 0x0F
}
