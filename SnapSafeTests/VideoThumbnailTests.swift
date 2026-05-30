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
    private var tempDirectory: URL!
    private var videosDirectory: URL!
    private var videoThumbnailsDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()

        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        videosDirectory = tempDirectory.appendingPathComponent(SecureImageRepository.videosDir)
        videoThumbnailsDirectory = tempDirectory.appendingPathComponent(SecureImageRepository.videoThumbnailsDir)

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
        videosDirectory = nil
        videoThumbnailsDirectory = nil
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
