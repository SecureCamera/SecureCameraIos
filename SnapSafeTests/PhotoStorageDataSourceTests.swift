//
//  PhotoStorageDataSourceTests.swift
//  SnapSafeTests
//

import XCTest
@testable import SnapSafe

final class PhotoStorageDataSourceTests: XCTestCase {

    private var tempRoot: URL!
    private var cachesRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("psds-\(UUID().uuidString)")
        cachesRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("psds-caches-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cachesRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try? FileManager.default.removeItem(at: cachesRoot)
    }

    private func makeDataSource(encryptionScheme: EncryptionScheme) -> PhotoStorageDataSource {
        PhotoStorageDataSource(
            encryptionScheme: encryptionScheme, appSupportRoot: tempRoot, cachesRoot: cachesRoot)
    }

    func test_getGalleryDirectory_createsDirUnderRoot_andExcludesFromBackup() throws {
        // Use any EncryptionScheme double; directory creation does not touch crypto.
        let ds = makeDataSource(encryptionScheme: FakeEncryptionScheme())
        let dir = ds.getGalleryDirectory()
        let expected = tempRoot.appendingPathComponent(PhotoStorageDataSource.photosDir)
        // Compare paths (not URLs) to avoid trailing-slash mismatches introduced by createDirectory.
        XCTAssertEqual(dir.standardized.path, expected.standardized.path,
                       "gallery dir should be <root>/photos; got \(dir.path)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path), "directory should be created")
        let values = try dir.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true, "directory must be excluded from backup")
    }

    func test_thumbnailsDirectory_isUnderCachesRoot() {
        let ds = makeDataSource(encryptionScheme: FakeEncryptionScheme())
        let dir = ds.getThumbnailsDirectory()
        let expected = cachesRoot.appendingPathComponent(PhotoStorageDataSource.thumbnailsDir)
        // Compare paths (not URLs) to avoid trailing-slash mismatches.
        XCTAssertEqual(dir.standardized.path, expected.standardized.path,
                       "thumbnails dir should be under cachesRoot; got \(dir.path)")
    }

    func test_encryptToFile_thenDecryptFile_roundTripsBytes() async throws {
        // PassThroughEncryptionScheme performs real file I/O (write/read) without
        // encryption, so it exercises the data source's file plumbing end to end.
        let ds = makeDataSource(encryptionScheme: PassThroughEncryptionScheme())
        let target = tempRoot.appendingPathComponent("roundtrip.bin")
        let original = Data("hello secure storage".utf8)
        try await ds.encryptToFile(original, targetFile: target)
        let recovered = try await ds.decryptFile(target)
        XCTAssertEqual(recovered, original, "decryptFile must return the bytes written by encryptToFile")
    }

    func test_encryptAndSaveImage_movesTempIntoTarget_andIsReadable() async throws {
        let ds = makeDataSource(encryptionScheme: PassThroughEncryptionScheme())
        let tempFile = tempRoot.appendingPathComponent("staging.tmp")
        let target = tempRoot.appendingPathComponent("final.bin")
        let original = Data([0xDE, 0xAD, 0xBE, 0xEF])
        try await ds.encryptAndSaveImage(original, tempFile: tempFile, targetFile: target)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFile.path),
                       "temp file should be moved to the target, not left behind")
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path), "target file should exist")
        let recovered = try await ds.decryptFile(target)
        XCTAssertEqual(recovered, original, "round-tripped bytes should match the original")
    }
}
