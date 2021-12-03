//
//  ProbeTemperatures.swift
//  Needle
//
//  Created by Jesse Johnston on 3/1/21.
//  Copyright © 2021 Combustion Inc. All rights reserved.
//

import Foundation

struct ProbeTemperatures: Equatable {
    let values: [Double]
}

extension ProbeTemperatures {

    /// Parses temperature data from reversed set of bytes
    static func fromReversed(bytes: [UInt8]) -> ProbeTemperatures {
        var rawTemps: [UInt16] = []
        
        // Add the temperatures in reverse order (reversed as it's a little-endian packed bitfield)
        rawTemps.insert(UInt16(bytes[0]  & 0xFF) <<  5 | UInt16(bytes[1]  & 0xF8) >> 3, at: 0 )
        rawTemps.insert(UInt16(bytes[1]  & 0x07) << 10 | UInt16(bytes[2]  & 0xFF) << 2 | UInt16(bytes[3]  & 0xC0) >> 6, at: 0 )
        rawTemps.insert(UInt16(bytes[3]  & 0x3F) <<  7 | UInt16(bytes[4]  & 0xFE) >> 1, at: 0 )
        rawTemps.insert(UInt16(bytes[4]  & 0x01) << 12 | UInt16(bytes[5]  & 0xFF) << 4 | UInt16(bytes[6]  & 0xF0) >> 4, at: 0 )
        rawTemps.insert(UInt16(bytes[6]  & 0x0F) <<  9 | UInt16(bytes[7]  & 0xFF) << 1 | UInt16(bytes[8]  & 0x80) >> 7, at: 0 )
        rawTemps.insert(UInt16(bytes[8]  & 0x7F) <<  6 | UInt16(bytes[9]  & 0xFC) >> 2, at: 0 )
        rawTemps.insert(UInt16(bytes[9]  & 0x03) << 11 | UInt16(bytes[10] & 0xFF) << 3 | UInt16(bytes[11] & 0xE0) >> 5, at: 0 )
        rawTemps.insert(UInt16(bytes[11] & 0x1F) <<  8 | UInt16(bytes[12] & 0xFF) >> 0, at: 0 )

        let temperatures = rawTemps.map { Double($0) * 0.05 - 20.0 }
        return ProbeTemperatures(values: temperatures)
    }


    /// Parses temperature data from raw data buffer
    static func fromRawData(data: Data) -> ProbeTemperatures {

        // Reverse the byte order (this is a little-endian packed bitfield)
        var bytes : [UInt8] = []
        for byte in data {
            bytes.insert(byte as UInt8, at: 0)
        }
        
        return fromReversed(bytes: bytes)
    }
}


extension ProbeTemperatures {
    // Generates fake data for UI previews
    static func withFakeData() -> ProbeTemperatures {
        let temperatures : [Double] = [
            50.0,
            60.0,
            70.0,
            80.0,
            100.0,
            200.0,
            300.0,
            400.0
        ]
        return ProbeTemperatures(values: temperatures)
    }
}
