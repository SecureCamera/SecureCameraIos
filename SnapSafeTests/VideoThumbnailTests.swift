//
//  VideoThumbnailTests.swift
//  SnapSafeTests
//
//  Covers storage/retrieval/deletion of encrypted video thumbnails, and that
//  they are wiped on poison-pill activation (they are derived from real video
//  frames, so they must be destroyed with the videos).
//

import XCTest
import UIKit
@testable import SnapSafe

@MainActor
final class VideoThumbnailTests: XCTestCase {

    private var repository: SecureImageRepository!
    private var fakeEncryption: FakeEncryptionScheme!
    private var tempDirectory: URL!
    private var videosDirectory: URL!
    private var videoThumbnailsDirectory: URL!
    private var decoyVideoThumbnailsDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()

        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        videosDirectory = tempDirectory.appendingPathComponent(SecureImageRepository.videosDir)
        videoThumbnailsDirectory = tempDirectory.appendingPathComponent(SecureImageRepository.videoThumbnailsDir)
        decoyVideoThumbnailsDirectory = tempDirectory.appendingPathComponent(SecureImageRepository.decoyVideoThumbnailsDir)

        fakeEncryption = FakeEncryptionScheme()
        repository = VideoTestableSecureImageRepository(
            tempDirectory: tempDirectory,
            thumbnailCache: FakeThumbnailCache(),
            encryptionScheme: fakeEncryption,
            videoEncryptionService: FakeVideoEncryptionService()
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        repository = nil
        fakeEncryption = nil
        tempDirectory = nil
        videosDirectory = nil
        videoThumbnailsDirectory = nil
        decoyVideoThumbnailsDirectory = nil
        try await super.tearDown()
    }

    func testStoreVideoThumbnailWritesEncryptedFile() async {
        await repository.storeVideoThumbnail(makeTestImage(), forVideoNamed: "video_20230101_120000")

        let file = videoThumbnailsDirectory.appendingPathComponent("video_20230101_120000.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path),
                      "Storing a thumbnail should write an encrypted file in the video thumbnails directory")
    }

    func testReadVideoThumbnailReturnsStoredImage() async {
        await repository.storeVideoThumbnail(makeTestImage(), forVideoNamed: "video_20230101_120000")

        let videoDef = VideoDef(
            videoName: "video_20230101_120000",
            videoFormat: "secv",
            videoFile: videosDirectory.appendingPathComponent("video_20230101_120000.secv")
        )

        let loaded = await repository.readVideoThumbnail(videoDef)
        XCTAssertNotNil(loaded, "A stored thumbnail should be readable")
    }

    func testDeleteVideoThumbnailRemovesFile() async {
        await repository.storeVideoThumbnail(makeTestImage(), forVideoNamed: "video_20230101_120000")
        let file = videoThumbnailsDirectory.appendingPathComponent("video_20230101_120000.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))

        repository.deleteVideoThumbnail(forVideoNamed: "video_20230101_120000")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    /// Security: video thumbnails are derived from real frames and must be
    /// destroyed when the poison pill fires.
    func testActivatePoisonPillDeletesAllVideoThumbnails() async {
        await repository.storeVideoThumbnail(makeTestImage(), forVideoNamed: "video_a")
        await repository.storeVideoThumbnail(makeTestImage(), forVideoNamed: "video_b")
        XCTAssertTrue(FileManager.default.fileExists(atPath: videoThumbnailsDirectory.path))

        repository.activatePoisonPill()

        XCTAssertFalse(FileManager.default.fileExists(atPath: videoThumbnailsDirectory.path),
                       "All video thumbnails should be destroyed on poison pill activation")
    }

    /// A decoy video's thumbnail must survive the poison pill (re-encrypted with
    /// the poison key), while a non-decoy video's thumbnail is destroyed.
    func testDecoyVideoThumbnailSurvivesPoisonPillWhileOthersAreDestroyed() async throws {
        try FileManager.default.createDirectory(at: videosDirectory, withIntermediateDirectories: true)

        // A decoy video + its thumbnail.
        let decoyVideoFile = videosDirectory.appendingPathComponent("video_decoy.secv")
        try Data("decoy-original".utf8).write(to: decoyVideoFile)
        let decoyVideoDef = VideoDef(videoName: "video_decoy", videoFormat: "secv", videoFile: decoyVideoFile)
        await repository.storeVideoThumbnail(makeTestImage(), forVideoNamed: "video_decoy")

        // A non-decoy video's thumbnail.
        await repository.storeVideoThumbnail(makeTestImage(), forVideoNamed: "video_regular")

        // The decoy thumbnail re-encryption decrypts the current thumbnail; make
        // the fake return some jpeg bytes for that decrypt.
        fakeEncryption.decryptResult = Data("jpeg".utf8)

        // Mark the video as a decoy.
        let added = await repository.addDecoyVideoWithKey(decoyVideoDef, keyData: Data(repeating: 0xAB, count: 32))
        XCTAssertTrue(added)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: decoyVideoThumbnailsDirectory.appendingPathComponent("video_decoy.jpg").path),
            "Marking a video as a decoy should store a poison-key thumbnail copy")

        // When
        repository.activatePoisonPill()

        // Then — the decoy video's thumbnail is restored and available.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: videoThumbnailsDirectory.appendingPathComponent("video_decoy.jpg").path),
            "Decoy video thumbnail must survive the poison pill so the gallery can show it")

        // And the non-decoy video's thumbnail is gone.
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: videoThumbnailsDirectory.appendingPathComponent("video_regular.jpg").path),
            "Non-decoy video thumbnail should be destroyed by the poison pill")
    }

    // MARK: - Helpers

    private func makeTestImage() -> UIImage {
        let size = CGSize(width: 40, height: 40)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
