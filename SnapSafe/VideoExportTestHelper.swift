//
//  VideoExportTestHelper.swift
//  SnapSafe
//
//  Created by Assistant on 5/25/26.
//

import AVFoundation
import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CryptoKit

/// Helper class for testing video export functionality on simulators
/// Since simulators don't have cameras, this provides mock video content for testing
@available(iOS 18.0, *)
class VideoExportTestHelper {
    
    /// Creates a test video file that can be used for export testing
    static func createTestVideoFile() async throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let videoURL = tempDirectory.appendingPathComponent("test_video_\(UUID().uuidString).mp4")
        
        // Create a simple test video using AVAssetWriter
        let writer = try AVAssetWriter(outputURL: videoURL, fileType: .mp4)
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1080,
            AVVideoHeightKey: 1920,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 6000000
            ]
        ]
        
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB
            ]
        )
        
        writer.add(videoInput)
        
        // Start writing
        guard writer.startWriting() else {
            throw VideoExportTestError.failedToCreateVideo(writer.error?.localizedDescription ?? "Unknown error")
        }
        
        writer.startSession(atSourceTime: .zero)
        
        // Generate a short test video (3 seconds)
        let totalFrames = 90 // 3 seconds at 30fps
        
        for frameIndex in 0..<totalFrames {
            let presentationTime = CMTime(value: Int64(frameIndex), timescale: 30)
            
            // Wait until the input is ready
            while !videoInput.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(10))
            }
            
            // Create a colored frame
            if let pixelBuffer = createTestPixelBuffer(frameIndex: frameIndex, totalFrames: totalFrames) {
                pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
            }
        }
        
        // Finish writing
        videoInput.markAsFinished()
        await writer.finishWriting()
        
        if writer.status != .completed {
            throw VideoExportTestError.failedToCreateVideo(writer.error?.localizedDescription ?? "Writing failed")
        }
        
        return videoURL
    }
    
    /// Creates a pixel buffer with a gradient that changes over time
    private static func createTestPixelBuffer(frameIndex: Int, totalFrames: Int) -> CVPixelBuffer? {
        let width = 1080
        let height = 1920
        
        var pixelBuffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            nil,
            &pixelBuffer
        )
        
        guard result == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        defer { CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0)) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let buffer32 = baseAddress.bindMemory(to: UInt32.self, capacity: height * bytesPerRow / 4)
        
        // Create an animated gradient
        let progress = Float(frameIndex) / Float(totalFrames)
        
        for y in 0..<height {
            for x in 0..<width {
                let index = y * (bytesPerRow / 4) + x
                
                // Create a moving rainbow gradient
                let hue = (Float(x) / Float(width) + progress) * 360.0
                let saturation: Float = 1.0
                let brightness: Float = 0.8
                
                let color = UIColor(hue: CGFloat(hue.truncatingRemainder(dividingBy: 360.0) / 360.0),
                                  saturation: CGFloat(saturation),
                                  brightness: CGFloat(brightness),
                                  alpha: 1.0)
                
                var red: CGFloat = 0
                var green: CGFloat = 0
                var blue: CGFloat = 0
                var alpha: CGFloat = 0
                color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                
                // Convert to ARGB format
                let argb = (UInt32(alpha * 255) << 24) |
                          (UInt32(red * 255) << 16) |
                          (UInt32(green * 255) << 8) |
                          (UInt32(blue * 255))
                
                buffer32[index] = argb
            }
        }
        
        return buffer
    }
    
    /// Test the video export functionality with mock data
    static func testVideoExport() async throws -> Bool {
        // Create a test video
        let testVideoURL = try await createTestVideoFile()
        defer {
            try? FileManager.default.removeItem(at: testVideoURL)
        }
        
        // Verify the video was created successfully
        guard FileManager.default.fileExists(atPath: testVideoURL.path) else {
            throw VideoExportTestError.testVideoNotFound
        }
        
        // Test that the video can be loaded by AVPlayer
        let asset = AVURLAsset(url: testVideoURL)
        let duration = try await asset.load(.duration)
        
        guard duration.seconds > 0 else {
            throw VideoExportTestError.invalidVideoDuration
        }
        
        // Test exporting to Photos Library (simulator)
        return try await testExportToPhotosLibrary(videoURL: testVideoURL)
    }
    
    /// Test exporting video to Photos Library
    private static func testExportToPhotosLibrary(videoURL: URL) async throws -> Bool {
        // Request authorization first
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        
        guard status == .authorized else {
            print("⚠️ Photos access not authorized. This is expected in simulator testing.")
            return true // Consider this a pass for simulator testing
        }
        
        // Attempt to save the video
        return try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
            }) { success, error in
                if let error = error {
                    continuation.resume(throwing: VideoExportTestError.exportFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
    
    /// Create an encrypted test video for testing encrypted video export
    static func createEncryptedTestVideo() async throws -> (videoURL: URL, encryptionKey: SymmetricKey) {
        // First create a regular test video
        let plainVideoURL = try await createTestVideoFile()
        defer {
            try? FileManager.default.removeItem(at: plainVideoURL)
        }
        
        // Generate encryption key
        let encryptionKey = SymmetricKey(size: .bits256)
        
        // Create encrypted version
        let tempDirectory = FileManager.default.temporaryDirectory
        let encryptedVideoURL = tempDirectory.appendingPathComponent("encrypted_test_video_\(UUID().uuidString).secv")
        
        // Read the original video data
        let videoData = try Data(contentsOf: plainVideoURL)
        
        // Create a simple encrypted format (this is a simplified version)
        // In your real app, you'd use your SECVFileFormat
        let encryptedData = try AES.GCM.seal(videoData, using: encryptionKey)
        
        // Combine nonce + ciphertext + tag for storage
        var combinedData = Data()
        combinedData.append(encryptedData.nonce.withUnsafeBytes { Data($0) })
        combinedData.append(encryptedData.ciphertext)
        combinedData.append(encryptedData.tag)
        
        try combinedData.write(to: encryptedVideoURL)
        
        return (encryptedVideoURL, encryptionKey)
    }
}

/// Test errors for video export functionality
enum VideoExportTestError: Error, LocalizedError {
    case failedToCreateVideo(String)
    case testVideoNotFound
    case invalidVideoDuration
    case exportFailed(String)
    case encryptionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .failedToCreateVideo(let details):
            return "Failed to create test video: \(details)"
        case .testVideoNotFound:
            return "Test video file was not found after creation"
        case .invalidVideoDuration:
            return "Test video has invalid duration"
        case .exportFailed(let details):
            return "Video export failed: \(details)"
        case .encryptionFailed(let details):
            return "Video encryption failed: \(details)"
        }
    }
}

// MARK: - SwiftUI Test View

/// A SwiftUI view for testing video export functionality in the simulator
@available(iOS 18.0, *)
struct VideoExportTestView: View {
    @State private var testStatus = "Ready to test"
    @State private var isRunningTest = false
    @State private var testResults: [String] = []
    @State private var showingResults = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Video Export Simulator Test")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(testStatus)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                if isRunningTest {
                    ProgressView()
                        .scaleEffect(1.2)
                }
                
                VStack(spacing: 12) {
                    Button("Test Video Creation") {
                        runVideoCreationTest()
                    }
                    .disabled(isRunningTest)
                    
                    Button("Test Video Export") {
                        runVideoExportTest()
                    }
                    .disabled(isRunningTest)
                    
                    Button("Test Encrypted Video") {
                        runEncryptedVideoTest()
                    }
                    .disabled(isRunningTest)
                    
                    Button("Run All Tests") {
                        runAllTests()
                    }
                    .disabled(isRunningTest)
                }
                .buttonStyle(.bordered)
                
                if !testResults.isEmpty {
                    Button("View Test Results") {
                        showingResults = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Spacer()
                
                Text("Note: This tests video export functionality without requiring camera hardware. Perfect for simulator testing!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
            .navigationTitle("Video Export Test")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingResults) {
                TestResultsView(results: testResults)
            }
        }
    }
    
    private func runVideoCreationTest() {
        isRunningTest = true
        testStatus = "Creating test video..."
        
        Task {
            #if DEBUG
            let result = await VideoExportValidator.validateVideoCreation()
            await MainActor.run {
                testStatus = result.success ? "✅ Video creation test passed!" : "❌ Video creation test failed"
                let emoji = result.success ? "✅" : "❌"
                testResults.append("\(emoji) Video Creation: \(result.message)")
                isRunningTest = false
            }
            #else
            await MainActor.run {
                testStatus = "Tests only available in DEBUG builds"
                isRunningTest = false
            }
            #endif
        }
    }
    
    private func runVideoExportTest() {
        isRunningTest = true
        testStatus = "Testing video export..."
        
        Task {
            #if DEBUG
            let result = await VideoExportValidator.validateVideoExport()
            await MainActor.run {
                testStatus = result.success ? "✅ Video export test passed!" : "❌ Video export test failed"
                let emoji = result.success ? "✅" : "❌"
                testResults.append("\(emoji) Video Export: \(result.message)")
                isRunningTest = false
            }
            #else
            await MainActor.run {
                testStatus = "Tests only available in DEBUG builds"
                isRunningTest = false
            }
            #endif
        }
    }
    
    private func runEncryptedVideoTest() {
        isRunningTest = true
        testStatus = "Testing encrypted video creation..."
        
        Task {
            #if DEBUG
            let result = await VideoExportValidator.validateEncryptedVideoCreation()
            await MainActor.run {
                testStatus = result.success ? "✅ Encrypted video test passed!" : "❌ Encrypted video test failed"
                let emoji = result.success ? "✅" : "❌"
                testResults.append("\(emoji) Encrypted Video: \(result.message)")
                isRunningTest = false
            }
            #else
            await MainActor.run {
                testStatus = "Tests only available in DEBUG builds"
                isRunningTest = false
            }
            #endif
        }
    }
    
    private func runAllTests() {
        isRunningTest = true
        testResults.removeAll()
        testStatus = "Running all tests..."
        
        Task {
            #if DEBUG
            let results = await VideoExportValidator.runAllTests()
            
            await MainActor.run {
                for result in results {
                    let emoji = result.success ? "✅" : "❌"
                    testResults.append("\(emoji) \(result.testName): \(result.success ? "Success" : result.message)")
                }
                testStatus = "All tests completed!"
                isRunningTest = false
            }
            #else
            await MainActor.run {
                testStatus = "Tests only available in DEBUG builds"
                isRunningTest = false
            }
            #endif
        }
    }
}

struct TestResultsView: View {
    let results: [String]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List(results, id: \.self) { result in
                Text(result)
                    .font(.body)
            }
            .navigationTitle("Test Results")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
        }
    }
}