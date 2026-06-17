//
//  PinCryptoTests.swift
//  SnapSafeTests
//
//  Created by Adam Brown on 9/2/25.
//


import XCTest
@testable import SnapSafe

final class PinCryptoTests: XCTestCase {

    private let deviceId = Data("test-device-id-123".utf8)
    private var crypto: PinCrypto!

    override func setUp() {
        super.setUp()
        crypto = PinCryptoImpl()
    }

    func test_hashPin_generatesSaltAndHash() throws {
        let pin = "1234"

        let hashed = try crypto.hashPin(pin: pin, deviceId: deviceId)

        XCTAssertFalse(hashed.salt.isEmpty, "Salt should not be empty")
        XCTAssertFalse(hashed.hash.isEmpty, "Hash should not be empty")
    }

    func test_hashPin_generatesDifferentHashesForSamePIN() throws {
        let pin = "1234"

        let h1 = try crypto.hashPin(pin: pin, deviceId: deviceId)
        let h2 = try crypto.hashPin(pin: pin, deviceId: deviceId)

        XCTAssertNotEqual(h1.salt, h2.salt, "Salts should be different")
        XCTAssertNotEqual(h1.hash, h2.hash, "Hashes should be different")
    }

    func test_verifyPin_returnsTrueForCorrectPIN() throws {
        let pin = "1234"
        let hashed = try crypto.hashPin(pin: pin, deviceId: deviceId)

        let ok = crypto.verifyPin(pin: pin, stored: hashed, deviceId: deviceId)
        XCTAssertTrue(ok, "Verification should succeed for correct PIN")
    }

    func test_verifyPin_returnsFalseForIncorrectPIN() throws {
        let correctPin = "1234"
        let hashed = try crypto.hashPin(pin: correctPin, deviceId: deviceId)

        let result = crypto.verifyPin(pin: "5678", stored: hashed, deviceId: deviceId)
        XCTAssertFalse(result, "Verification should fail for incorrect PIN")
    }

    func test_verifyPin_handlesEmptyPIN() throws {
        let correctPin = "1234"
        let hashed = try crypto.hashPin(pin: correctPin, deviceId: deviceId)

        let result = crypto.verifyPin(pin: "", stored: hashed, deviceId: deviceId)
        XCTAssertFalse(result, "Verification should fail for empty PIN")
    }
}
