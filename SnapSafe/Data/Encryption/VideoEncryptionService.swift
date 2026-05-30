//
//  VideoEncryptionService.swift
//  SnapSafe
//
//  Created by Claude on 1/26/26.
//

import Foundation
import CryptoKit
import Combine
import Logging

/// Service for encrypting and decrypting videos using the SECV format.
@MainActor
protocol VideoEncryptionServiceProtocol {
    /// Encrypt a video file using SECV format.
    /// - Parameters:
    ///   - inputURL: URL of the unencrypted video file
    ///   - outputURL: URL where the encrypted file should be written
    ///   - encryptionKey: Key to use for encryption
    /// - Returns: Progress publisher and completion promise
    func encryptVideo(inputURL: URL, outputURL: URL, encryptionKey: SymmetricKey) -> (progress: AnyPublisher<Double, Never>, completion: (Result<URL, Error>) -> Void)

    /// Decrypt a video file from SECV format.
    /// - Parameters:
    ///   - inputURL: URL of the encrypted video file
    ///   - outputURL: URL where the decrypted file should be written
    ///   - encryptionKey: Key to use for decryption
    /// - Returns: Progress publisher and completion promise
    func decryptVideo(inputURL: URL, outputURL: URL, encryptionKey: SymmetricKey) -> (progress: AnyPublisher<Double, Never>, completion: (Result<URL, Error>) -> Void)

    /// Decrypt a video file from SECV format, awaiting completion before returning.
    /// Use this instead of decryptVideo when the caller needs the file ready before proceeding.
    func decryptVideoForSharing(inputURL: URL, outputURL: URL, encryptionKey: SymmetricKey) async throws

    /// Encrypt a video file using SECV format, awaiting completion before returning.
    /// Use this when the caller needs the encrypted file ready before proceeding
    /// (e.g. re-encrypting a decoy video with the poison-pill key).
    func encryptVideoForDecoy(inputURL: URL, outputURL: URL, encryptionKey: SymmetricKey) async throws

    /// Validate that a file has proper SECV format.
    /// - Parameter fileURL: URL of the file to validate
    /// - Returns: True if the file has valid SECV format
    func validateSECVFile(fileURL: URL) -> Bool
}

@MainActor
final class VideoEncryptionService: VideoEncryptionServiceProtocol {

    private let logger = Logger.video
    private var cancellables = Set<AnyCancellable>()

    /// Encrypt a video file using SECV format.
    func encryptVideo(inputURL: URL, outputURL: URL, encryptionKey: SymmetricKey) -> (progress: AnyPublisher<Double, Never>, completion: (Result<URL, Error>) -> Void) {
        let progressSubject = PassthroughSubject<Double, Never>()
        
        let completionHandler: (Result<URL, Error>) -> Void = { result in
            switch result {
            case .success(let url):
                self.logger.info("Video encryption completed successfully", metadata: [
                    "file": .string(url.lastPathComponent)
                ])
            case .failure(let error):
                self.logger.error("Video encryption failed", metadata: [
                    "error": .string(error.localizedDescription)
                ])
            }
        }
        
        // Start encryption in background
        Task(priority: .userInitiated) {
            do {
                try await encryptVideoFile(inputURL: inputURL, outputURL: outputURL, encryptionKey: encryptionKey, progressHandler: { progress in
                    progressSubject.send(progress)
                })
                completionHandler(.success(outputURL))
            } catch {
                completionHandler(.failure(error))
            }
        }
        
        return (progressSubject.eraseToAnyPublisher(), completionHandler)
    }

    /// Decrypt a video file from SECV format.
    func decryptVideo(inputURL: URL, outputURL: URL, encryptionKey: SymmetricKey) -> (progress: AnyPublisher<Double, Never>, completion: (Result<URL, Error>) -> Void) {
        let progressSubject = PassthroughSubject<Double, Never>()
        
        let completionHandler: (Result<URL, Error>) -> Void = { result in
            switch result {
            case .success(let url):
                self.logger.info("Video decryption completed successfully", metadata: [
                    "file": .string(url.lastPathComponent)
                ])
            case .failure(let error):
                self.logger.error("Video decryption failed", metadata: [
                    "error": .string(error.localizedDescription)
                ])
            }
        }
        
        // Start decryption in background
        Task(priority: .userInitiated) {
            do {
                try await decryptVideoFile(inputURL: inputURL, outputURL: outputURL, encryptionKey: encryptionKey, progressHandler: { progress in
                    progressSubject.send(progress)
                })
                completionHandler(.success(outputURL))
            } catch {
                completionHandler(.failure(error))
            }
        }
        
        return (progressSubject.eraseToAnyPublisher(), completionHandler)
    }

    func decryptVideoForSharing(inputURL: URL, outputURL: URL, encryptionKey: SymmetricKey) async throws {
        try await decryptVideoFile(inputURL: inputURL, outputURL: outputURL, encryptionKey: encryptionKey, progressHandler: { _ in })
    }

    func encryptVideoForDecoy(inputURL: URL, outputURL: URL, encryptionKey: SymmetricKey) async throws {
        try await encryptVideoFile(inputURL: inputURL, outputURL: outputURL, encryptionKey: encryptionKey, progressHandler: { _ in })
    }

    /// Validate that a file has proper SECV format.
    func validateSECVFile(fileURL: URL) -> Bool {
        do {
            let fileSize = try getFileSize(fileURL: fileURL)
            let trailerData = try readTrailerData(fileURL: fileURL, fileSize: fileSize)
            let trailer = try SECVFileFormat.SecvTrailer.from(data: trailerData)
            
            // Verify the file size matches the expected format
            let expectedSize = SECVFileFormat.calculateTotalFileSize(
                originalSize: trailer.originalSize,
                totalChunks: trailer.totalChunks
            )
            
            return expectedSize == fileSize
        } catch {
            logger.warning("SECV validation failed", metadata: [
                "file": .string(fileURL.lastPathComponent),
                "error": .string(error.localizedDescription)
            ])
            return false
        }
    }

    // MARK: - Private Implementation

    /// Main encryption method that processes the video file.
    private func encryptVideoFile(inputURL: URL, outputURL: URL, encryptionKey: SymmetricKey, progressHandler: @escaping (Double) -> Void) async throws {
        logger.info("Starting video encryption", metadata: [
            "input": .string(inputURL.lastPathComponent),
            "output": .string(outputURL.lastPathComponent)
        ])

        // Get file size and calculate chunks
        let fileSize = try getFileSize(fileURL: inputURL)
        let chunkSize = SECVFileFormat.DEFAULT_CHUNK_SIZE
        let totalChunks = (fileSize + UInt64(chunkSize) - 1) / UInt64(chunkSize)
        
        logger.info("Video encryption parameters", metadata: [
            "fileSize": .stringConvertible(fileSize),
            "chunkSize": .stringConvertible(chunkSize),
            "totalChunks": .stringConvertible(totalChunks)
        ])

        // Open input and output files
        let inputFile = try FileHandle(forReadingFrom: inputURL)
        defer { inputFile.closeFile() }

        let outputFile = try FileHandle(forWritingTo: outputURL)
        defer { outputFile.closeFile() }

        // Process each chunk
        var currentOffset: UInt64 = 0
        var chunksProcessed: UInt64 = 0

        for _ in 0..<totalChunks {
            // Calculate chunk size (last chunk may be smaller)
            let remainingBytes = fileSize - currentOffset
            let currentChunkSize = min(UInt64(chunkSize), remainingBytes)
            
            // Read plaintext chunk
            try inputFile.seek(toOffset: currentOffset)
            let plaintextData = try inputFile.read(upToCount: Int(currentChunkSize))
            guard let plaintextData = plaintextData, !plaintextData.isEmpty else {
                throw SECVError.fileIOError
            }

            // Generate random IV for this chunk
            let iv = generateRandomIV()

            // Encrypt the chunk
            let encryptedData = try encryptChunk(plaintext: plaintextData, key: encryptionKey, iv: iv)

            // Write IV + ciphertext + auth tag to output
            try outputFile.seekToEnd()
            try outputFile.write(contentsOf: iv)
            try outputFile.write(contentsOf: encryptedData.ciphertext)
            try outputFile.write(contentsOf: encryptedData.tag)

            // Update progress
            chunksProcessed += 1
            let progress = Double(chunksProcessed) / Double(totalChunks)
            progressHandler(progress)

            currentOffset += currentChunkSize
        }

        // Write chunk index table
        try writeChunkIndexTable(outputFile: outputFile, totalChunks: totalChunks, chunkSize: UInt32(chunkSize))

        // Write trailer
        try writeTrailer(outputFile: outputFile, fileSize: fileSize, totalChunks: totalChunks)

        logger.info("Video encryption completed")
    }

    /// Main decryption method that processes the video file.
    private func decryptVideoFile(inputURL: URL, outputURL: URL, encryptionKey: SymmetricKey, progressHandler: @escaping (Double) -> Void) async throws {
        logger.info("Starting video decryption", metadata: [
            "input": .string(inputURL.lastPathComponent),
            "output": .string(outputURL.lastPathComponent)
        ])

        // Read and validate trailer
        let fileSize = try getFileSize(fileURL: inputURL)
        let trailerData = try readTrailerData(fileURL: inputURL, fileSize: fileSize)
        let trailer = try SECVFileFormat.SecvTrailer.from(data: trailerData)

        logger.info("Video decryption parameters", metadata: [
            "originalSize": .stringConvertible(trailer.originalSize),
            "chunkSize": .stringConvertible(trailer.chunkSize),
            "totalChunks": .stringConvertible(trailer.totalChunks)
        ])

        // Open input and output files
        let inputFile = try FileHandle(forReadingFrom: inputURL)
        defer { inputFile.closeFile() }

        let outputFile = try FileHandle(forWritingTo: outputURL)
        defer { outputFile.closeFile() }

        // Process each chunk
        var chunksProcessed: UInt64 = 0

        for chunkIndex in 0..<trailer.totalChunks {
            // Calculate chunk position. Every chunk before the last occupies a
            // full-size slot (chunkSize + IV + tag), so this offset is correct
            // even though the final chunk's data may be smaller.
            let fullChunkSize = UInt64(trailer.chunkSize)
            let chunkDataSize = Int(trailer.chunkSize) + SECVFileFormat.IV_SIZE + SECVFileFormat.AUTH_TAG_SIZE
            let chunkStart = UInt64(chunkIndex) * UInt64(chunkDataSize)

            // The final chunk is usually smaller than chunkSize. AES-GCM ciphertext
            // has the same length as the plaintext, so read only this chunk's real
            // size — reading a full chunkSize would swallow the auth tag (and the
            // index/trailer) and fail with fileIOError.
            let thisChunkSize = min(fullChunkSize, trailer.originalSize - UInt64(chunkIndex) * fullChunkSize)

            // Read IV + ciphertext + auth tag
            try inputFile.seek(toOffset: chunkStart)
            let ivData = try inputFile.read(upToCount: SECVFileFormat.IV_SIZE)
            let ciphertextData = try inputFile.read(upToCount: Int(thisChunkSize))
            let tagData = try inputFile.read(upToCount: SECVFileFormat.AUTH_TAG_SIZE)

            guard let ivData = ivData, ivData.count == SECVFileFormat.IV_SIZE,
                  let ciphertextData = ciphertextData, !ciphertextData.isEmpty,
                  let tagData = tagData, tagData.count == SECVFileFormat.AUTH_TAG_SIZE else {
                throw SECVError.fileIOError
            }

            // Decrypt the chunk
            let decryptedData = try decryptChunk(ciphertext: ciphertextData, key: encryptionKey, iv: ivData, tag: tagData)

            // Write decrypted data to output
            try outputFile.seekToEnd()
            try outputFile.write(contentsOf: decryptedData)

            // Update progress
            chunksProcessed += 1
            let progress = Double(chunksProcessed) / Double(trailer.totalChunks)
            progressHandler(progress)
        }

        logger.info("Video decryption completed")
    }

    // MARK: - Helper Methods

    /// Generate a random 12-byte IV for AES-GCM.
    private func generateRandomIV() -> Data {
        var ivData = Data(count: SECVFileFormat.IV_SIZE)
        let result = ivData.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, SECVFileFormat.IV_SIZE, $0.baseAddress!)
        }
        guard result == errSecSuccess else {
            fatalError("Failed to generate random IV")
        }
        return ivData
    }

    /// Encrypt a single chunk using AES-GCM.
    private func encryptChunk(plaintext: Data, key: SymmetricKey, iv: Data) throws -> (ciphertext: Data, tag: Data) {
        let sealedBox = try AES.GCM.seal(plaintext, using: key, nonce: AES.GCM.Nonce(data: iv))
        return (sealedBox.ciphertext, sealedBox.tag)
    }

    /// Decrypt a single chunk using AES-GCM.
    private func decryptChunk(ciphertext: Data, key: SymmetricKey, iv: Data, tag: Data) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(sealedBox, using: key)
    }

    /// Write the chunk index table to the output file.
    private func writeChunkIndexTable(outputFile: FileHandle, totalChunks: UInt64, chunkSize: UInt32) throws {
        var currentOffset: UInt64 = 0
        var indexTableData = Data()

        for _ in 0..<totalChunks {
            let encryptedChunkSize = SECVFileFormat.calculateEncryptedChunkSize(plaintextSize: Int(chunkSize))
            let entry = SECVFileFormat.ChunkIndexEntry(offset: currentOffset, encryptedSize: UInt32(encryptedChunkSize))
            indexTableData.append(entry.toData())
            currentOffset += UInt64(encryptedChunkSize)
        }

        try outputFile.seekToEnd()
        try outputFile.write(contentsOf: indexTableData)
    }

    /// Write the SECV trailer to the output file.
    private func writeTrailer(outputFile: FileHandle, fileSize: UInt64, totalChunks: UInt64) throws {
        let trailer = SECVFileFormat.SecvTrailer(
            version: SECVFileFormat.VERSION,
            chunkSize: UInt32(SECVFileFormat.DEFAULT_CHUNK_SIZE),
            totalChunks: totalChunks,
            originalSize: fileSize
        )
        let trailerData = trailer.toData()
        try outputFile.seekToEnd()
        try outputFile.write(contentsOf: trailerData)
    }

    /// Get file size in bytes.
    private func getFileSize(fileURL: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let fileSize = attributes[.size] as? UInt64 else {
            throw SECVError.fileIOError
        }
        return fileSize
    }

    /// Read trailer data from the end of the file.
    private func readTrailerData(fileURL: URL, fileSize: UInt64) throws -> Data {
        let trailerPosition = SECVFileFormat.calculateTrailerPosition(fileLength: fileSize)
        let inputFile = try FileHandle(forReadingFrom: fileURL)
        defer { inputFile.closeFile() }
        
        try inputFile.seek(toOffset: trailerPosition)
        let trailerData = try inputFile.read(upToCount: SECVFileFormat.TRAILER_SIZE)
        
        guard let trailerData = trailerData, trailerData.count == SECVFileFormat.TRAILER_SIZE else {
            throw SECVError.invalidTrailerSize
        }
        
        return trailerData
    }
}

