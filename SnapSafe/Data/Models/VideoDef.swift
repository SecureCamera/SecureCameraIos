//
//  VideoDef.swift
//  SnapSafe
//
//  Created by Claude on 1/26/26.
//

import Foundation
import AVFoundation

struct VideoDef: Hashable, Identifiable {
    public let id = UUID()
    let videoName: String
    let videoFormat: String
    let videoFile: URL

    init(videoName: String, videoFormat: String, videoFile: URL) {
        self.videoName = videoName
        self.videoFormat = videoFormat
        self.videoFile = videoFile
    }

    /// Returns true if this video is encrypted (uses .secv format).
    var isEncrypted: Bool {
        return videoFormat == SECVFileFormat.FILE_EXTENSION
    }

    func dateTaken() -> Date? {
        // Extract date from filename format: "video_yyyyMMdd_HHmmss.mov" or "video_yyyyMMdd_HHmmss.secv"
        let dateString = videoName.replacingOccurrences(of: "video_", with: "")
            .replacingOccurrences(of: ".\\($videoFormat)", with: "")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        return formatter.date(from: dateString)
    }

    /// Get the encryption status of the video file.
    func getEncryptionStatus() -> VideoEncryptionStatus {
        if isEncrypted {
            // Check if file has valid SECV format
            do {
                let fileSize = try getFileSize()
                let trailerData = try readTrailerData(fileSize: fileSize)
                let trailer = try SECVFileFormat.SecvTrailer.from(data: trailerData)
                
                // Verify the file size matches the expected format
                let expectedSize = SECVFileFormat.calculateTotalFileSize(
                    originalSize: trailer.originalSize,
                    totalChunks: trailer.totalChunks
                )
                
                if expectedSize == fileSize {
                    return .encrypted
                } else {
                    return .corrupted
                }
            } catch {
                return .corrupted
            }
        } else if videoFormat == "mov" || videoFormat == "mp4" {
            return .unencrypted
        } else {
            return .unknown
        }
    }

    /// Get the file size in bytes.
    private func getFileSize() throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: videoFile.path)
        guard let fileSize = attributes[.size] as? UInt64 else {
            throw SECVError.fileIOError
        }
        return fileSize
    }

    /// Read the trailer data from the end of the file.
    private func readTrailerData(fileSize: UInt64) throws -> Data {
        let trailerPosition = SECVFileFormat.calculateTrailerPosition(fileLength: fileSize)
        let fileHandle = try FileHandle(forReadingFrom: videoFile)
        defer { fileHandle.closeFile() }
        
        try fileHandle.seek(toOffset: UInt64(trailerPosition))
        let trailerData = try fileHandle.read(upToCount: SECVFileFormat.TRAILER_SIZE)
        
        guard let trailerData = trailerData, trailerData.count == SECVFileFormat.TRAILER_SIZE else {
            throw SECVError.invalidTrailerSize
        }
        
        return trailerData
    }

    /// Get video duration if available (for unencrypted videos).
    func getDuration() async -> TimeInterval? {
        guard !isEncrypted else { return nil }
        
        let asset = AVURLAsset(url: videoFile)
        
        // Load duration asynchronously to avoid blocking
        do {
            let duration = try await asset.load(.duration)
            return duration.seconds
        } catch {
            print("Failed to load video duration: \(error)")
            return nil
        }
    }
}

/// Video encryption status.
enum VideoEncryptionStatus {
    case unencrypted   // Video is in plaintext format (.mov, .mp4)
    case encrypted     // Video is properly encrypted (.secv)
    case corrupted     // Video file is corrupted or has invalid format
    case unknown       // Unknown video format
}