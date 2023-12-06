//  Product.swift

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

public enum SimplifiedModeProduct: UInt16, CaseIterable {
    case _default = 0x0000
    case anyPoultry = 0x0001
    case beefCuts = 0x0002
    case porkCuts = 0x0003
    case vealCuts = 0x0004
    case lambCuts = 0x0005
    case groundMeats = 0x0006
    case hamFreshOrSmoked = 0x0007
    case hamCookedAndReheated = 0x0008
    case eggs = 0x0009
    case fishAndShellfish = 0x000A
    case leftovers = 0x000B
    case casseroles = 0x000C

    //0x000D - 0x03FF: Reserved
    
    // 10 bit enum value
    static let MASK: UInt16 = 0x3FF
}

extension SimplifiedModeProduct {
    public func toString() -> String {
        switch(self) {
        case ._default:
            return "Default"
        case .anyPoultry:
            return "Any Poultry"
        case .beefCuts:
            return "Beef Cuts"
        case .porkCuts:
            return "Pork Cuts"
        case .vealCuts:
            return "Veal Cuts"
        case .lambCuts:
            return "Lamb Cuts"
        case .groundMeats:
            return "Ground Meats"
        case .hamFreshOrSmoked:
            return "Ham, Fresh or Smoked"
        case .hamCookedAndReheated:
            return "Ham, Cooked and Reheated"
        case .eggs:
            return "Eggs"
        case .fishAndShellfish:
            return "Fish and Shellfish"
        case .leftovers:
            return "Leftovers"
        case .casseroles:
            return "Casseroles"
        }
    }
}


public enum IntegratedModeProduct: UInt16, CaseIterable {
    // Default value is defined in documentation, but
    // not selectable in application
    // 0x0000: Default
    
    case beef = 0x0001
    case beefGround = 0x0002
    case chicken = 0x0003
    case chickenGround = 0x0004
    case pork = 0x0005
    case porkGround = 0x0006
    case ham = 0x0007
    case hamGround = 0x0008
    case turkey = 0x0009
    case turkeyGround = 0x000A
    case lamb = 0x000B
    case lambGround = 0x000C
    case fish = 0x000D
    case fishGround = 0x000E
    case dairyMilkLessThan10PctFat = 0x000F
    
    // 0x0010 - 0x03FE: Resevered
    
    case custom = 0x03FF
    
    // 10 bit enum value
    static let MASK: UInt16 = 0x3FF
}

extension IntegratedModeProduct {
    public func toString() -> String {
        switch self {
        case .beef: return "Beef"
        case .beefGround: return "Beef (Ground)"
        case .chicken: return "Chicken"
        case .chickenGround: return "Chicken (Ground)"
        case .pork: return "Pork"
        case .porkGround: return "Pork (Ground)"
        case .ham: return "Ham"
        case .hamGround: return "Ham (Ground)"
        case .turkey: return "Turkey"
        case .turkeyGround: return "Turkey (Ground)"
        case .lamb: return "Lamb"
        case .lambGround: return "Lamb (Ground)"
        case .fish: return "Fish"
        case .fishGround: return "Fish (Ground)"
        case .dairyMilkLessThan10PctFat: return "Dairy - Milk (<10% fat)"
        case .custom: return "Custom"
        }
    }
}
