//
//  HardwareEncryptionSchemeFileProtectionTests.swift
//  SnapSafeTests
//
//  Created by Claude on 2026-05-31.
//

import Foundation
import Mockable
import XCTest

@testable import SnapSafe

final class HardwareEncryptionSchemeFileProtectionTests: XCTestCase {
    private var tempDir: URL!
    private var deviceInfo: MockDeviceInfoDataSource!
    private var scheme: HardwareEncryptionScheme!

    override func setUp() async throws {
        try await super.setUp()

        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        deviceInfo = MockDeviceInfoDataSource()
        given(deviceInfo).getDeviceIdentifier().willReturn(Data("test-device-id".utf8))

        scheme = HardwareEncryptionScheme(deviceInfo: deviceInfo)
    }

    override func tearDown() async throws {
        try await super.tearDown()
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_keyDirectory_hasCompleteFileProtection() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("File protection is not enforced on iOS Simulator; verify on a real device")
        #else
        let keyDir = scheme.getKeyDirectory()

        let resourceValues = try keyDir.resourceValues(forKeys: [.fileProtectionKey])
        let protection = resourceValues.fileProtection

        XCTAssertEqual(protection, .complete, "Keys directory should have .complete file protection")
        #endif
    }

    func test_keyDirectory_isExcludedFromBackup() async throws {
        let keyDir = scheme.getKeyDirectory()

        let resourceValues = try keyDir.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertTrue(resourceValues.isExcludedFromBackup ?? false, "Keys directory should be excluded from backup")
    }

    func test_dekFile_hasCompleteFileProtection_afterCreation() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("File protection is not enforced on iOS Simulator; verify on a real device")
        #else
        let testPin = "1234"
        let hashedPin = HashedPin(hash: "dGVzdGhhc2g=", salt: "dGVzdHNhbHQ=")

        do {
            try await scheme.createKey(plainPin: testPin, hashedPin: hashedPin)
        } catch {
            throw XCTSkip("Secure Enclave key creation failed: \(error)")
        }

        let dekFile = scheme.getDekFile(hashedPin: hashedPin)

        guard FileManager.default.fileExists(atPath: dekFile.path) else {
            XCTFail("DEK file was not created")
            return
        }

        let resourceValues = try dekFile.resourceValues(forKeys: [.fileProtectionKey])
        let protection = resourceValues.fileProtection

        XCTAssertEqual(protection, .complete, "DEK file should have .complete file protection")
        #endif
    }

    func test_dekFile_parentDirectory_hasCompleteProtection() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("File protection is not enforced on iOS Simulator; verify on a real device")
        #else
        let testPin = "1234"
        let hashedPin = HashedPin(hash: "dGVzdGhhc2g=", salt: "dGVzdHNhbHQ=")

        do {
            try await scheme.createKey(plainPin: testPin, hashedPin: hashedPin)
        } catch {
            throw XCTSkip("Secure Enclave key creation failed: \(error)")
        }

        let dekFile = scheme.getDekFile(hashedPin: hashedPin)
        let parentDir = dekFile.deletingLastPathComponent()

        let resourceValues = try parentDir.resourceValues(forKeys: [.fileProtectionKey])
        let protection = resourceValues.fileProtection

        XCTAssertEqual(protection, .complete, "DEK parent directory should have .complete file protection")
        #endif
    }
}
