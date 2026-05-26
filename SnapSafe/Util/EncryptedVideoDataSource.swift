//
//  EncryptedVideoDataSource.swift
//  SnapSafe
//
//  Created by Claude on 1/26/26.
//

import Foundation
import AVFoundation
import CryptoKit
import Logging
import UniformTypeIdentifiers

/// Custom AVAssetResourceLoaderDelegate for decrypting SECV videos on-the-fly.
/// This enables AVPlayer to play encrypted videos without decrypting the entire file first.
final class EncryptedVideoDataSource: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {

    private let logger = Logger.video
    private let videoURL: URL
    private let encryptionKey: SymmetricKey
    private var fileSize: UInt64 = 0
    private var trailer: SECVFileFormat.SecvTrailer?
    private var chunkCache: [UInt64: Data] = [:] // Simple cache for recently decrypted chunks
    private let cacheSizeLimit = 5 // Max chunks to cache

    /// Initialize with encrypted video URL and decryption key.
    init(videoURL: URL, encryptionKey: SymmetricKey) {
        self.videoURL = videoURL
        self.encryptionKey = encryptionKey
        super.init()

        // Read metadata immediately
        do {
            try setupFileAccess()
        } catch {
            logger.error("Failed to setup encrypted video access", metadata: [
                "error": .string(error.localizedDescription),
                "file": .string(videoURL.lastPathComponent)
            ])
        }
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        logger.debug("Resource loader requested data", metadata: [
            "offset": .stringConvertible(loadingRequest.dataRequest?.requestedOffset ?? 0),
            "length": .stringConvertible(loadingRequest.dataRequest?.requestedLength ?? 0)
        ])

        guard let trailer = trailer else {
            logger.error("No trailer available - cannot fulfill request")
            loadingRequest.finishLoading(with: NSError(domain: "com.snapsafe.video", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video not properly initialized"]))
            return false
        }

        guard let dataRequest = loadingRequest.dataRequest else {
            logger.error("No data request in loading request")
            loadingRequest.finishLoading(with: NSError(domain: "com.snapsafe.video", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid loading request"]))
            return false
        }

        // Handle content information request (metadata about the video)
        if loadingRequest.contentInformationRequest != nil {
            fulfillContentInformationRequest(loadingRequest.contentInformationRequest!)
        }

        // Calculate which chunks are needed for this request
        let requestedOffset = UInt64(dataRequest.requestedOffset)
        let requestedLength = dataRequest.requestedLength

        logger.debug("Processing data request", metadata: [
            "requestedOffset": .stringConvertible(requestedOffset),
            "requestedLength": .stringConvertible(requestedLength),
            "chunkSize": .stringConvertible(trailer.chunkSize)
        ])

        // Calculate chunk range needed
        let startChunk = requestedOffset / UInt64(trailer.chunkSize)
        let endChunk = (requestedOffset + UInt64(requestedLength) - 1) / UInt64(trailer.chunkSize)
        
        logger.debug("Chunk range calculation", metadata: [
            "startChunk": .stringConvertible(startChunk),
            "endChunk": .stringConvertible(endChunk)
        ])

        // Process synchronously on the resource loader queue to avoid
        // concurrent file handle access from parallel Tasks.
        do {
            var fulfilledLength: Int = 0
            var currentOffset = requestedOffset

            for chunkIndex in startChunk...endChunk {
                if fulfilledLength >= requestedLength {
                    break
                }

                let chunkPlaintextOffset = SECVFileFormat.calculatePlaintextOffset(chunkIndex: chunkIndex, chunkSize: trailer.chunkSize)

                // Check cache first
                if let cachedData = chunkCache[chunkIndex] {
                    let dataToProvide = getDataFromChunk(cachedData, chunkPlaintextOffset: chunkPlaintextOffset, requestedOffset: currentOffset, requestedLength: requestedLength - fulfilledLength)

                    if !dataToProvide.isEmpty {
                        dataRequest.respond(with: dataToProvide)
                        fulfilledLength += dataToProvide.count
                        currentOffset += UInt64(dataToProvide.count)
                    }
                    continue
                }

                // Read and decrypt chunk (opens its own file handle)
                let chunkData = try readAndDecryptChunk(chunkIndex: chunkIndex, trailer: trailer)

                cacheChunk(chunkIndex: chunkIndex, data: chunkData)

                let dataToProvide = getDataFromChunk(chunkData, chunkPlaintextOffset: chunkPlaintextOffset, requestedOffset: currentOffset, requestedLength: requestedLength - fulfilledLength)

                if !dataToProvide.isEmpty {
                    dataRequest.respond(with: dataToProvide)
                    fulfilledLength += dataToProvide.count
                    currentOffset += UInt64(dataToProvide.count)
                }
            }

            loadingRequest.finishLoading()

        } catch {
            logger.error("Failed to fulfill loading request", metadata: [
                "error": .string(error.localizedDescription)
            ])
            loadingRequest.finishLoading(with: error)
        }

        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForResponseTo authenticationChallenge: URLAuthenticationChallenge) -> Bool {
        // No authentication needed for local files
        return false
    }

    // MARK: - Private Methods

    /// Setup file access and read metadata.
    private func setupFileAccess() throws {
        logger.info("Setting up encrypted video access", metadata: [
            "file": .string(videoURL.lastPathComponent)
        ])

        // Get file size
        let attributes = try FileManager.default.attributesOfItem(atPath: videoURL.path)
        guard let size = attributes[.size] as? UInt64 else {
            throw SECVError.fileIOError
        }
        fileSize = size

        // Read and parse trailer
        let trailerData = try readTrailerData()
        trailer = try SECVFileFormat.SecvTrailer.from(data: trailerData)

        logger.info("Video file initialized", metadata: [
            "fileSize": .stringConvertible(fileSize),
            "originalSize": .stringConvertible(trailer?.originalSize ?? 0),
            "totalChunks": .stringConvertible(trailer?.totalChunks ?? 0)
        ])
    }

    /// Read trailer data from end of file.
    private func readTrailerData() throws -> Data {
        guard fileSize >= UInt64(SECVFileFormat.TRAILER_SIZE) else {
            throw SECVError.invalidTrailerSize
        }

        let trailerPosition = SECVFileFormat.calculateTrailerPosition(fileLength: fileSize)
        let fileHandle = try FileHandle(forReadingFrom: videoURL)
        defer { fileHandle.closeFile() }
        
        try fileHandle.seek(toOffset: trailerPosition)
        let trailerData = try fileHandle.read(upToCount: SECVFileFormat.TRAILER_SIZE)
        
        guard let trailerData = trailerData, trailerData.count == SECVFileFormat.TRAILER_SIZE else {
            throw SECVError.invalidTrailerSize
        }
        
        return trailerData
    }

    /// Fulfill content information request with video metadata.
    private func fulfillContentInformationRequest(_ request: AVAssetResourceLoadingContentInformationRequest) {
        guard let trailer = trailer else {
            request.contentType = UTType.quickTimeMovie.identifier
            request.contentLength = 0
            request.isByteRangeAccessSupported = true
            return
        }

        request.contentType = UTType.quickTimeMovie.identifier
        request.contentLength = Int64(trailer.originalSize)
        request.isByteRangeAccessSupported = true
        
        logger.debug("Fulfilled content information request", metadata: [
            "contentLength": .stringConvertible(request.contentLength)
        ])
    }

    /// Read and decrypt a single chunk using its own file handle.
    private func readAndDecryptChunk(chunkIndex: UInt64, trailer: SECVFileFormat.SecvTrailer) throws -> Data {
        // Calculate where this chunk starts in the encrypted file.
        // Each full chunk occupies: IV + chunkSize + authTag bytes.
        // The last chunk is smaller: IV + remainingPlaintext + authTag.
        let fullEncryptedChunkSize = UInt64(trailer.chunkSize) + UInt64(SECVFileFormat.IV_SIZE) + UInt64(SECVFileFormat.AUTH_TAG_SIZE)
        let chunkFileOffset = chunkIndex * fullEncryptedChunkSize

        // Determine actual plaintext size for this chunk (last chunk may be smaller)
        let plaintextOffset = chunkIndex * UInt64(trailer.chunkSize)
        let remainingPlaintext = trailer.originalSize - plaintextOffset
        let thisChunkPlaintextSize = Int(min(UInt64(trailer.chunkSize), remainingPlaintext))

        // Open a dedicated file handle for this read
        let fh = try FileHandle(forReadingFrom: videoURL)
        defer { fh.closeFile() }

        try fh.seek(toOffset: chunkFileOffset)

        // Read IV (12 bytes)
        guard let ivData = try fh.read(upToCount: SECVFileFormat.IV_SIZE),
              ivData.count == SECVFileFormat.IV_SIZE else {
            throw SECVError.fileIOError
        }

        // Read ciphertext (exact size for this chunk)
        guard let ciphertextData = try fh.read(upToCount: thisChunkPlaintextSize),
              ciphertextData.count == thisChunkPlaintextSize else {
            throw SECVError.fileIOError
        }

        // Read authentication tag (16 bytes)
        guard let tagData = try fh.read(upToCount: SECVFileFormat.AUTH_TAG_SIZE),
              tagData.count == SECVFileFormat.AUTH_TAG_SIZE else {
            throw SECVError.fileIOError
        }

        let decryptedData = try decryptChunk(ciphertext: ciphertextData, iv: ivData, tag: tagData)

        logger.debug("Decrypted chunk", metadata: [
            "chunkIndex": .stringConvertible(chunkIndex),
            "decryptedSize": .stringConvertible(decryptedData.count)
        ])

        return decryptedData
    }

    /// Decrypt a chunk using AES-GCM.
    private func decryptChunk(ciphertext: Data, iv: Data, tag: Data) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(sealedBox, using: encryptionKey)
    }

    /// Get the specific data range from a decrypted chunk.
    private func getDataFromChunk(_ chunkData: Data, chunkPlaintextOffset: UInt64, requestedOffset: UInt64, requestedLength: Int) -> Data {
        let offsetInChunk = requestedOffset - chunkPlaintextOffset
        let remainingInChunk = chunkData.count - Int(offsetInChunk)
        let lengthToProvide = min(remainingInChunk, requestedLength)
        
        guard lengthToProvide > 0 else {
            return Data()
        }
        
        let range = Int(offsetInChunk)..<Int(offsetInChunk + UInt64(lengthToProvide))
        return chunkData.subdata(in: range)
    }

    /// Cache a decrypted chunk, respecting cache size limits.
    private func cacheChunk(chunkIndex: UInt64, data: Data) {
        chunkCache[chunkIndex] = data
        
        // Enforce cache size limit
        if chunkCache.count > cacheSizeLimit {
            // Remove oldest chunk (simple FIFO cache)
            if let oldestChunkIndex = chunkCache.keys.min() {
                chunkCache.removeValue(forKey: oldestChunkIndex)
            }
        }
        
        logger.debug("Chunk cached", metadata: [
            "chunkIndex": .stringConvertible(chunkIndex),
            "cacheSize": .stringConvertible(chunkCache.count)
        ])
    }
}

// MARK: - AVAsset Extension for Encrypted Videos

extension AVAsset {
    /// Retained resource loader delegates (AVAssetResourceLoader only holds a weak ref).
    nonisolated(unsafe) private static var retainedDelegates = [String: EncryptedVideoDataSource]()

    /// Create an AVAsset that can play encrypted SECV videos.
    /// Uses a custom URL scheme so AVFoundation routes requests through our delegate
    /// instead of trying to read the file directly.
    static func makeEncryptedVideoAsset(with encryptedVideoURL: URL, encryptionKey: SymmetricKey) -> AVURLAsset? {
        // Build a custom-scheme URL so the resource loader delegate is invoked
        var components = URLComponents()
        components.scheme = "secv"
        components.host = "video"
        components.path = "/" + encryptedVideoURL.lastPathComponent
        // Stash the real file path as a query param
        components.queryItems = [URLQueryItem(name: "path", value: encryptedVideoURL.path)]

        guard let customURL = components.url else { return nil }

        let asset = AVURLAsset(url: customURL)
        let delegate = EncryptedVideoDataSource(videoURL: encryptedVideoURL, encryptionKey: encryptionKey)

        // Retain the delegate (AVAssetResourceLoader only keeps a weak reference)
        let key = encryptedVideoURL.lastPathComponent + UUID().uuidString
        Self.retainedDelegates[key] = delegate

        asset.resourceLoader.setDelegate(delegate, queue: DispatchQueue(label: "com.snapsafe.videoResourceLoader"))

        return asset
    }
}