/*
* Copyright (c) 2019, Nordic Semiconductor
* All rights reserved.
*
* Redistribution and use in source and binary forms, with or without modification,
* are permitted provided that the following conditions are met:
*
* 1. Redistributions of source code must retain the above copyright notice, this
*    list of conditions and the following disclaimer.
*
* 2. Redistributions in binary form must reproduce the above copyright notice, this
*    list of conditions and the following disclaimer in the documentation and/or
*    other materials provided with the distribution.
*
* 3. Neither the name of the copyright holder nor the names of its contributors may
*    be used to endorse or promote products derived from this software without
*    specific prior written permission.
*
* THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
* ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
* WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
* IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
* INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
* NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
* PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
* WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
* ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
* POSSIBILITY OF SUCH DAMAGE.
*/

import CoreBluetooth

internal enum ButtonlessDFUOpCode : UInt8 {
    /// Jump from the main application to Secure DFU bootloader (DFU mode).
    case enterBootloader = 0x01
    /// Set a new advertisement name when jumping to Secure DFU bootloader (DFU mode).
    case setName         = 0x02
    /// The response code.
    case responseCode    = 0x20
    
    var code: UInt8 {
        return rawValue
    }
}

extension ButtonlessDFUOpCode : CustomStringConvertible {
    
    var description: String {
        switch self {
        case .enterBootloader:   return "Enter Bootloader"
        case .setName:           return "Set Name"
        case .responseCode:      return "Response Code"
        }
    }
}

internal enum ButtonlessDFUResultCode : UInt8 {
    /// The operation completed successfully.
    case success            = 0x01
    /// The provided opcode was invalid.
    case opCodeNotSupported = 0x02
    /// The operation failed.
    case operationFailed    = 0x04
    /// The requested advertisement name was invalid (empty or too long).
    /// Only available without bond support.
    case invalidAdvName     = 0x05
    /// The request was rejected due to an ongoing asynchronous operation.
    case busy               = 0x06
    /// The request was rejected because no bond was created.
    case notBonded          = 0x07
    
    // Note: When more result codes are added, the corresponding DFUError
    //       case needs to be added. See `error(ofType:)` method below.
    
    var code: UInt8 {
        return rawValue
    }
    
    func error(ofType remoteError: DFURemoteError) -> DFUError {
        return remoteError.with(code: code)
    }
}

extension ButtonlessDFUResultCode : CustomStringConvertible {
    
    var description: String {
        switch self {
        case .success:            return "Success"
        case .opCodeNotSupported: return "Operation not supported"
        case .operationFailed:    return "Operation failed"
        case .invalidAdvName:     return "Invalid advertisement name"
        case .busy:               return "Busy"
        case .notBonded:          return "Device not bonded"
        }
    }
    
}

internal enum ButtonlessDFURequest {
    case enterBootloader
    case set(name: String)
    
    var data: Data {
        switch self {
        case .enterBootloader:
            return Data([ButtonlessDFUOpCode.enterBootloader.code])
        case .set(let name):
            var data = Data([ButtonlessDFUOpCode.setName.code])
            data += UInt8(name.lengthOfBytes(using: String.Encoding.utf8))
            data += name.utf8
            return data
        }
    }
}

extension ButtonlessDFURequest : CustomStringConvertible {
    
    var description: String {
        switch self {
        case .enterBootloader: return "Enter Bootloader"
        case .set(let name):   return "Set Name (Name = \(name))"
        }
    }
    
}

internal struct ButtonlessDFUResponse {
    let opCode        : ButtonlessDFUOpCode
    let requestOpCode : ButtonlessDFUOpCode
    let status        : ButtonlessDFUResultCode

    init?(_ data: Data) {
        // The correct response is always 3 bytes long: Response Op Code,
        // Request Op Code and Status.
        guard data.count >= 3,
              let opCode = ButtonlessDFUOpCode(rawValue: data[0]),
              let requestOpCode = ButtonlessDFUOpCode(rawValue: data[1]),
              let status = ButtonlessDFUResultCode(rawValue: data[2]),
              opCode == .responseCode else {
            return nil
        }
        
        self.opCode        = opCode
        self.requestOpCode = requestOpCode
        self.status        = status
    }
}

extension ButtonlessDFUResponse : CustomStringConvertible {
    
    var description: String {
        return "Response (Op Code = \(requestOpCode), Status = \(status))"
    }
    
}
