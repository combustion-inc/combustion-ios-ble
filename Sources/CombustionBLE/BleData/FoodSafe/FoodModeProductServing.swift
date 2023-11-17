//  FoodModeProductServing.swift

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

public enum FoodModeProductServing: Equatable {
    case simplified(product: SimplifiedModeProduct, serving: Serving)
    case integrated(product: IntegratedModeProduct, serving: Serving)
}

extension FoodModeProductServing {
    
    /// Help function to determine if Food Safe mode has been set
    /// - return true if Safe mode has been set
    public func isSafeModeSet() -> Bool {
        switch(self) {
        case .integrated:
            return true
        case .simplified(let product, _):
            return product != ._default
        }
    }
    
    public func mode() -> FoodSafeMode {
        switch self {
        case .simplified:
            return .simplified
        case .integrated:
            return .integrated
        }
    }
    
    public func serving() -> Serving {
        switch self {
        case .simplified(_, let serving):
            return serving
        case .integrated(_, let serving):
            return serving
        }
    }
}

extension FoodModeProductServing {
    private enum Constants {
        // Data length
        static let RAW_DATA_SIZE = 2
    }
    
    func toRaw() -> Data {
        var data = Data(count: Constants.RAW_DATA_SIZE)
        
        switch(self) {
        case .simplified(product: let product, serving: let serving):
            data[0] = FoodSafeMode.simplified.rawValue | UInt8(product.rawValue << 3)
            data[1] = UInt8(product.rawValue >> 5) | (serving.rawValue << 5)
            
        case .integrated(product: let product, serving: let serving):
            data[0] = FoodSafeMode.integrated.rawValue | UInt8(product.rawValue << 3)
            data[1] = UInt8(product.rawValue >> 5) | (serving.rawValue << 5)
        }
        
        return data
    }
    
    static func fromRaw(data: Data) -> FoodModeProductServing? {
        guard data.count >= Constants.RAW_DATA_SIZE else { return nil }
        
        // Food Safe Mode - 3 bits
        let rawMode = data[0] & FoodSafeMode.MASK
        
        // Product - 10 bits
        let rawProduct = ((UInt16(data[0]) & 0x00F8) >> 3) | ((UInt16(data[1]) & 0x001F) << 5)
        
        // Serving - 3 bits
        let rawServing = (data[1] >> 5) & Serving.MASK
        let serving = Serving(rawValue: rawServing) ?? .servedImmediately
        
        switch(FoodSafeMode(rawValue: rawMode)) {
            
        case .simplified:
            let product = SimplifiedModeProduct(rawValue: rawProduct) ?? ._default
            return .simplified(product: product, serving: serving)
            
        case .integrated:
            let product = IntegratedModeProduct(rawValue: rawProduct) ?? ._default
            return .integrated(product: product, serving: serving)
            
        default:
            return nil
        }
    }
}
