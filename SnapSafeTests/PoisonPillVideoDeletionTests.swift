//
//  PoisonPillVideoDeletionTests.swift
//  SnapSafeTests
//
//  Verifies that activating the poison pill destroys videos that are not
//  marked as decoys. Regression test for a bug where videos survived the
//  poison pill because only the photo gallery was wiped.
//

import XCTest
@testable import SnapSafe

@MainActor
final class PoisonPillVideoDeletionTests: XCTestCase {

    private var repository: SecureImageRepository!
    private var tempDirectory: URL!
    private var galleryDirectory: URL!
    private var decoyDirectory: URL!
    private var videosDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()

        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        galleryDirectory = tempDirectory.appendingPathComponent(SecureImageRepository.photosDir)
        decoyDirectory = tempDirectory.appendingPathComponent(SecureImageRepository.decoysDir)
        videosDirectory = tempDirectory.appendingPathComponent(SecureImageRepository.videosDir)

        repository = VideoTestableSecureImageRepository(
            tempDirectory: tempDirectory,
            thumbnailCache: FakeThumbnailCache(),
            encryptionScheme: FakeEncryptionScheme()
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        repository = nil
        tempDirectory = nil
        galleryDirectory = nil
        decoyDirectory = nil
        videosDirectory = nil
        try await super.tearDown()
    }

    /// Core regression test: when the poison pill is activated, a decoy photo is
    /// preserved while non-decoy videos are destroyed.
    func testActivatePoisonPillDestroysVideosNotMarkedAsDecoys() throws {
        try FileManager.default.createDirectory(at: galleryDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: decoyDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: videosDirectory, withIntermediateDirectories: true)

        // A decoy photo (present in gallery, backed up in the decoy directory) - survives.
        let decoyPhoto = galleryDirectory.appendingPathComponent("photo_20230101_120000_00.jpg")
        try Data().write(to: decoyPhoto)
        let decoyBackup = decoyDirectory.appendingPathComponent("photo_20230101_120000_00.jpg")
        try Data("decoy".utf8).write(to: decoyBackup)

        // A regular (non-decoy) photo - destroyed.
        let regularPhoto = galleryDirectory.appendingPathComponent("photo_20230101_120001_00.jpg")
        try Data().write(to: regularPhoto)

        // Videos - none are decoys, so all must be destroyed.
        let video1 = videosDirectory.appendingPathComponent("video_20230101_120000.secv")
        let video2 = videosDirectory.appendingPathComponent("video_20230101_120100.secv")
        try Data().write(to: video1)
        try Data().write(to: video2)

        // When
        repository.activatePoisonPill()

        // Then - only the decoy photo survives.
        let photos = repository.getPhotos()
        XCTAssertEqual(photos.count, 1)
        XCTAssertEqual(photos.first?.photoName, "photo_20230101_120000_00.jpg")

        // And the non-decoy videos are destroyed.
        XCTAssertFalse(FileManager.default.fileExists(atPath: video1.path),
                       "Non-decoy video should be destroyed when the poison pill is activated")
        XCTAssertFalse(FileManager.default.fileExists(atPath: video2.path),
                       "Non-decoy video should be destroyed when the poison pill is activated")
    }

    /// Guards the decoy check (and the ordering relative to the photo wipe, which
    /// removes the decoy directory): a video that has a matching decoy backup is
    /// preserved while a non-decoy video alongside it is destroyed.
    func testActivatePoisonPillPreservesVideosMarkedAsDecoys() throws {
        try FileManager.default.createDirectory(at: decoyDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: videosDirectory, withIntermediateDirectories: true)

        // A "decoy" video: present in videos dir with a matching decoy backup.
        let decoyVideo = videosDirectory.appendingPathComponent("video_decoy.secv")
        try Data().write(to: decoyVideo)
        let decoyVideoBackup = decoyDirectory.appendingPathComponent("video_decoy.secv")
        try Data().write(to: decoyVideoBackup)

        // A regular (non-decoy) video.
        let regularVideo = videosDirectory.appendingPathComponent("video_regular.secv")
        try Data().write(to: regularVideo)

        // When
        repository.activatePoisonPill()

        // Then
        XCTAssertTrue(FileManager.default.fileExists(atPath: decoyVideo.path),
                      "A decoy-backed video should survive poison pill activation")
        XCTAssertFalse(FileManager.default.fileExists(atPath: regularVideo.path),
                       "A non-decoy video should be destroyed")
    }
}

// MARK: - Testable Repository

@MainActor
final class VideoTestableSecureImageRepository: SecureImageRepository {
    private let testDirectory: URL

    init(tempDirectory: URL, thumbnailCache: ThumbnailCache, encryptionScheme: EncryptionScheme) {
        self.testDirectory = tempDirectory
        super.init(thumbnailCache: thumbnailCache, encryptionScheme: encryptionScheme)
    }

    override func getGalleryDirectory() -> URL {
        testDirectory.appendingPathComponent(SecureImageRepository.photosDir)
    }

    override func getDecoyDirectory() -> URL {
        testDirectory.appendingPathComponent(SecureImageRepository.decoysDir)
    }

    override func getVideosDirectory() -> URL {
        testDirectory.appendingPathComponent(SecureImageRepository.videosDir)
    }
}
