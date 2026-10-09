//
//  SECVFileFormatTests.swift
//  SnapSafeTests
//
//  Created by Claude on 1/26/26.
//

import XCTest
@testable import SnapSafe

final class SECVFileFormatTests: XCTestCase {

    func testTrailerSerialization() throws {
        // Create a test trailer
        let trailer = SECVFileFormat.SecvTrailer(
            version: SECVFileFormat.VERSION,
            chunkSize: UInt32(SECVFileFormat.DEFAULT_CHUNK_SIZE),
            totalChunks: 42,
            originalSize: 10485760 // 10MB
        )

        // Convert to data
        let data = trailer.toData()
        
        // Verify data size
        XCTAssertEqual(data.count, SECVFileFormat.TRAILER_SIZE, "Trailer data should be exactly 64 bytes")

        // Parse back from data
        let parsedTrailer = try SECVFileFormat.SecvTrailer.from(data: data)

        // Verify all fields match
        XCTAssertEqual(parsedTrailer.version, trailer.version, "Version should match")
        XCTAssertEqual(parsedTrailer.chunkSize, trailer.chunkSize, "Chunk size should match")
        XCTAssertEqual(parsedTrailer.totalChunks, trailer.totalChunks, "Total chunks should match")
        XCTAssertEqual(parsedTrailer.originalSize, trailer.originalSize, "Original size should match")
    }

    func testChunkIndexEntrySerialization() throws {
        // Create a test chunk index entry
        let entry = SECVFileFormat.ChunkIndexEntry(
            offset: 1048576,
            encryptedSize: UInt32(1048576 + SECVFileFormat.IV_SIZE + SECVFileFormat.AUTH_TAG_SIZE)
        )

        // Convert to data
        let data = entry.toData()
        
        // Verify data size
        XCTAssertEqual(data.count, SECVFileFormat.CHUNK_INDEX_ENTRY_SIZE, "Chunk index entry should be exactly 12 bytes")

        // Parse back from data
        let parsedEntry = try SECVFileFormat.ChunkIndexEntry.from(data: data)

        // Verify all fields match
        XCTAssertEqual(parsedEntry.offset, entry.offset, "Offset should match")
        XCTAssertEqual(parsedEntry.encryptedSize, entry.encryptedSize, "Encrypted size should match")
    }

    func testEncryptedChunkSizeCalculation() {
        // Test with 1MB chunk
        let chunkSize = SECVFileFormat.DEFAULT_CHUNK_SIZE
        let encryptedSize = SECVFileFormat.calculateEncryptedChunkSize(plaintextSize: chunkSize)
        
        let expectedSize = SECVFileFormat.IV_SIZE + chunkSize + SECVFileFormat.AUTH_TAG_SIZE
        XCTAssertEqual(encryptedSize, expectedSize, "Encrypted chunk size should be IV + plaintext + auth tag")
    }

    func testTrailerPositionCalculation() {
        // Test with a 10MB file
        let fileSize: UInt64 = 10_485_760
        let trailerPosition = SECVFileFormat.calculateTrailerPosition(fileLength: fileSize)
        
        let expectedPosition = fileSize - UInt64(SECVFileFormat.TRAILER_SIZE)
        XCTAssertEqual(trailerPosition, expectedPosition, "Trailer should be at fileSize - 64")
    }

    func testIndexTablePositionCalculation() {
        // Test with a 10MB file and 10 chunks
        let fileSize: UInt64 = 10_485_760
        let totalChunks: UInt64 = 10
        let indexTablePosition = SECVFileFormat.calculateIndexTablePosition(fileLength: fileSize, totalChunks: totalChunks)
        
        let expectedPosition = fileSize - UInt64(SECVFileFormat.TRAILER_SIZE) - (totalChunks * UInt64(SECVFileFormat.CHUNK_INDEX_ENTRY_SIZE))
        XCTAssertEqual(indexTablePosition, expectedPosition, "Index table position calculation should be correct")
    }

    func testPlaintextOffsetCalculation() {
        // Test offset calculation for chunk index 5 with 1MB chunks
        let chunkIndex: UInt64 = 5
        let chunkSize: UInt32 = UInt32(SECVFileFormat.DEFAULT_CHUNK_SIZE)
        let offset = SECVFileFormat.calculatePlaintextOffset(chunkIndex: chunkIndex, chunkSize: chunkSize)
        
        let expectedOffset = chunkIndex * UInt64(chunkSize)
        XCTAssertEqual(offset, expectedOffset, "Plaintext offset should be chunkIndex * chunkSize")
    }

    func testTotalFileSizeCalculation() {
        // Test with 10MB original file and 10 chunks
        let originalSize: UInt64 = 10_485_760
        let totalChunks: UInt64 = 10
        
        let totalFileSize = SECVFileFormat.calculateTotalFileSize(originalSize: originalSize, totalChunks: totalChunks)
        
        // Calculate expected size manually
        let encryptedDataSize = totalChunks * UInt64(SECVFileFormat.DEFAULT_CHUNK_SIZE + SECVFileFormat.IV_SIZE + SECVFileFormat.AUTH_TAG_SIZE)
        let indexTableSize = totalChunks * UInt64(SECVFileFormat.CHUNK_INDEX_ENTRY_SIZE)
        let expectedSize = encryptedDataSize + indexTableSize + UInt64(SECVFileFormat.TRAILER_SIZE)
        
        XCTAssertEqual(totalFileSize, expectedSize, "Total file size calculation should be correct")
    }

    func testInvalidTrailerParsing() {
        // Test parsing invalid trailer data
        let invalidData = Data(repeating: 0, count: SECVFileFormat.TRAILER_SIZE - 1)
        
        XCTAssertThrowsError(try SECVFileFormat.SecvTrailer.from(data: invalidData), "Should throw error for invalid trailer size") {
            error in
            XCTAssertTrue(error is SECVError, "Should throw SECVError")
            if let secvError = error as? SECVError {
                XCTAssertEqual(secvError, SECVError.invalidTrailerSize, "Should be invalidTrailerSize error")
            }
        }
    }

    func testInvalidMagicParsing() {
        // Test parsing trailer with invalid magic
        var invalidData = Data(repeating: 0, count: SECVFileFormat.TRAILER_SIZE)
        invalidData.replaceSubrange(0..<4, with: "INVL".data(using: .ascii) ?? Data())
        
        XCTAssertThrowsError(try SECVFileFormat.SecvTrailer.from(data: invalidData), "Should throw error for invalid magic") {
            error in
            XCTAssertTrue(error is SECVError, "Should throw SECVError")
            if let secvError = error as? SECVError {
                XCTAssertEqual(secvError, SECVError.invalidMagic, "Should be invalidMagic error")
            }
        }
    }

    func testVideoDefEncryptionDetection() {
        // Test VideoDef encryption detection
        let encryptedVideo = VideoDef(
            videoName: "video_20260126_120000",
            videoFormat: SECVFileFormat.FILE_EXTENSION,
            videoFile: URL(fileURLWithPath: "/test/video.secv")
        )

        let unencryptedVideo = VideoDef(
            videoName: "video_20260126_120000",
            videoFormat: "mov",
            videoFile: URL(fileURLWithPath: "/test/video.mov")
        )

        XCTAssertTrue(encryptedVideo.isEncrypted, "Should detect .secv as encrypted")
        XCTAssertFalse(unencryptedVideo.isEncrypted, "Should detect .mov as unencrypted")
    }
}