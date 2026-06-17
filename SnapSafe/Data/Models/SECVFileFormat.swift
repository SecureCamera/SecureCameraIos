//
//  SECVFileFormat.swift
//  SnapSafe
//
//  Created by Claude on 1/26/26.
//

import Foundation

/// SECV (Secure Encrypted Camera Video) file format constants and utilities.
///
/// File Format:
/// [Encrypted Chunks]
///   - Per chunk: [12-byte IV][ciphertext][16-byte auth tag]
///
/// [Chunk Index Table: 12 bytes per chunk]
///   - Chunk offset: uint64 (8 bytes)
///   - Encrypted size: uint32 (4 bytes)
///
/// [Trailer: 64 bytes] - Located at end of file
///   - Magic: "SECV" (4 bytes)
///   - Version: uint16 (2 bytes)
///   - Chunk size: uint32 (4 bytes)
///   - Total chunks: uint64 (8 bytes)
///   - Original size: uint64 (8 bytes)
///   - Reserved: padding to 64 bytes (38 bytes)
///
/// The trailer format (chunks first, metadata at end) eliminates the need
/// to rewrite the entire file when encryption completes, preventing memory
/// spikes from loading large videos into RAM.
enum SECVFileFormat {
    static let MAGIC = "SECV"
    static let VERSION: UInt16 = 1
    static let TRAILER_SIZE = 64
    static let CHUNK_INDEX_ENTRY_SIZE = 12
    static let IV_SIZE = 12
    static let AUTH_TAG_SIZE = 16
    static let DEFAULT_CHUNK_SIZE = 1_048_576 // 1MB

    static let FILE_EXTENSION = "secv"

    // Trailer field offsets
    private static let OFFSET_MAGIC = 0
    private static let OFFSET_VERSION = 4
    private static let OFFSET_CHUNK_SIZE = 6
    private static let OFFSET_TOTAL_CHUNKS = 10
    private static let OFFSET_ORIGINAL_SIZE = 18

    /// Represents the trailer of a SECV file (metadata at end of file).
    struct SecvTrailer: Equatable {
        let version: UInt16
        let chunkSize: UInt32
        let totalChunks: UInt64
        let originalSize: UInt64

        init(version: UInt16, chunkSize: UInt32, totalChunks: UInt64, originalSize: UInt64) {
            self.version = version
            self.chunkSize = chunkSize
            self.totalChunks = totalChunks
            self.originalSize = originalSize
        }

        /// Convert trailer to byte array for writing to file.
        func toData() -> Data {
            var data = Data(count: SECVFileFormat.TRAILER_SIZE)

            // Magic
            data.replaceSubrange(OFFSET_MAGIC..<OFFSET_MAGIC+4, with: SECVFileFormat.MAGIC.data(using: .ascii) ?? Data())
            
            // Version (little-endian)
            withUnsafeBytes(of: version.littleEndian) { data.replaceSubrange(OFFSET_VERSION..<OFFSET_VERSION+2, with: $0) }
            
            // Chunk size (little-endian)
            withUnsafeBytes(of: chunkSize.littleEndian) { data.replaceSubrange(OFFSET_CHUNK_SIZE..<OFFSET_CHUNK_SIZE+4, with: $0) }
            
            // Total chunks (little-endian)
            withUnsafeBytes(of: totalChunks.littleEndian) { data.replaceSubrange(OFFSET_TOTAL_CHUNKS..<OFFSET_TOTAL_CHUNKS+8, with: $0) }
            
            // Original size (little-endian)
            withUnsafeBytes(of: originalSize.littleEndian) { data.replaceSubrange(OFFSET_ORIGINAL_SIZE..<OFFSET_ORIGINAL_SIZE+8, with: $0) }
            
            return data
        }

        /// Parse trailer from byte array.
        static func from(data: Data) throws -> SecvTrailer {
            guard data.count >= TRAILER_SIZE else {
                throw SECVError.invalidTrailerSize
            }

            // Verify magic
            let magicData = data.subdata(in: OFFSET_MAGIC..<OFFSET_MAGIC+4)
            guard let magicString = String(data: magicData, encoding: .ascii), magicString == MAGIC else {
                throw SECVError.invalidMagic
            }

            // Read version
            let version = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: OFFSET_VERSION, as: UInt16.self).littleEndian }

            // Read chunk size
            let chunkSize = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: OFFSET_CHUNK_SIZE, as: UInt32.self).littleEndian }

            // Read total chunks
            let totalChunks = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: OFFSET_TOTAL_CHUNKS, as: UInt64.self).littleEndian }

            // Read original size
            let originalSize = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: OFFSET_ORIGINAL_SIZE, as: UInt64.self).littleEndian }

            return SecvTrailer(
                version: version,
                chunkSize: chunkSize,
                totalChunks: totalChunks,
                originalSize: originalSize
            )
        }
    }

    /// Represents an entry in the chunk index table.
    struct ChunkIndexEntry: Equatable {
        let offset: UInt64
        let encryptedSize: UInt32

        init(offset: UInt64, encryptedSize: UInt32) {
            self.offset = offset
            self.encryptedSize = encryptedSize
        }

        /// Convert chunk index entry to byte array.
        func toData() -> Data {
            var data = Data(count: CHUNK_INDEX_ENTRY_SIZE)
            
            // Offset (little-endian)
            withUnsafeBytes(of: offset.littleEndian) { data.replaceSubrange(0..<8, with: $0) }
            
            // Encrypted size (little-endian)
            withUnsafeBytes(of: encryptedSize.littleEndian) { data.replaceSubrange(8..<12, with: $0) }
            
            return data
        }

        /// Parse chunk index entry from byte array.
        static func from(data: Data, offset: Int = 0) throws -> ChunkIndexEntry {
            guard data.count >= offset + CHUNK_INDEX_ENTRY_SIZE else {
                throw SECVError.invalidChunkIndexEntry
            }

            let subdata = data.subdata(in: offset..<offset+CHUNK_INDEX_ENTRY_SIZE)
            
            // Read offset
            let offsetValue = subdata.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt64.self).littleEndian }

            // Read encrypted size
            let encryptedSize = subdata.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self).littleEndian }

            return ChunkIndexEntry(offset: offsetValue, encryptedSize: encryptedSize)
        }
    }

    /// Calculate the size of encrypted data for a given plaintext size.
    /// Encrypted size = IV (12 bytes) + ciphertext (same as plaintext) + auth tag (16 bytes)
    static func calculateEncryptedChunkSize(plaintextSize: Int) -> Int {
        return IV_SIZE + plaintextSize + AUTH_TAG_SIZE
    }

    /// Calculate the position of the trailer in the file (last 64 bytes).
    /// For trailer format, trailer is at: fileLength - TRAILER_SIZE
    static func calculateTrailerPosition(fileLength: UInt64) -> UInt64 {
        return fileLength - UInt64(TRAILER_SIZE)
    }

    /// Calculate the position of the index table in the file.
    /// For trailer format, index is at: fileLength - TRAILER_SIZE - (totalChunks * CHUNK_INDEX_ENTRY_SIZE)
    static func calculateIndexTablePosition(fileLength: UInt64, totalChunks: UInt64) -> UInt64 {
        return fileLength - UInt64(TRAILER_SIZE) - (totalChunks * UInt64(CHUNK_INDEX_ENTRY_SIZE))
    }

    /// Calculate the plaintext offset for a given chunk index.
    static func calculatePlaintextOffset(chunkIndex: UInt64, chunkSize: UInt32) -> UInt64 {
        return chunkIndex * UInt64(chunkSize)
    }

    /// Calculate the total file size for a given original size and chunk count.
    static func calculateTotalFileSize(originalSize _: UInt64, totalChunks: UInt64) -> UInt64 {
        let encryptedDataSize = totalChunks * UInt64(DEFAULT_CHUNK_SIZE + IV_SIZE + AUTH_TAG_SIZE)
        let indexTableSize = totalChunks * UInt64(CHUNK_INDEX_ENTRY_SIZE)
        return encryptedDataSize + indexTableSize + UInt64(TRAILER_SIZE)
    }
}

/// SECV-specific errors.
enum SECVError: Error, LocalizedError {
    case invalidTrailerSize
    case invalidMagic
    case invalidChunkIndexEntry
    case invalidFileFormat
    case encryptionFailed
    case decryptionFailed
    case fileIOError
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .invalidTrailerSize: return "Invalid SECV trailer size"
        case .invalidMagic: return "Invalid SECV magic number"
        case .invalidChunkIndexEntry: return "Invalid chunk index entry"
        case .invalidFileFormat: return "Invalid SECV file format"
        case .encryptionFailed: return "Video encryption failed"
        case .decryptionFailed: return "Video decryption failed"
        case .fileIOError: return "File I/O error"
        case .checksumMismatch: return "Checksum mismatch"
        }
    }
}