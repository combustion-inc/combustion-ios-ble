//  EWMA.swift

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

class EWMA {
    private var alpha: Float
    private var ewma: Float
    private var seeded: Bool
    
    /// Construct a new Exponentially Weighted Moving Average class.
    ///
    /// - Parameters:
    ///   - span: Interpreted as an N-sample moving average, where span is N.
    ///           - Note: span must be >= 1. A span of zero is forced to be 1.
    init(span: UInt32) {
        alpha = span == 0 ? 1.0 : 2.0 / (Float(span) + 1.0)
        ewma = 0.0
        seeded = false
    }
    
    /// Gets the current value.
    ///
    /// - Returns: Current value for the moving average.
    func get() -> Float {
        return ewma
    }
    
    /// Adds a sample to the moving average.
    ///
    /// - Parameter value: The value to add.
    func put(value: Float) {
        if seeded {
            ewma = alpha * value + (1.0 - alpha) * ewma
        } else {
            ewma = value
            seeded = true
        }
    }
    
    /// Forces the current value to the input.
    ///
    /// - Parameter ewma: The value to set.
    func set(ewma: Float) {
        seeded = true
        self.ewma = ewma
    }
    
    /// Resets the moving average.
    func reset() {
        seeded = false
        ewma = 0.0
    }
    
    /// Steps the current value of the average by the input. Only steps
    /// if the value has been previously seeded.
    ///
    /// - Parameter value: The step value.
    func step(value: Float) {
        if seeded {
            ewma += value
        }
    }
}
