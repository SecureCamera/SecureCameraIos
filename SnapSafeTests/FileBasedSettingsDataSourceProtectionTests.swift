//
//  FileBasedSettingsDataSourceProtectionTests.swift
//  SnapSafeTests
//
//  Created by Claude on 2026-06-01.
//
//  H2 (Option D) hardening: the settings file persists the reversible
//  poison-pill PIN ciphertext (and the primary/poison-pill PIN hashes). It must
//  be written with complete file protection so it is unreadable while the device
//  is locked, not just excluded from backup. File protection is not enforced on
//  the simulator, so this runs on a device.

import Foundation
import XCTest

@testable import SnapSafe

final class FileBasedSettingsDataSourceProtectionTests: XCTestCase {

    private var fileURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("h2-settings-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: fileURL)
        try await super.tearDown()
    }

    func test_settingsFile_hasCompleteFileProtection() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("File protection is not enforced on iOS Simulator; verify on a real device")
        #else
        // Creating the data source writes the file (init saves defaults).
        let store = FileBasedSettingsDataSource(fileURL: fileURL)

        // Persist a poison-pill secret so the file holds the sensitive value.
        await store.setPoisonPillPin(cipheredHashedPin: "hashed", cipheredPlainPin: "plain")

        let values = try fileURL.resourceValues(forKeys: [.fileProtectionKey])
        XCTAssertEqual(values.fileProtection, .complete,
                       "Settings file must have .complete file protection (holds reversible PP PIN)")
        #endif
    }
}
