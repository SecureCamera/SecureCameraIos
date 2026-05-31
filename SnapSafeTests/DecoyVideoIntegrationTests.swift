//
//  DecoyVideoIntegrationTests.swift
//  SnapSafeTests
//
//  End-to-end test of marking a video as a decoy using the REAL
//  VideoEncryptionService (not the fake). This is what drives the gallery decoy
//  badge: the badge shows iff isDecoyVideo(videoDef) is true, which requires
//  addDecoyVideoWithKey to actually create the decoy file.
//

import XCTest
import CryptoKit
@testable import SnapSafe

@MainActor
final class DecoyVideoIntegrationTests: XCTestCase {

    private var tempDirectory: URL!
    private var videosDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        videosDirectory = tempDirectory.appendingPathComponent(SecureImageRepository.videosDir)
        try FileManager.default.createDirectory(at: videosDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        videosDirectory = nil
        try await super.tearDown()
    }

    func testMarkingVideoAsDecoyCreatesDecoyWithRealEncryption() async throws {
        let videoService = VideoEncryptionService()
        // FakeEncryptionScheme.getDerivedKey() returns 32 zero bytes; encrypt the
        // source video with that same key so addDecoyVideoWithKey can decrypt it.
        let currentKey = SymmetricKey(data: Data(count: 32))

        // Create a plaintext "video" and encrypt it into the videos directory,
        // exactly as the camera does (pre-create the output, then encrypt).
        let plainURL = tempDirectory.appendingPathComponent("plain.mov")
        try Data(repeating: 0x42, count: 8192).write(to: plainURL)

        let videoFile = videosDirectory.appendingPathComponent("video_20260530_000000.secv")
        FileManager.default.createFile(atPath: videoFile.path, contents: nil)
        try await videoService.encryptVideoForDecoy(inputURL: plainURL, outputURL: videoFile, encryptionKey: currentKey)

        let videoDef = VideoDef(
            videoName: "video_20260530_000000",
            videoFormat: "secv",
            videoFile: videoFile
        )

        let repo = VideoTestableSecureImageRepository(
            tempDirectory: tempDirectory,
            thumbnailCache: FakeThumbnailCache(),
            encryptionScheme: FakeEncryptionScheme(),
            videoEncryptionService: videoService
        )

        // When — mark the video as a decoy (real decrypt + re-encrypt).
        let success = await repo.addDecoyVideoWithKey(videoDef, keyData: Data(repeating: 0xAB, count: 32))

        // Then
        XCTAssertTrue(success, "Marking a video as a decoy must succeed with the real encryption service")
        XCTAssertTrue(repo.isDecoyVideo(videoDef),
                      "isDecoyVideo must be true after marking — this is what drives the gallery decoy badge")
    }

    /// Regression for the SECV decrypt bug: encrypt then decrypt must recover the
    /// original bytes exactly for a single (partial) chunk.
    func testVideoEncryptDecryptRoundTripSingleChunk() async throws {
        try await assertRoundTrip(plaintext: Data((0..<8192).map { UInt8($0 & 0xFF) }))
    }

    /// The case the bug actually broke: a multi-chunk file with a partial final
    /// chunk. Decrypt used to read a full chunkSize for the last chunk, swallowing
    /// the auth tag and throwing fileIOError.
    func testVideoEncryptDecryptRoundTripMultiChunkPartialLast() async throws {
        let size = SECVFileFormat.DEFAULT_CHUNK_SIZE + 5000 // 1 full chunk + a partial one
        try await assertRoundTrip(plaintext: Data((0..<size).map { UInt8($0 & 0xFF) }))
    }

    /// Importing a video encrypts it to a recoverable SECV file in the videos dir.
    func testImportVideoEncryptsRecoverably() async throws {
        let plaintext = Data((0..<8192).map { UInt8($0 & 0xFF) })
        let plainURL = tempDirectory.appendingPathComponent("import.mov")
        try plaintext.write(to: plainURL)

        let repo = VideoTestableSecureImageRepository(
            tempDirectory: tempDirectory,
            thumbnailCache: FakeThumbnailCache(),
            encryptionScheme: FakeEncryptionScheme(),
            videoEncryptionService: VideoEncryptionService()
        )

        let imported = await repo.importVideo(from: plainURL)
        XCTAssertTrue(imported)

        let secv = try FileManager.default
            .contentsOfDirectory(at: videosDirectory, includingPropertiesForKeys: nil)
            .first { $0.pathExtension == "secv" }
        let secvURL = try XCTUnwrap(secv, "import should create a .secv file in the videos directory")
        XCTAssertTrue(secvURL.lastPathComponent.hasPrefix("video_"))

        // Decrypt it back with the same key and verify the original bytes.
        let outURL = tempDirectory.appendingPathComponent("recovered.mov")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        try await VideoEncryptionService().decryptVideoForSharing(
            inputURL: secvURL, outputURL: outURL, encryptionKey: SymmetricKey(data: Data(count: 32)))
        XCTAssertEqual(try Data(contentsOf: outURL), plaintext)
    }

    private func assertRoundTrip(plaintext: Data) async throws {
        let service = VideoEncryptionService()
        let key = SymmetricKey(data: Data(count: 32))

        let plainURL = tempDirectory.appendingPathComponent("\(UUID().uuidString).mov")
        try plaintext.write(to: plainURL)

        let encURL = tempDirectory.appendingPathComponent("\(UUID().uuidString).secv")
        FileManager.default.createFile(atPath: encURL.path, contents: nil)
        try await service.encryptVideoForDecoy(inputURL: plainURL, outputURL: encURL, encryptionKey: key)

        let outURL = tempDirectory.appendingPathComponent("\(UUID().uuidString).mov")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        try await service.decryptVideoForSharing(inputURL: encURL, outputURL: outURL, encryptionKey: key)

        let recovered = try Data(contentsOf: outURL)
        XCTAssertEqual(recovered, plaintext, "decrypt must recover the exact original bytes")
    }
}
