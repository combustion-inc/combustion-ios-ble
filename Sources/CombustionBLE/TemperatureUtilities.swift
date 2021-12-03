//
//  TemperatureUtilities.swift
//  Combustion_iOS
//
//  Created by Jason Machacek on 10/24/21.
//

import Foundation

// MARK: Temperature Utitilies

/// Converts specified celsius value to fahrenheit
func fahrenheit(celsius: Double) -> Double {
    return celsius * 9.0 / 5.0 + 32.0
}

/// Converts specified fahrenheit value to celsius
func celsius(fahrenheit: Double) -> Double {
    return (fahrenheit - 32.0) * 5.0 / 9.0
}
