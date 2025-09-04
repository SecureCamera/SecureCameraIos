//
//  PinRepositoryTest.swift
//  SnapSafeTests
//
//  Created by Adam Brown on 9/3/25.
//

import Mockable
import XCTest

@testable import SnapSafe

final class PinRepositoryTests: XCTestCase {

    private var settings: MockSettingsDataSource!
    private var deviceInfo: MockDeviceInfoDataSource!
    private var pinCrypto: MockPinCrypto!
    private var encryptionScheme: MockEncryptionScheme!
    private var repo: PinRepository!

    private let deviceId = Data("device-id-123".utf8)

    override func setUp() async throws {
        try await super.setUp()
        settings = MockSettingsDataSource()
        deviceInfo = MockDeviceInfoDataSource()
        pinCrypto = MockPinCrypto()
        encryptionScheme = MockEncryptionScheme()

        given(deviceInfo).getDeviceIdentifier().willReturn(deviceId)

        repo = PinRepositoryImpl(
            dataSource: settings,
            encryptionScheme: encryptionScheme,
            deviceInfo: deviceInfo,
            pinCrypto: pinCrypto
        )
    }

    func test_setAppPin_hashes_and_stores_ciphered_pin() async throws {
        let pin = "1234"
        let hashed = HashedPin(hash: "hash123", salt: "salt123")
        given(pinCrypto).hashPin(pin: .value(pin), deviceId: .value(deviceId)).willReturn(hashed)

        let hashedData = try jsonEncoder().encode(hashed)
        let encryptedData = Data("encrypted".utf8)
        let expectedBase64 = encryptedData.base64EncodedString()

        given(encryptionScheme).encryptWithKeyAlias(
            plain: .value(hashedData), keyAlias: .value("pin_key")
        ).willReturn(encryptedData)
        
        given(settings).setAppPin(cipheredPin: .value(expectedBase64))
            .willReturn()

        await repo.setAppPin(pin)

        verify(settings)
            .setAppPin(cipheredPin: .value(expectedBase64))
            .called(.once)
    }

    func test_getHashedPin_decrypts_and_returns_stored_pin() async throws {
        let stored = HashedPin(hash: "h", salt: "s")
        let storedData = try jsonEncoder().encode(stored)
        let encryptedData = Data("encrypted".utf8)
        let encryptedBase64 = encryptedData.base64EncodedString()

        given(settings).getCipheredPin().willReturn(encryptedBase64)
        given(encryptionScheme).decryptWithKeyAlias(
            encrypted: .value(encryptedData), keyAlias: .value("pin_key")
        ).willReturn(storedData)

        let result = await repo.getHashedPin()

        XCTAssertNotNil(result)
        XCTAssertEqual(stored.hash, result!.hash)
        XCTAssertEqual(stored.salt, result!.salt)
    }

    func test_getHashedPin_returns_nil_when_none_stored() async throws {
        given(settings).getCipheredPin().willReturn(nil as String?)
        let result = await repo.getHashedPin()
        XCTAssertNil(result)
    }

    func test_hashPin_delegates_to_PinCrypto_with_device_id() async throws {
        let pin = "9999"
        let hashed = HashedPin(hash: "hh", salt: "ss")
        given(pinCrypto).hashPin(pin: .value(pin), deviceId: .value(deviceId)).willReturn(hashed)

        let result = await repo.hashPin(pin)
        XCTAssertEqual(hashed, result)
    }

    func test_verifyPin_delegates_to_PinCrypto_with_device_id() async throws {
        let input = "1111"
        let stored = HashedPin(hash: "h1", salt: "s1")
        given(pinCrypto).verifyPin(
            pin: .value(input), stored: .value(stored), deviceId: .value(deviceId)
        ).willReturn(true)

        await XCTAssertTrueAsync(await repo.verifyPin(inputPin: input, storedHash: stored))
    }

    func test_verifySecurityPin_uses_getHashedPin_and_verifyPin() async throws {
        let input = "2222"
        let stored = HashedPin(hash: "h2", salt: "s2")
        let storedData = try jsonEncoder().encode(stored)
        let encryptedData = Data("encrypted".utf8)
        let encryptedBase64 = encryptedData.base64EncodedString()

        given(settings).getCipheredPin().willReturn(encryptedBase64)
        given(encryptionScheme).decryptWithKeyAlias(
            encrypted: .value(encryptedData), keyAlias: .value("pin_key")
        ).willReturn(storedData)
        given(pinCrypto).verifyPin(
            pin: .value(input), stored: .value(stored), deviceId: .value(deviceId)
        ).willReturn(true)

        await XCTAssertTrueAsync(await repo.verifySecurityPin(input))
    }

    func test_verifySecurityPin_returns_false_when_no_stored_pin() async throws {
        given(settings).getCipheredPin().willReturn(nil as String?)
        let verified = await repo.verifySecurityPin("0000")
        XCTAssertFalse(verified)
    }

    func test_setPoisonPillPin_stores_ciphered_hashed_and_plain() async throws {
        let ppp = "5678"
        let hashed = HashedPin(hash: "ph", salt: "ps")
        given(pinCrypto).hashPin(pin: .value(ppp), deviceId: .value(deviceId)).willReturn(hashed)
        
        let hashedData = try! jsonEncoder().encode(hashed)
        let plainData = ppp.data(using: .utf8)!
        let encryptedHashedData = Data("encrypted-hashed".utf8)
        let encryptedPlainData = Data("encrypted-plain".utf8)
        let expectedHashedBase64 = encryptedHashedData.base64EncodedString()
        let expectedPlainBase64 = encryptedPlainData.base64EncodedString()

        let jsonString = String(data: hashedData, encoding: .utf8)!
        print(jsonString)
        
        given(encryptionScheme).encryptWithKeyAlias(
            plain: .matching { $0 == hashedData },
            keyAlias: .value("pin_key")
        ).willReturn(encryptedHashedData)
        given(encryptionScheme).encryptWithKeyAlias(
            plain: .matching { $0 == plainData },
            keyAlias: .value("pin_key")
        ).willReturn(encryptedPlainData)
        
        given(settings).setPoisonPillPin(
            cipheredHashedPin: .value(expectedHashedBase64),
            cipheredPlainPin: .value(expectedPlainBase64),
        ).willReturn()

        await repo.setPoisonPillPin(ppp)

        verify(settings)
            .setPoisonPillPin(
                cipheredHashedPin: .value(expectedHashedBase64),
                cipheredPlainPin: .value(expectedPlainBase64)
            )
            .called(.once)
    }

    func test_getPlainPoisonPillPin_decrypts_plain() async throws {
        let ppp = "7777"
        let plainData = ppp.data(using: .utf8)!
        let encryptedData = Data("encrypted".utf8)
        let encryptedBase64 = encryptedData.base64EncodedString()

        given(settings).getPlainPoisonPillPin().willReturn(encryptedBase64)
        given(encryptionScheme).decryptWithKeyAlias(
            encrypted: .value(encryptedData), keyAlias: .value("pin_key")
        ).willReturn(plainData)

        let result = await repo.getPlainPoisonPillPin()
        XCTAssertEqual(ppp, result)
    }

    func test_getPlainPoisonPillPin_returns_nil_when_not_set() async throws {
        given(settings).getPlainPoisonPillPin().willReturn(nil as String?)
        let result = await repo.getPlainPoisonPillPin()
        XCTAssertNil(result)
    }

    func test_getHashedPoisonPillPin_decrypts_and_decodes() async throws {
        let stored = HashedPin(hash: "h3", salt: "s3")
        let storedData = try jsonEncoder().encode(stored)
        let encryptedData = Data("encrypted".utf8)
        let encryptedBase64 = encryptedData.base64EncodedString()

        given(settings).getHashedPoisonPillPin().willReturn(encryptedBase64)
        given(encryptionScheme).decryptWithKeyAlias(
            encrypted: .value(encryptedData), keyAlias: .value("pin_key")
        ).willReturn(storedData)

        let result = await repo.getHashedPoisonPillPin()
        XCTAssertNotNil(result)
        XCTAssertEqual(stored, result)
    }

    func test_hasPoisonPillPin_true_only_when_both_exist() async throws {
        let main = HashedPin(hash: "mh", salt: "ms")
        let mainData = try jsonEncoder().encode(main)
        let encryptedMainData = Data("encrypted-main".utf8)
        let encryptedMainBase64 = encryptedMainData.base64EncodedString()

        let ppp = HashedPin(hash: "ph", salt: "ps")
        let pppData = try jsonEncoder().encode(ppp)
        let encryptedPppData = Data("encrypted-ppp".utf8)
        let encryptedPppBase64 = encryptedPppData.base64EncodedString()

        given(settings).getCipheredPin().willReturn(encryptedMainBase64)
        given(encryptionScheme).decryptWithKeyAlias(
            encrypted: .value(encryptedMainData), keyAlias: .value("pin_key")
        ).willReturn(mainData)
        given(settings).getHashedPoisonPillPin().willReturn(encryptedPppBase64)
        given(encryptionScheme).decryptWithKeyAlias(
            encrypted: .value(encryptedPppData), keyAlias: .value("pin_key")
        ).willReturn(pppData)

        try await XCTAssertTrueAsync(try await repo.hasPoisonPillPin())
    }

    func test_hasPoisonPillPin_false_when_one_missing() async throws {
        let main = HashedPin(hash: "mh", salt: "ms")
        let mainData = try jsonEncoder().encode(main)
        let encryptedMainData = Data("encrypted-main".utf8)
        let encryptedMainBase64 = encryptedMainData.base64EncodedString()

        given(settings).getCipheredPin().willReturn(encryptedMainBase64)
        given(encryptionScheme).decryptWithKeyAlias(
            encrypted: .value(encryptedMainData), keyAlias: .value("pin_key")
        ).willReturn(mainData)
        given(settings).getHashedPoisonPillPin().willReturn(nil as String?)
        try await XCTAssertFalseAsync(try await repo.hasPoisonPillPin())

        given(settings).getCipheredPin().willReturn(nil as String?)
        let ppp = HashedPin(hash: "ph", salt: "ps")
        let pppData = try jsonEncoder().encode(ppp)
        let encryptedPppData = Data("encrypted-ppp".utf8)
        let encryptedPppBase64 = encryptedPppData.base64EncodedString()

        given(settings).getHashedPoisonPillPin().willReturn(encryptedPppBase64)
        given(encryptionScheme).decryptWithKeyAlias(
            encrypted: .value(encryptedPppData), keyAlias: .value("pin_key")
        ).willReturn(pppData)
        try await XCTAssertFalseAsync(try await repo.hasPoisonPillPin())
    }

    func test_verifyPoisonPillPin_delegates_to_verifyPin() async throws {
        let input = "9898"
        let stored = HashedPin(hash: "h9", salt: "s9")
        let storedData = try jsonEncoder().encode(stored)
        let encryptedData = Data("encrypted".utf8)
        let encryptedBase64 = encryptedData.base64EncodedString()

        given(settings).getHashedPoisonPillPin().willReturn(encryptedBase64)
        given(encryptionScheme).decryptWithKeyAlias(
            encrypted: .value(encryptedData), keyAlias: .value("pin_key")
        ).willReturn(storedData)
        given(pinCrypto).verifyPin(
            pin: .value(input), stored: .value(stored), deviceId: .value(deviceId)
        ).willReturn(true)

        await XCTAssertTrueAsync(await repo.verifyPoisonPillPin(input))
    }

    func test_activatePoisonPill_moves_ppp_and_removes_ppp() async throws {
        let ppp = HashedPin(hash: "ph1", salt: "ps1")
        let pppData = try jsonEncoder().encode(ppp)
        let encryptedPppData = Data("encrypted-ppp".utf8)
        let encryptedPppBase64 = encryptedPppData.base64EncodedString()
        let newEncryptedData = Data("new-encrypted".utf8)
        let newEncryptedBase64 = newEncryptedData.base64EncodedString()

        given(settings).getHashedPoisonPillPin().willReturn(encryptedPppBase64)
        
        given(encryptionScheme).decryptWithKeyAlias(
            encrypted: .value(encryptedPppData), keyAlias: .value("pin_key")
        ).willReturn(pppData)
        given(encryptionScheme).encryptWithKeyAlias(
            plain: .value(pppData), keyAlias: .value("pin_key")
        ).willReturn(newEncryptedData)
        
        given(settings).activatePoisonPill(ciphered: .value(newEncryptedBase64))
            .willReturn()
        given(settings).removePoisonPillPin()
            .willReturn()

        await repo.activatePoisonPill()

        verify(settings).activatePoisonPill(ciphered: .value(newEncryptedBase64)).called(.once)
        verify(settings).removePoisonPillPin().called(.once)
    }

    func test_activatePoisonPill_does_nothing_when_no_ppp() async throws {
        given(settings).getHashedPoisonPillPin().willReturn(nil as String?)

        await repo.activatePoisonPill()

        verify(settings).activatePoisonPill(ciphered: .any).called(.never)
        verify(settings).removePoisonPillPin().called(.never)
    }

    func test_removePoisonPillPin_delegates_to_data_source() async throws {
        given(settings).removePoisonPillPin().willReturn()
        await repo.removePoisonPillPin()
        verify(settings).removePoisonPillPin().called(.once)
    }
}
