//
//  HardwareEncryptionSchemeSecurityResetTests.swift
//  SnapSafeTests
//
//  Created by Claude on 2026-05-31.
//

import Foundation
import Mockable
import Security
import XCTest

@testable import SnapSafe

final class HardwareEncryptionSchemeSecurityResetTests: XCTestCase {
    private var deviceInfo: MockDeviceInfoDataSource!
    private var scheme: HardwareEncryptionScheme!

    private static let kekAlias = "snapsafe_kek"
    private static let pinAlias = "pin_key"

    override func setUp() async throws {
        try await super.setUp()
        deviceInfo = MockDeviceInfoDataSource()
        given(deviceInfo).getDeviceIdentifier().willReturn(Data("test-device-id".utf8))
        scheme = HardwareEncryptionScheme(deviceInfo: deviceInfo)
        // Ensure clean keychain state for deterministic assertions
        Self.deleteAllAppECHardwareKeys()
    }

    override func tearDown() async throws {
        try await super.tearDown()
        Self.deleteAllAppECHardwareKeys()
    }

    private static func deleteAllAppECHardwareKeys() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func hardwareKeyExists(alias: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: alias.data(using: .utf8)!,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }

    /// H3 (a): `securityFailureReset` must delete the Secure Enclave / hardware key
    /// material via `SecItemDelete`. Otherwise the keys survive across reset and
    /// can decrypt any DEK that ever leaks (backup, extraction, etc.).
    func test_securityFailureReset_deletesHardwareKeys() async throws {
        // Force creation of both hardware keys the app uses.
        do {
            _ = try await scheme.encryptWithKeyAlias(plain: Data("payload".utf8),
                                                    keyAlias: Self.kekAlias)
            _ = try await scheme.encryptWithKeyAlias(plain: Data("payload".utf8),
                                                    keyAlias: Self.pinAlias)
        } catch {
            throw XCTSkip("Hardware key creation unavailable in this environment: \(error)")
        }

        XCTAssertTrue(Self.hardwareKeyExists(alias: Self.kekAlias),
                      "Precondition: KEK key should exist before reset")
        XCTAssertTrue(Self.hardwareKeyExists(alias: Self.pinAlias),
                      "Precondition: pin_key should exist before reset")

        await scheme.securityFailureReset()

        XCTAssertFalse(Self.hardwareKeyExists(alias: Self.kekAlias),
                       "KEK hardware key must be deleted by securityFailureReset()")
        XCTAssertFalse(Self.hardwareKeyExists(alias: Self.pinAlias),
                       "Auxiliary hardware keys (e.g. pin_key) must be deleted by securityFailureReset()")
    }

    /// H3 (b): `evictKey` is fire-and-forget today, so the in-memory key may
    /// outlive the reset. After `await securityFailureReset()`, any subsequent
    /// `getDerivedKey()` must throw — proving the cache was evicted *before*
    /// reset returned (not eventually).
    func test_securityFailureReset_evictsCachedKeyBeforeReturning() async throws {
        let hashedPin = HashedPin(hash: "dGVzdGhhc2g=", salt: "dGVzdHNhbHQ=")

        do {
            try await scheme.createKey(plainPin: "1234", hashedPin: hashedPin)
            try await scheme.deriveAndCacheKey(plainPin: "1234", hashedPin: hashedPin)
        } catch {
            throw XCTSkip("Hardware key derivation unavailable in this environment: \(error)")
        }

        _ = try await scheme.getDerivedKey()  // precondition: cache populated

        await scheme.securityFailureReset()

        do {
            _ = try await scheme.getDerivedKey()
            XCTFail("getDerivedKey should throw after securityFailureReset awaits eviction")
        } catch CryptoError.keyNotDerived {
            // expected
        }
    }
}
