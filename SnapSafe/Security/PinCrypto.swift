//
//  PinCrypto.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/2/25.
//

import Foundation
import Argon2Kit


final class PinCrypto {
    static let DEFAULT_ITERATIONS: UInt32 = 5
    static let DEFAULT_COST_KIB: UInt32   = 65_536 // 64 MiB

    private let iterations: UInt32
    private let costKiB: UInt32

    init(iterations: UInt32 = DEFAULT_ITERATIONS, costKiB: UInt32 = DEFAULT_COST_KIB) {
        self.iterations = iterations
        self.costKiB = costKiB
    }

    /// Hashes PIN bound to `deviceId` (pinBytes + deviceIdBytes), returning base64url-wrapped Argon2 **encoded** string + salt.
    func hashPin(pin: String, deviceId: Data) -> HashedPin {
        let salt = Data.random(bytes: 16)

        var password = Data(pin.utf8)
        password.append(deviceId)

        let digest = try! Argon2.hash(
            password: password,
            salt: salt,
            iterations: iterations,
            memory: costKiB,
            type: .i,
        )

        return HashedPin(
            hash: digest.encodedData.base64URLEncodedString(),
            salt: salt.base64URLEncodedString()
        )
    }

    /// Verifies `pin` against stored Argon2 **encoded** string (which we stored as base64url) using the same pin+deviceId binding.
    func verifyPin(pin: String, stored: HashedPin, deviceId: Data) -> Bool {
        var password = Data(pin.utf8)
        password.append(deviceId)

        // Decode the stored Argon2 *encoded string* from base64url back to UTF-8.
        guard
            let encodedData = Data(base64URLString: stored.hash)
        else {
            return false
        }

        return try! Argon2.verify(password: password, encodedHash: encodedData)
    }
}
