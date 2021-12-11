# Combustion Inc. Predictive Thermometer BLE Library

## Overview

This package enables communication with Combustion Inc. Predictive Thermometers. It uses Apple's Combine framework, subclassing `ObservableObject` to enable reactive UI development in SwiftUI (and is compatible with Storyboard approaches as well).

Discovered probes show up as instances of the `Probe` class in the `DeviceManager.shared.probes` dictionary, and their temperatures and other data are continually updated by incoming BLE advertising messages. Additionally, calling `connect()` on an individual `Probe` object will cause the framework to maintain a connection to that device, and will automatically download all logged temperature records on the device.

## About Combustion Inc.

We build nice things that make cooking more enjoyable. Like a thermometer that's wireless, oven-safe, and uses machine-learning to do what no other thermometer can: predict your food’s cooking and resting times with uncanny accuracy. 

Our Predictive Thermometer's eight temperature sensors measure the temp outside and inside the food, in the center and at the surface, and nearly everywhere in between. So you know what’s really happening in and around your food. There's a display Timer that's big and bold—legible even through tears of joy and chopped onions—and a mobile app. 

Or you can create your own mobile app to work with the Predictive Thermometer using this open source library.

<img src="https://combustion.inc/assets/img/product_rendering/probe-and-timer-large.jp2" alt="Probe and Timer" width="400"/>

Visit [www.combustion.inc](https://www.combustion.inc) to sign up to be notified when they're available to order in early 2022.

Head on over to our [FAQ](https://combustion.inc/faq.html) for more product details.

Ask us a quick question on [Twitter](https://twitter.com/intent/tweet?screen_name=inccombustion).

Email [hello@combustion.inc](mailto:hello@combustion.inc) for OEM partnership information.



## Example project

An example iOS app illustrating the use of this framework is available in the [combustion-ios-example](https://github.com/combustion-inc/combustion-ios-example) repository.

## Usage information

### Swift Package Manager

Simply add this [Github repository](https://github.com/combustion-inc/combustion-ios-ble) to your project via [Swift Package Manager](https://developer.apple.com/documentation/swift_packages/adding_package_dependencies_to_your_app).

### Target capabilities

The following Capabilities need to be added to your Target (Signing & Capabilities tab in Target settings):

- Background BLE services
  - Enable `Uses Bluetooth LE Accessories`

### Info.plist settings

Additionally, the following entries must be added to your project's `Info.plist`:

- Key: `Privacy - Bluetooth Always Usage Description`

  - Value: Description of reason for Bluetooth access, e.g. "Bluetooth is used to communicate with hardware products."

- Key: `Privacy - Bluetooth Peripheral Usage Description`

  - Value: Description of reason for Bluetooth access, e.g. "Bluetooth is used to communicate with hardware products."

## Important Classes

The following classes provide key functionality to apps incorporating this framework.

### `DeviceManager`

`DeviceManager` is an observable singleton class that maintains a dictionary of `Probe` objects that have been discovered over BLE.

#### Important members

- `probes` - Observable dictionary of probes (key is a `String` BLE UUID identifier, value is the `Probe` object)
- `getProbes()` - Function that returns array representation of the `Probe` objects in the `probes` dictionary.

### `Probe` (subclass of `Device`)

An instance of the `Probe` class representes an individual temperature probe that has been discovered via its advertising data. These are retrieved from the `DeviceManager.shared.probes` dictionary.

### Important members

- `serialNumber` - The Probe's unique serial number
- `name` - String format of probe serial number
- `macAddress` - Probe's MAC address
- `macAddressString` - String representation of Probe's MAC address
- `batteryLevel` - Battery level as reported by probe *NOTE: This is not yet implemented in probe firmware and will likely change to a boolean 'battery low' flag in the near future.*
- `currentTemperatures` - `ProbeTemperatures` struct containing the most recent temperatures read by the Probe. 
  - `currentTemperatures.values` - Array of these temperatures, in celsius, where `values[0]` is temperature sensor T1, and `values[7]` is temperature sensor T8.
    - T1 - High-precision temperature sensor in tip of probe
    - T2 - High-precision temperature sensor
    - T3 - MCU temperature sensor
    - T4 - High-precision temperature sensor
    - T5 - High-temperature thermistor
    - T6 - High-temperature thermistor
    - T7 - High-temperature thermistor
    - T8 - High-temperature thermistor on handle tip measuring ambient

- `id` - iOS-provided UUID for the device

- `rssi` - Signal strength between Probe and iOS device

- `maintainingConnection` - Whether the app is currently attempting to maintain a connection with the `Probe`, as directed by the `connect()` and `disconnect()` methods.

- `connect()` - Attempts to connect to device, and instructs framework to attempt to maintain a connection to this probe if it is lost.

- `disconnect()` - Instruct framework to disconnect from this probe, and to no longer attempt to maintain a connection to it.

- `stale` - `true` if no advertising data or notifications have been received from the Probe within the "staleness timeout" (15 seconds), or `false` if recent data has been received.

- `status` - `DeviceStatus` struct containing device status information.
  - `minSequenceNumber` - Minimum sequence number of log records stored on the probe
  - `maxSequenceNumber` - Maximum sequence number of log records stored on the probe

- `logsUpToDate` - Boolean value that indicates whether all log sequence numbers contained in the probe (determined by the `status` sequence number range) have been successfully retrieved and stored in the app's memory.

- `temperatureLog` - `ProbeTemperatureLog` class instance containing all logged temperatures that have been retrieved from the device, and logic that coordinates automatically retrieving all past records when connected to a Probe.
  - Individual logged temperatures are provided in the `temperatureLog.dataPoints` array. These are instances of the struct `LoggedProbeDataPoint`, which contains the point's sequence number and corresponding `ProbeTemperatures` struct as explained above.

## Useful functions

The framework also provides `celsius()` and `fahrenheit()` functions that convert temperatures between these two formats.

## Common usage examples

### Importing this framework

To use the Combustion BLE framework in your own Swift file, import it:

```swift
import CombustionBLE
```

### Rendering list of probes

In SwiftUI, a list of probes can be rendered like so:

```swift
struct EngineeringProbeList: View {
    @ObservedObject var deviceManager = DeviceManager.shared
    
    var body: some View {
        NavigationView {
            List {
                ForEach(deviceManager.probes.keys.sorted(), id: \.self) { key in
                    if let probe = deviceManager.probes[key] {
                        NavigationLink(destination: EngineeringProbeDetails(probe: probe)) {
                            EngineeringProbeRow(probe: probe)
                        }
                    }
                }
            }
            .navigationTitle("Probes")
        }
    }
}
```

## Framework features coming soon

The following features are planned for near-term development but are not yet implemented in this version of the Combustion BLE Framework.

### Set ring color

The framework will provide functions allowing a probe's identifying silicone ring color to be configured by the user (colors TBA).

### Set numeric ID

The framework will provide functions allowing a Probe's numeric ID (1-8) to be configured by the user.

### Firmware update

The framework will provide methods for updating a Probe's firmware with a signed firmware image.

### Instant Read

The framework will include additional features for differentiating Instant Read messages from logged temperatures.
