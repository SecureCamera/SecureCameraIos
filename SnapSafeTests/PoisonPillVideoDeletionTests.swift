//
//  PoisonPillVideoDeletionTests.swift
//  SnapSafeTests
//
//  Verifies poison-pill video handling: non-decoy videos are destroyed, while
//  decoy videos are re-encrypted with the poison-pill key and survive (and are
//  swapped in to replace the original real-key file).
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
            encryptionScheme: FakeEncryptionScheme(),
            videoEncryptionService: FakeVideoEncryptionService()
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

    /// Adding a decoy video re-encrypts it with the poison-pill key into the
    /// decoy directory and marks it as a decoy.
    func testAddDecoyVideoReEncryptsAndMarksDecoy() async throws {
        try FileManager.default.createDirectory(at: videosDirectory, withIntermediateDirectories: true)

        let videoFile = videosDirectory.appendingPathComponent("video_20230101_120000.secv")
        try Data("original-real-key".utf8).write(to: videoFile)
        let videoDef = VideoDef(videoName: "video_20230101_120000", videoFormat: "secv", videoFile: videoFile)

        let fakeVideo = FakeVideoEncryptionService()
        let repo = VideoTestableSecureImageRepository(
            tempDirectory: tempDirectory,
            thumbnailCache: FakeThumbnailCache(),
            encryptionScheme: FakeEncryptionScheme(),
            videoEncryptionService: fakeVideo
        )

        // When
        let success = await repo.addDecoyVideoWithKey(videoDef, keyData: Data(repeating: 0xAB, count: 32))

        // Then
        XCTAssertTrue(success)
        XCTAssertTrue(fakeVideo.decryptForSharingCalled, "Should decrypt the original with the current key")
        XCTAssertTrue(fakeVideo.encryptForDecoyCalled, "Should re-encrypt with the poison-pill key")
        XCTAssertTrue(repo.isDecoyVideo(videoDef), "Video should be marked as a decoy")

        let decoyCopy = decoyDirectory.appendingPathComponent("video_20230101_120000.secv")
        XCTAssertTrue(FileManager.default.fileExists(atPath: decoyCopy.path))
        XCTAssertEqual(try Data(contentsOf: decoyCopy), FakeVideoEncryptionService.reEncryptedMarker)
    }

    /// End-to-end: mark a video as a decoy, then activate the poison pill. The
    /// decoy video survives and its file is replaced by the poison-pill-key copy,
    /// while a non-decoy video alongside it is destroyed.
    func testActivatePoisonPillReplacesDecoyVideoWithReEncryptedCopy() async throws {
        try FileManager.default.createDirectory(at: videosDirectory, withIntermediateDirectories: true)

        // Decoy video — original encrypted with the (now-doomed) real key.
        let decoyVideoFile = videosDirectory.appendingPathComponent("video_decoy.secv")
        try Data("original-real-key".utf8).write(to: decoyVideoFile)
        let decoyVideoDef = VideoDef(videoName: "video_decoy", videoFormat: "secv", videoFile: decoyVideoFile)

        // Non-decoy video.
        let regularVideo = videosDirectory.appendingPathComponent("video_regular.secv")
        try Data("regular".utf8).write(to: regularVideo)

        // Mark the decoy video (re-encrypts into the decoy dir with the poison key).
        let added = await repository.addDecoyVideoWithKey(decoyVideoDef, keyData: Data(repeating: 0xAB, count: 32))
        XCTAssertTrue(added)
        XCTAssertTrue(repository.isDecoyVideo(decoyVideoDef))

        // When
        repository.activatePoisonPill()

        // Then - decoy video survives and now holds the poison-pill-key bytes.
        XCTAssertTrue(FileManager.default.fileExists(atPath: decoyVideoFile.path),
                      "Decoy video should survive poison pill activation")
        XCTAssertEqual(try Data(contentsOf: decoyVideoFile), FakeVideoEncryptionService.reEncryptedMarker,
                       "Decoy video should be replaced by its poison-pill-key copy")

        // And the non-decoy video is destroyed.
        XCTAssertFalse(FileManager.default.fileExists(atPath: regularVideo.path),
                       "Non-decoy video should be destroyed")
    }
}

// MARK: - Testable Repository

@MainActor
final class VideoTestableSecureImageRepository: SecureImageRepository {
    private let testDirectory: URL

    init(
        tempDirectory: URL,
        thumbnailCache: ThumbnailCache,
        encryptionScheme: EncryptionScheme,
        videoEncryptionService: VideoEncryptionServiceProtocol
    ) {
        self.testDirectory = tempDirectory
        super.init(
            thumbnailCache: thumbnailCache,
            encryptionScheme: encryptionScheme,
            videoEncryptionService: videoEncryptionService
        )
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

    override func getVideoThumbnailsDirectory() -> URL {
        testDirectory.appendingPathComponent(SecureImageRepository.videoThumbnailsDir)
    }
}
