//
//  VideoMetaDataTests.swift
//  SnapSafeTests
//
//  Integration coverage for SecureImageRepository.getVideoMetaData: a synthetic
//  .mov is encrypted to .secv and read back through EncryptedVideoDataSource.
//

import XCTest
import AVFoundation
import CoreLocation
import CryptoKit
@testable import SnapSafe

@MainActor
final class VideoMetaDataTests: XCTestCase {

    private var tempDirectory: URL!
    private var videosDirectory: URL!
    private var repository: SecureImageRepository!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        videosDirectory = tempDirectory.appendingPathComponent(SecureImageRepository.videosDir)
        try FileManager.default.createDirectory(at: videosDirectory, withIntermediateDirectories: true)

        // Real video encryption so EncryptedVideoDataSource can decrypt the SECV.
        repository = SecureImageRepository(
            thumbnailCache: ThumbnailCache(),
            encryptionScheme: FakeEncryptionScheme(),
            videoEncryptionService: VideoEncryptionService(),
            applicationSupportDirectory: tempDirectory,
            cachesDirectory: tempDirectory
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        repository = nil
        tempDirectory = nil
        videosDirectory = nil
        try await super.tearDown()
    }

    // MARK: - Tests

    func testRoundTripWithEmbeddedMetadata() async throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let location = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let items = AVMetadataItemFactory.makeCaptureItems(location: location, date: date)

        let videoDef = try await makeEncryptedVideoDef(name: "video_20231114_221320", metadata: items)
        let meta = try await repository.getVideoMetaData(videoDef)

        XCTAssertEqual(meta.dateTakenSource, .embedded,
                       "Date should come from the embedded creation date, not the filename")
        XCTAssertEqual(meta.dateTaken.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 1.0,
                       "Embedded date \(meta.dateTaken) should match \(date)")
        let coords = try XCTUnwrap(meta.location, "Embedded location should be returned")
        XCTAssertEqual(coords.latitude, 37.7749, accuracy: 1e-4, "latitude was \(coords.latitude)")
        XCTAssertEqual(coords.longitude, -122.4194, accuracy: 1e-4, "longitude was \(coords.longitude)")
        XCTAssertEqual(meta.resolution.width, 160, "width was \(meta.resolution.width)")
        XCTAssertEqual(meta.resolution.height, 90, "height was \(meta.resolution.height)")
        XCTAssertGreaterThan(meta.duration, 0, "duration was \(meta.duration)")
        XCTAssertNotNil(meta.codec, "codec should be populated from the track format")
        XCTAssertGreaterThan(meta.fileSize, 0, "fileSize was \(meta.fileSize)")
    }

    func testBackwardsCompatNoMetadataFallsBackToFilename() async throws {
        let videoDef = try await makeEncryptedVideoDef(name: "video_20231114_221320", metadata: [])
        let meta = try await repository.getVideoMetaData(videoDef)

        XCTAssertNil(meta.location, "No embedded location should yield nil")
        XCTAssertEqual(meta.dateTakenSource, .filename,
                       "Without embedded date the source should be .filename")
        let expected = try XCTUnwrap(videoDef.dateTaken())
        XCTAssertEqual(meta.dateTaken.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1.0,
                       "Date \(meta.dateTaken) should match filename-derived \(expected)")
        XCTAssertEqual(meta.resolution.width, 160, "technical fields should still populate; width was \(meta.resolution.width)")
        XCTAssertGreaterThan(meta.duration, 0, "duration was \(meta.duration)")
        XCTAssertNotNil(meta.codec, "codec should still populate without capture metadata")
    }

    func testImportedVideoPreservesPreExistingGps() async throws {
        // A video that already carries GPS (different coordinates) must not be stripped.
        let date = Date(timeIntervalSince1970: 1_600_000_000)
        let location = CLLocation(latitude: -33.8688, longitude: 151.2093)
        let items = AVMetadataItemFactory.makeCaptureItems(location: location, date: date)

        let videoDef = try await makeEncryptedVideoDef(name: "video_20200913_122640", metadata: items)
        let meta = try await repository.getVideoMetaData(videoDef)

        let coords = try XCTUnwrap(meta.location, "Pre-existing GPS must be preserved")
        XCTAssertEqual(coords.latitude, -33.8688, accuracy: 1e-4, "latitude was \(coords.latitude)")
        XCTAssertEqual(coords.longitude, 151.2093, accuracy: 1e-4, "longitude was \(coords.longitude)")
    }

    // MARK: - Helpers

    /// Write a tiny real .mov (with optional metadata), encrypt it to a .secv in
    /// the repository's videos directory, and return its VideoDef. Encryption uses
    /// the same all-zeros key FakeEncryptionScheme.getDerivedKey() returns, so the
    /// repository can decrypt it.
    private func makeEncryptedVideoDef(name: String, metadata: [AVMetadataItem]) async throws -> VideoDef {
        let plainURL = tempDirectory.appendingPathComponent("\(UUID().uuidString).mov")
        try await writeSyntheticMovie(to: plainURL, metadata: metadata)

        let secvURL = videosDirectory.appendingPathComponent("\(name).secv")
        // The real VideoEncryptionService opens the output with forWritingTo:, which
        // requires the file to already exist.
        FileManager.default.createFile(atPath: secvURL.path, contents: Data())

        let key = SymmetricKey(data: Data(count: 32))  // matches FakeEncryptionScheme.getDerivedKey()
        try await VideoEncryptionService().encryptVideoForDecoy(
            inputURL: plainURL, outputURL: secvURL, encryptionKey: key)

        return VideoDef(videoName: name, videoFormat: "secv", videoFile: secvURL)
    }

    /// Encode a 160x90, ~0.5s H.264 movie using AVAssetWriter, embedding `metadata`.
    private func writeSyntheticMovie(to url: URL, metadata: [AVMetadataItem]) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        if !metadata.isEmpty { writer.metadata = metadata }

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 160,
            AVVideoHeightKey: 90
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB])

        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "test", code: 1) }
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<15 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 5_000_000) }
            if let buffer = makePixelBuffer() {
                adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30))
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? NSError(domain: "test", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "writer status \(writer.status.rawValue)"])
        }
    }

    private func makePixelBuffer() -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let ok = CVPixelBufferCreate(kCFAllocatorDefault, 160, 90, kCVPixelFormatType_32ARGB, nil, &pixelBuffer)
        guard ok == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, 0x7F, CVPixelBufferGetBytesPerRow(buffer) * 90)
        }
        return buffer
    }
}
