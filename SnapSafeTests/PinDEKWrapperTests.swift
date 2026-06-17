//
//  PinDEKWrapperTests.swift
//  SnapSafeTests
//
//  Created by Claude on 2026-05-31.
//
//  Tests the C1 fix: the DEK is wrapped under a PIN-derived key (AES-GCM) so the
//  PIN is *cryptographically* required to recover the DEK, not just procedurally
//  checked. This unit is keychain-free (CryptoKit + PBKDF2) and runs on the
//  simulator / CI. See design/2026-05-31-c1-pin-binding-analysis.

import CryptoKit
import Foundation
import XCTest

@testable import SnapSafe

final class PinDEKWrapperTests: XCTestCase {

    private let salt = Data("a-16-byte-salt!!".utf8)
    private let deviceId = Data("device-identifier-bytes".utf8)

    // MARK: - PIN key derivation

    func test_derivePinKey_isDeterministicForSameInputs() throws {
        let k1 = try PinDEKWrapper.derivePinKey(plainPin: "1234", salt: salt, deviceId: deviceId)
        let k2 = try PinDEKWrapper.derivePinKey(plainPin: "1234", salt: salt, deviceId: deviceId)
        XCTAssertEqual(k1.rawBytes, k2.rawBytes, "Same PIN/salt/device must derive the same key")
    }

    func test_derivePinKey_differsForDifferentPins() throws {
        let k1 = try PinDEKWrapper.derivePinKey(plainPin: "1234", salt: salt, deviceId: deviceId)
        let k2 = try PinDEKWrapper.derivePinKey(plainPin: "9999", salt: salt, deviceId: deviceId)
        XCTAssertNotEqual(k1.rawBytes, k2.rawBytes, "Different PINs must derive different keys")
    }

    func test_derivePinKey_differsForDifferentDevices() throws {
        let k1 = try PinDEKWrapper.derivePinKey(plainPin: "1234", salt: salt, deviceId: deviceId)
        let k2 = try PinDEKWrapper.derivePinKey(plainPin: "1234", salt: salt, deviceId: Data("other-device".utf8))
        XCTAssertNotEqual(k1.rawBytes, k2.rawBytes, "Different devices must derive different keys")
    }

    // MARK: - Wrap / unwrap round trip

    func test_wrapThenUnwrap_withSamePin_recoversDEK() throws {
        let dek = try randomDEK()
        let pinKey = try PinDEKWrapper.derivePinKey(plainPin: "1234", salt: salt, deviceId: deviceId)

        let wrapped = try PinDEKWrapper.wrap(dek: dek, pinKey: pinKey)
        let recovered = try PinDEKWrapper.unwrap(payload: wrapped, pinKey: pinKey)

        XCTAssertEqual(recovered, dek, "Unwrapping with the correct PIN key must recover the exact DEK")
    }

    func test_unwrap_withWrongPin_throwsWrongPin() throws {
        let dek = try randomDEK()
        let rightKey = try PinDEKWrapper.derivePinKey(plainPin: "1234", salt: salt, deviceId: deviceId)
        let wrongKey = try PinDEKWrapper.derivePinKey(plainPin: "0000", salt: salt, deviceId: deviceId)

        let wrapped = try PinDEKWrapper.wrap(dek: dek, pinKey: rightKey)

        XCTAssertThrowsError(try PinDEKWrapper.unwrap(payload: wrapped, pinKey: wrongKey)) { error in
            XCTAssertEqual(error as? CryptoError, CryptoError.wrongPin,
                           "A wrong PIN must surface as CryptoError.wrongPin, not a raw CryptoKit error")
        }
    }

    // MARK: - Wrapped-blob properties

    func test_wrap_doesNotLeakDEKInPlaintext() throws {
        let dek = try randomDEK()
        let pinKey = try PinDEKWrapper.derivePinKey(plainPin: "1234", salt: salt, deviceId: deviceId)

        let wrapped = try PinDEKWrapper.wrap(dek: dek, pinKey: pinKey)

        XCTAssertFalse(wrapped.range(of: dek) != nil, "Wrapped payload must not contain the raw DEK bytes")
    }

    func test_wrap_isNonDeterministic_dueToRandomNonce() throws {
        let dek = try randomDEK()
        let pinKey = try PinDEKWrapper.derivePinKey(plainPin: "1234", salt: salt, deviceId: deviceId)

        let a = try PinDEKWrapper.wrap(dek: dek, pinKey: pinKey)
        let b = try PinDEKWrapper.wrap(dek: dek, pinKey: pinKey)

        XCTAssertNotEqual(a, b, "Each wrap must use a fresh random nonce")
        // Both must still decrypt back to the same DEK.
        XCTAssertEqual(try PinDEKWrapper.unwrap(payload: a, pinKey: pinKey), dek)
        XCTAssertEqual(try PinDEKWrapper.unwrap(payload: b, pinKey: pinKey), dek)
    }

    func test_wrappedPayload_hasExpectedLength() throws {
        let dek = try randomDEK()
        let pinKey = try PinDEKWrapper.derivePinKey(plainPin: "1234", salt: salt, deviceId: deviceId)

        let wrapped = try PinDEKWrapper.wrap(dek: dek, pinKey: pinKey)

        // 12-byte nonce + 32-byte ciphertext (== plaintext length) + 16-byte tag.
        XCTAssertEqual(wrapped.count, 12 + 32 + 16)
    }

    // MARK: - Legacy migration discriminator

    func test_isLegacyRawDEK_trueForRawDEKLength() throws {
        let raw = try randomDEK()  // 32 bytes
        XCTAssertTrue(PinDEKWrapper.isLegacyRawDEK(raw))
    }

    func test_isLegacyRawDEK_falseForWrappedPayload() throws {
        let dek = try randomDEK()
        let pinKey = try PinDEKWrapper.derivePinKey(plainPin: "1234", salt: salt, deviceId: deviceId)
        let wrapped = try PinDEKWrapper.wrap(dek: dek, pinKey: pinKey)  // 60 bytes
        XCTAssertFalse(PinDEKWrapper.isLegacyRawDEK(wrapped))
    }

    // MARK: - Helpers

    private func randomDEK() throws -> Data {
        var bytes = Data(count: 32)
        let result = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        guard result == errSecSuccess else { throw CryptoError.randomGenerationFailed }
        return bytes
    }
}

private extension SymmetricKey {
    var rawBytes: Data { withUnsafeBytes { Data($0) } }
}
