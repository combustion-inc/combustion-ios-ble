//  TemperatureUtilities.swift

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

// MARK: Temperature Utitilies

/// Converts specified celsius value to fahrenheit
/// - parameter celsius: Temperature in degrees celsius
/// - returns: Temperature in degrees fahrenheit
public func fahrenheit(celsius: Double) -> Double {
    return celsius * 9.0 / 5.0 + 32.0
}

/// Converts specified fahrenheit value to celsius
/// - parameter fahrenheit: Temperature in degrees fahrenheit
/// - returns: Temperature in degrees celsius
public func celsius(fahrenheit: Double) -> Double {
    return (fahrenheit - 32.0) * 5.0 / 9.0
}
