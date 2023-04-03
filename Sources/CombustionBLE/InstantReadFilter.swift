//  InstantReadFilter.swift
//  Smoothing filter for Instant Read readings.

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

typealias InstantReadTemperatures = (Double, Double)

internal class InstantReadFilter {
    private enum Units {
        case celsius
        case fahrenheit
    }
    
    private enum Constants {
        static let DEADBAND_RANGE_IN_CELSIUS = 0.05
    }
    
    /// The filtered instant read values, with the first element in the pair being the
    /// temperature in Celsius and the second being in Fahrenheit.
    public private(set) var values: InstantReadTemperatures? = nil
    
    /// Adds the temeprature in celsius to the instant read filter. Upon completion of the function
    /// the updated filtered values are in `values`.
    func addReading(temperatureInCelsius: Double?) {
        if let temperatureInCelsius = temperatureInCelsius {
            self.values = (
                calculateFilteredTemperature(
                    temperatureInCelsius: temperatureInCelsius,
                    currentDisplayTemperature: values?.0,
                    units: .celsius
                ),
                calculateFilteredTemperature(
                    temperatureInCelsius: temperatureInCelsius,
                    currentDisplayTemperature: values?.1,
                    units: .fahrenheit
                )
            )
        } else {
            values = nil
        }
    }
    
    private func calculateFilteredTemperature(temperatureInCelsius: Double,
                                              currentDisplayTemperature: Double?,
                                              units: Units ) -> Double {
        
        // Set deadband based on selected units
        let deadbandRange = (units == .celsius ?
                             Constants.DEADBAND_RANGE_IN_CELSIUS :
                             celsiusToFahrenheitDifference(Constants.DEADBAND_RANGE_IN_CELSIUS))
        
        let temperature = (units == .celsius ?
                           temperatureInCelsius :
                            celsiusToFahrenheitAbsolute(temperatureInCelsius))
        
        let displayTemperature = currentDisplayTemperature ?? temperature.rounded()
        
        let upperBound = displayTemperature + 0.5 + deadbandRange
        let lowerBound = displayTemperature - 0.5 - deadbandRange
        
        if (temperature > upperBound || temperature < lowerBound) {
            return temperature.rounded()
        }
        
        return displayTemperature
    }

     private func celsiusToFahrenheitDifference(_ celsius: Double) -> Double {
         return (celsius * 9.0) / 5.0
     }

     private func celsiusToFahrenheitAbsolute(_ celsius: Double) -> Double {
         return celsiusToFahrenheitDifference(celsius) + 32.0
     }
}
