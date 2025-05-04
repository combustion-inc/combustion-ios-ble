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

internal enum SecureDFUOpCode : UInt8 {
    case getProtocolVersion   = 0x0  // not supported by this library
    case createObject         = 0x01
    case setPRNValue          = 0x02
    case calculateChecksum    = 0x03
    case execute              = 0x04
 // case no-such-op-code      = 0x05
    case selectObject         = 0x06
    case getMtu               = 0x07 // not supported by this library
    case write                = 0x08 // not supported by this library
    case ping                 = 0x09 // not supported by this library
    case getHwVersion         = 0x0A // not supported by this library
    case getFwVersion         = 0x0B // not supported by this library
    case abort                = 0x0C
    case responseCode         = 0x60

    var code: UInt8 {
        return rawValue
    }
}

extension SecureDFUOpCode : CustomStringConvertible {
    
    var description: String {
        switch self {
        case .getProtocolVersion: return "Get Protocol Version"
        case .createObject:       return "Create Object"
        case .setPRNValue:        return "Set PRN Value"
        case .calculateChecksum:  return "Calculate Checksum"
        case .execute:            return "Execute"
        case .selectObject:       return "Select Object"
        case .getMtu:             return "Get MTU"
        case .write:              return "Write"
        case .ping:               return "Ping"
        case .getHwVersion:       return "Get Hw Version"
        case .getFwVersion:       return "Get Fw Version"
        case .abort:              return "Abort"
        case .responseCode:       return "Response Code"
        }
    }
}

internal enum SecureDFUExtendedErrorCode : UInt8 {
    case noError              = 0x00
    case wrongCommandFormat   = 0x02
    case unknownCommand       = 0x03
    case initCommandInvalid   = 0x04
    case fwVersionFailure     = 0x05
    case hwVersionFailure     = 0x06
    case sdVersionFailure     = 0x07
    case signatureMissing     = 0x08
    case wrongHashType        = 0x09
    case hashFailed           = 0x0A
    case wrongSignatureType   = 0x0B
    case verificationFailed   = 0x0C
    case insufficientSpace    = 0x0D
    
    // Note: When more result codes are added, the corresponding DFUError
    //       case needs to be added. See `error` property below.
    
    var code: UInt8 {
        return rawValue
    }
    
    var error: DFUError {
        return DFURemoteError.secureExtended.with(code: code)
    }
}

extension SecureDFUExtendedErrorCode : CustomStringConvertible {
    
    var description: String {
        switch self {
        case .noError:              return "No error"
        case .wrongCommandFormat:   return "Wrong command format"
        case .unknownCommand:       return "Unknown command"
        case .initCommandInvalid:   return "Init command was invalid"
        case .fwVersionFailure:     return "FW version check failed"
        case .hwVersionFailure:     return "HW version check failed"
        case .sdVersionFailure:     return "SD version check failed"
        case .signatureMissing:     return "Signature missing"
        case .wrongHashType:        return "Invalid hash type"
        case .hashFailed:           return "Hashing failed"
        case .wrongSignatureType:   return "Invalid signature type"
        case .verificationFailed:   return "Verification failed"
        case .insufficientSpace:    return "Insufficient space for upgrade"
        }
    }
    
}

internal enum SecureDFUProcedureType : UInt8 {
    case command = 0x01
    case data    = 0x02
}

extension SecureDFUProcedureType : CustomStringConvertible {
    
    var description: String{
        switch self{
            case .command:  return "Command"
            case .data:     return "Data"
        }
    }
    
}

internal enum SecureDFUImageType : UInt8 {
    case softdevice  = 0x00
    case application = 0x01
    case bootloader  = 0x02
}

extension SecureDFUImageType : CustomStringConvertible {
    
    var description: String{
        switch self{
            case .softdevice:  return "Soft Device"
            case .application: return "Application"
            case .bootloader:  return "Bootloader"
        }
    }
    
}

internal enum SecureDFURequest {
    case getProtocolVersion
    case createCommandObject(withSize: UInt32)
    case createDataObject(withSize: UInt32)
    case selectCommandObject
    case selectDataObject
    case setPacketReceiptNotification(value: UInt16)
    case calculateChecksumCommand
    case executeCommand
    case getMtu
    case write(bytes: Data)
    case ping(id: UInt8)
    case getHwVersion
    case getFwVersion(image: SecureDFUImageType)
    case abort

    var data: Data {
        switch self {
        case .getProtocolVersion:
            return Data([SecureDFUOpCode.getProtocolVersion.code])
        case .createDataObject(let size):
            var data = Data([SecureDFUOpCode.createObject.code, SecureDFUProcedureType.data.rawValue])
            data += size.littleEndian
            return data
        case .createCommandObject(let size):
            var data = Data([SecureDFUOpCode.createObject.code, SecureDFUProcedureType.command.rawValue])
            data += size.littleEndian
            return data
        case .setPacketReceiptNotification(let size):
            var data = Data([SecureDFUOpCode.setPRNValue.code])
            data += size.littleEndian
            return data
        case .calculateChecksumCommand:
            return Data([SecureDFUOpCode.calculateChecksum.code])
        case .executeCommand:
            return Data([SecureDFUOpCode.execute.code])
        case .selectCommandObject:
            return Data([SecureDFUOpCode.selectObject.code, SecureDFUProcedureType.command.rawValue])
        case .selectDataObject:
            return Data([SecureDFUOpCode.selectObject.code, SecureDFUProcedureType.data.rawValue])
        case .getMtu:
            return Data([SecureDFUOpCode.getMtu.code])
        case .write(let bytes):
            var data = Data([SecureDFUOpCode.write.code])
            data += bytes
            data += UInt16(bytes.count).littleEndian
            return data
        case .ping(let id):
            return Data([SecureDFUOpCode.ping.code, id])
        case .getHwVersion:
            return Data([SecureDFUOpCode.getHwVersion.code])
        case .getFwVersion(let image):
            return Data([SecureDFUOpCode.getFwVersion.code, image.rawValue])
        case .abort:
            return Data([SecureDFUOpCode.abort.code])
        }
    }
}

extension SecureDFURequest : CustomStringConvertible {

    var description: String {
        switch self {
        case .getProtocolVersion:            return "Get Protocol Version (Op Code = 0)"
        case .createCommandObject(let size): return "Create Command Object (Op Code = 1, Type = 1, Size: \(size)b)"
        case .createDataObject(let size):    return "Create Data Object (Op Code = 1, Type = 2, Size: \(size)b)"
        case .setPacketReceiptNotification(let number):
                                             return "Packet Receipt Notif Req (Op Code = 2, Value = \(number))"
        case .calculateChecksumCommand:      return "Calculate Checksum (Op Code = 3)"
        case .executeCommand:                return "Execute Object (Op Code = 4)"
        case .selectCommandObject:           return "Select Command Object (Op Code = 6, Type = 1)"
        case .selectDataObject:              return "Select Data Object (Op Code = 6, Type = 2)"
        case .getMtu:                        return "Get MTU (Op Code = 7)"
        case .write(let bytes):              return "Write (Op Code = 8, Data = 0x\(bytes.hexString), Length = \(bytes.count))"
        case .ping(let id):                  return "Ping (Op Code = 9, ID = \(id))"
        case .getHwVersion:                  return "Get HW Version (Op Code = 10)"
        case .getFwVersion(let image):       return "Get FW Version (Op Code = 11, Type = \(image.rawValue))"
        case .abort:                         return "Abort (Op Code = 12)"
        }
    }
    
}

internal enum SecureDFUResultCode : UInt8 {
    case invalidCode           = 0x0
    case success               = 0x01
    case opCodeNotSupported    = 0x02
    case invalidParameter      = 0x03
    case insufficientResources = 0x04
    case invalidObject         = 0x05
    case signatureMismatch     = 0x06
    case unsupportedType       = 0x07
    case operationNotPermitted = 0x08
    case operationFailed       = 0x0A
    case extendedError         = 0x0B
    
    // Note: When more result codes are added, the corresponding DFUError
    //       case needs to be added. See `error` property below.
    
    var code: UInt8 {
        return rawValue
    }
    
    var error: DFUError {
        return DFURemoteError.secure.with(code: code)
    }
}

extension SecureDFUResultCode : CustomStringConvertible {
    
    var description: String {
        switch self {
            case .invalidCode:           return "Invalid code"
            case .success:               return "Success"
            case .opCodeNotSupported:    return "Operation not supported"
            case .invalidParameter:      return "Invalid parameter"
            case .insufficientResources: return "Insufficient resources"
            case .invalidObject:         return "Invalid object"
            case .signatureMismatch:     return "Signature mismatch"
            case .operationNotPermitted: return "Operation not permitted"
            case .unsupportedType:       return "Unsupported type"
            case .operationFailed:       return "Operation failed"
            case .extendedError:         return "Extended error"
        }
    }
    
}

internal typealias SecureDFUResponseCallback = (_ response : SecureDFUResponse) -> Void

internal struct SecureDFUResponse {
    let opCode        : SecureDFUOpCode
    let requestOpCode : SecureDFUOpCode
    let status        : SecureDFUResultCode
    let maxSize       : UInt32?
    let offset        : UInt32?
    let crc           : UInt32?
    let error         : SecureDFUExtendedErrorCode?
    
    init?(_ data: Data) {
        // The response has at least 3 bytes.
        guard data.count >= 3,
              let opCode = SecureDFUOpCode(rawValue: data[0]),
              let requestOpCode = SecureDFUOpCode(rawValue: data[1]),
              let status = SecureDFUResultCode(rawValue: data[2]),
              opCode == .responseCode else {
            return nil
        }
        
        switch status {
        case .success:
            // Parse response data in case of a success.
            switch requestOpCode {
            case .selectObject:
                // The correct response for Select Object has additional 12 bytes:
                // Max Object Size, Offset and CRC.
                guard data.count >= 15 else { return nil }
                let maxSize : UInt32 = data.asValue(offset: 3)
                let offset  : UInt32 = data.asValue(offset: 7)
                let crc     : UInt32 = data.asValue(offset: 11)
                
                self.maxSize = maxSize
                self.offset  = offset
                self.crc     = crc
                self.error   = nil
            case .calculateChecksum:
                // The correct response for Calculate Checksum has additional 8 bytes:
                // Offset and CRC.
                guard data.count >= 11 else { return nil }
                let offset : UInt32 = data.asValue(offset: 3)
                let crc    : UInt32 = data.asValue(offset: 7)
                
                self.maxSize = nil
                self.offset  = offset
                self.crc     = crc
                self.error   = nil
            default:
                self.maxSize = nil
                self.offset  = nil
                self.crc     = nil
                self.error   = nil
            }
        case .extendedError:
            // If extended error was received, the 4th byte is the extended error code.
            guard data.count >= 4,
                  let error = SecureDFUExtendedErrorCode(rawValue: data[3]) else {
                return nil
            }
            
            self.maxSize = nil
            self.offset  = nil
            self.crc     = nil
            self.error   = error
        default:
            self.maxSize = nil
            self.offset  = nil
            self.crc     = nil
            self.error   = nil
        }
        
        self.opCode        = opCode
        self.requestOpCode = requestOpCode
        self.status        = status
    }
}

extension SecureDFUResponse : CustomStringConvertible {
    
    var description: String {
        switch status {
        case .extendedError:
            if let error = error {
                return "Response (Op Code = \(requestOpCode), Status = \(status), Extended Error \(error.rawValue) = \(error))"
            }
            return "Response (Op Code = \(requestOpCode), Status = \(status), Unsupported Extended Error value)"
        case .success:
            switch requestOpCode {
            case .selectObject:
                // Max size for a command object is usually around 256. Let's say 1024,
                // just to be sure. This is only for logging, so may be wrong.
                return String(format: "\(maxSize! > 1024 ? "Data" : "Command") object selected (Max size = \(maxSize!), Offset = \(offset!), CRC = %08X)", crc!)
            case .calculateChecksum:
                return String(format: "Checksum (Offset = \(offset!), CRC = %08X)", crc!)
            default:
                // Other responses are either not logged, or logged by the service or executor,
                // so this 'default' should never be called.
                break
            }
            fallthrough
        default:
            return "Response (Op Code = \(requestOpCode), Status = \(status))"
        }
    }
    
}

internal struct SecureDFUPacketReceiptNotification {
    let opCode        : SecureDFUOpCode
    let requestOpCode : SecureDFUOpCode
    let resultCode    : SecureDFUResultCode
    let offset        : UInt32
    let crc           : UInt32

    init?(_ data: Data) {
        guard data.count >= 11,
              let opCode = SecureDFUOpCode(rawValue: data[0]),
              let requestOpCode = SecureDFUOpCode(rawValue: data[1]),
              let resultCode = SecureDFUResultCode(rawValue: data[2]),
              opCode == .responseCode,
              requestOpCode == .calculateChecksum,
              resultCode == .success else {
            return nil
        }
        
        self.opCode        = opCode
        self.requestOpCode = requestOpCode
        self.resultCode    = resultCode
        
        let offset : UInt32 = data.asValue(offset: 3)
        let crc    : UInt32 = data.asValue(offset: 7)

        self.offset = offset
        self.crc = crc
    }
}

extension SecureDFUPacketReceiptNotification : CustomStringConvertible {
    
    var description: String {
        return String(format: "Packet Receipt Notification (Offset = \(offset), CRC = %08X)", crc)
    }
    
}
