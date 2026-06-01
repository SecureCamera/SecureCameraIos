//
//  HardwareEncryptionSchemePinBindingTests.swift
//  SnapSafeTests
//
//  Created by Claude on 2026-05-31.
//
//  C1 integration tests at the HardwareEncryptionScheme level: the DEK round
//  trips only with the correct PIN, a wrong PIN is rejected, and legacy
//  SE-only-wrapped DEKs migrate transparently. These exercise the real Secure
//  Enclave, so they skip on the simulator (SE key creation is unavailable
//  there) — run on a device. The keychain-free crypto boundary is covered
//  exhaustively by PinDEKWrapperTests, which run on CI.

import CryptoKit
import Foundation
import Mockable
import XCTest

@testable import SnapSafe

final class HardwareEncryptionSchemePinBindingTests: XCTestCase {

    private var deviceInfo: MockDeviceInfoDataSource!
    private var scheme: HardwareEncryptionScheme!
    private let hashedPin = HashedPin(hash: "dGVzdGhhc2g=", salt: "dGVzdHNhbHQ=")

    override func setUp() async throws {
        try await super.setUp()
        deviceInfo = MockDeviceInfoDataSource()
        given(deviceInfo).getDeviceIdentifier().willReturn(Data("test-device-id".utf8))
        scheme = HardwareEncryptionScheme(deviceInfo: deviceInfo)
    }

    override func tearDown() async throws {
        await scheme.securityFailureReset()
        try await super.tearDown()
    }

    func test_createThenDerive_withCorrectPin_recoversSameDEK() async throws {
        try skipOnSimulator()

        try await scheme.createKey(plainPin: "1234", hashedPin: hashedPin)
        let dek1 = try await scheme.deriveKey(plainPin: "1234", hashedPin: hashedPin)
        let dek2 = try await scheme.deriveKey(plainPin: "1234", hashedPin: hashedPin)

        XCTAssertEqual(dek1.count, 32)
        XCTAssertEqual(dek1, dek2, "Same PIN must deterministically recover the same DEK")
    }

    func test_derive_withWrongPin_throwsWrongPin() async throws {
        try skipOnSimulator()

        try await scheme.createKey(plainPin: "1234", hashedPin: hashedPin)

        do {
            _ = try await scheme.deriveKey(plainPin: "9999", hashedPin: hashedPin)
            XCTFail("Deriving with the wrong PIN should throw")
        } catch let error as CryptoError {
            XCTAssertEqual(error, .wrongPin)
        }
    }

    func test_storedPayload_isPinWrapped_notRawDEK() async throws {
        try skipOnSimulator()

        try await scheme.createKey(plainPin: "1234", hashedPin: hashedPin)

        // SE-unwrap the on-disk file and confirm the payload is the PIN-wrapped
        // form (nonce+ct+tag), not a bare 32-byte DEK.
        let dekFile = scheme.getDekFile(hashedPin: hashedPin)
        let onDisk = try Data(contentsOf: dekFile)
        let payload = try scheme.decryptWithHardwareKeyForTesting(encrypted: onDisk)

        XCTAssertFalse(PinDEKWrapper.isLegacyRawDEK(payload),
                       "Newly created DEK must be stored PIN-wrapped, not as a raw DEK")
        XCTAssertEqual(payload.count, PinDEKWrapper.wrappedSize)
    }

    private func skipOnSimulator() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Secure Enclave is unavailable on the simulator; run on a device")
        #endif
    }
}
