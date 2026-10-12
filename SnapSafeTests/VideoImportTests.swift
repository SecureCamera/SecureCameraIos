//
//  VideoImportTests.swift
//  SnapSafeTests
//
//  Covers SecureImageRepository.importVideo: a picked video is encrypted to a
//  uniquely-named, date-sortable SECV file in the videos directory, with a
//  thumbnail when the input is a real video.
//

import XCTest
import CryptoKit
@testable import SnapSafe

@MainActor
final class VideoImportTests: XCTestCase {

    private var repository: SecureImageRepository!
    private var tempDirectory: URL!
    private var videosDirectory: URL!
    private var videoThumbnailsDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()

        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        videosDirectory = tempDirectory.appendingPathComponent(SecureImageRepository.videosDir)
        try FileManager.default.createDirectory(at: videosDirectory, withIntermediateDirectories: true)
        videoThumbnailsDirectory = tempDirectory.appendingPathComponent(SecureImageRepository.videoThumbnailsDir)

        repository = SecureImageRepository(
            thumbnailCache: ThumbnailCache(),
            encryptionScheme: FakeEncryptionScheme(),
            videoEncryptionService: FakeVideoEncryptionService(),
            applicationSupportDirectory: tempDirectory,
            cachesDirectory: tempDirectory
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

    func testImportVideoCreatesEncryptedSecvInVideosDirectory() async throws {
        let plain = try makePlaintext()

        let ok = await repository.importVideo(from: plain)
        XCTAssertTrue(ok)

        let files = try secvFiles()
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].lastPathComponent.hasPrefix("video_"),
                      "Imported video should use the video_ naming convention")
        XCTAssertGreaterThan(try Data(contentsOf: files[0]).count, 0,
                             "Imported video should be written (encrypted) to disk")
    }

    func testImportedVideoNameIsDateSortable() async throws {
        _ = await repository.importVideo(from: try makePlaintext())

        let file = try XCTUnwrap(try secvFiles().first)
        let name = file.deletingPathExtension().lastPathComponent
        let videoDef = VideoDef(videoName: name, videoFormat: "secv", videoFile: file)
        XCTAssertNotNil(videoDef.dateTaken(),
                        "Imported video name must be parseable by dateTaken() so it sorts in the gallery")
    }

    func testImportingTwoVideosCreatesTwoDistinctFiles() async throws {
        _ = await repository.importVideo(from: try makePlaintext())
        _ = await repository.importVideo(from: try makePlaintext())

        let files = try secvFiles()
        XCTAssertEqual(files.count, 2, "Each imported video should get its own file")
        XCTAssertEqual(Set(files.map { $0.lastPathComponent }).count, 2,
                       "Imported videos must have unique names even within the same second")
    }

    func testImportVideoWithNonVideoInputStillEncryptsButSkipsThumbnail() async throws {
        // The fake encryption service ignores the input format, but thumbnail
        // generation uses real AVFoundation, which can't decode arbitrary bytes.
        let ok = await repository.importVideo(from: try makePlaintext())
        XCTAssertTrue(ok, "Encryption should succeed even when thumbnail generation fails")

        let thumbs = (try? FileManager.default.contentsOfDirectory(
            at: videoThumbnailsDirectory, includingPropertiesForKeys: nil)) ?? []
        XCTAssertTrue(thumbs.filter { $0.pathExtension == "jpg" }.isEmpty,
                      "A non-decodable input should not produce a thumbnail")
    }

    // MARK: - Helpers

    private func makePlaintext() throws -> URL {
        let url = tempDirectory.appendingPathComponent("\(UUID().uuidString).mov")
        try Data((0..<2048).map { UInt8($0 & 0xFF) }).write(to: url)
        return url
    }

    private func secvFiles() throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: videosDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "secv" }
    }
}
