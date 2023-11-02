//  Protein.swift

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

enum Protein: UInt8 {
    case _default = 0
    case chicken = 0x01
    case beef = 0x02
    case pork = 0x03
    case fish = 0x04
    case shellfish = 0x05
    case turkey = 0x06
    case lamb = 0x07
    case veal = 0x08
    case eggs = 0x09
    case dairy = 0x0A
    case vegetables = 0x0B
    case gameWild = 0x0C
    case gameFarmed = 0x0D
    case ostrichEmu = 0x0E
    
    // 6 bit enum value
    static let MASK: UInt8 = 0x3F
}





