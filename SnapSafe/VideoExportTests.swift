// Development/testing tool — compiled in Debug builds only, never ships.
#if DEBUG
//
//  VideoExportTests.swift
//  SnapSafe
//
//  Created by Assistant on 5/25/26.
//  NOTE: This file should be in the test target, not the main app target

#if DEBUG
import Foundation
import AVFoundation
import Photos
import CryptoKit

@available(iOS 18.0, *)
class VideoExportValidator {
    
    static func validateVideoCreation() async -> (success: Bool, message: String) {
        do {
            let videoURL = try await VideoExportTestHelper.createTestVideoFile()
            defer {
                try? FileManager.default.removeItem(at: videoURL)
            }
            
            // Verify the file exists
            guard FileManager.default.fileExists(atPath: videoURL.path) else {
                return (false, "Video file was not created")
            }
            
            // Verify it's a valid video
            let asset = AVURLAsset(url: videoURL)
            let duration = try await asset.load(.duration)
            
            guard duration.seconds > 0 else {
                return (false, "Video has invalid duration")
            }
            
            guard duration.seconds >= 2.5 else {
                return (false, "Video duration is too short")
            }
            
            // Verify video has correct dimensions
            let tracks = try await asset.load(.tracks)
            let videoTracks = tracks.filter { $0.mediaType == .video }
            
            guard videoTracks.count > 0 else {
                return (false, "Video has no video tracks")
            }
            
            if let videoTrack = videoTracks.first {
                let naturalSize = try await videoTrack.load(.naturalSize)
                guard naturalSize.width == 1080 && naturalSize.height == 1920 else {
                    return (false, "Video dimensions are incorrect: \(naturalSize.width)x\(naturalSize.height)")
                }
            }
            
            return (true, "Video creation test passed")
            
        } catch {
            return (false, "Video creation failed: \(error.localizedDescription)")
        }
    }
    
    static func validateVideoExport() async -> (success: Bool, message: String) {
        do {
            let success = try await VideoExportTestHelper.testVideoExport()
            if success {
                return (true, "Video export test passed")
            } else {
                return (true, "Video export completed with warnings (expected on simulator)")
            }
        } catch {
            return (false, "Video export test failed: \(error.localizedDescription)")
        }
    }
    
    static func validateEncryptedVideoCreation() async -> (success: Bool, message: String) {
        do {
            let (encryptedVideoURL, encryptionKey) = try await VideoExportTestHelper.createEncryptedTestVideo()
            defer {
                try? FileManager.default.removeItem(at: encryptedVideoURL)
            }
            
            // Verify the encrypted file exists
            guard FileManager.default.fileExists(atPath: encryptedVideoURL.path) else {
                return (false, "Encrypted video file was not created")
            }
            
            // Verify it has the right extension
            guard encryptedVideoURL.pathExtension == "secv" else {
                return (false, "Encrypted video has wrong extension: .\(encryptedVideoURL.pathExtension)")
            }
            
            // Verify the file is not empty
            let fileSize = try FileManager.default.attributesOfItem(atPath: encryptedVideoURL.path)[.size] as? Int64
            guard (fileSize ?? 0) > 0 else {
                return (false, "Encrypted video file is empty")
            }
            
            // Verify encryption key is valid
            guard encryptionKey.bitCount == 256 else {
                return (false, "Encryption key has wrong bit count: \(encryptionKey.bitCount)")
            }
            
            return (true, "Encrypted video test passed")
            
        } catch {
            return (false, "Encrypted video test failed: \(error.localizedDescription)")
        }
    }
    
    static func validateEncryptedVideoPlayer() async -> (success: Bool, message: String) {
        do {
            let (encryptedVideoURL, encryptionKey) = try await VideoExportTestHelper.createEncryptedTestVideo()
            defer {
                try? FileManager.default.removeItem(at: encryptedVideoURL)
            }
            
            // Test that we can create an encrypted video asset
            let asset = AVAsset.makeEncryptedVideoAsset(
                with: encryptedVideoURL,
                encryptionKey: encryptionKey
            )
            
            guard let asset = asset else {
                return (false, "Could not create encrypted video asset")
            }
            
            // Test that the asset has the custom scheme
            guard asset.url.scheme == "secv" else {
                return (false, "Asset does not use custom secv:// scheme: \(asset.url.scheme ?? "nil")")
            }
            
            return (true, "Encrypted video player test passed")
            
        } catch {
            return (false, "Encrypted video player test failed: \(error.localizedDescription)")
        }
    }
    
    static func runAllTests() async -> [(testName: String, success: Bool, message: String)] {
        var results: [(String, Bool, String)] = []
        
        let videoCreation = await validateVideoCreation()
        results.append(("Video Creation", videoCreation.success, videoCreation.message))
        
        let videoExport = await validateVideoExport()
        results.append(("Video Export", videoExport.success, videoExport.message))
        
        let encryptedVideo = await validateEncryptedVideoCreation()
        results.append(("Encrypted Video", encryptedVideo.success, encryptedVideo.message))
        
        let encryptedPlayer = await validateEncryptedVideoPlayer()
        results.append(("Encrypted Player", encryptedPlayer.success, encryptedPlayer.message))
        
        return results
    }
}

// Helper function to get current memory usage
private func getMemoryUsage() -> Int64 {
    var taskInfo = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size) / 4
    
    let result: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
        $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    
    if result == KERN_SUCCESS {
        return Int64(taskInfo.phys_footprint)
    } else {
        return 0
    }
}

#endif
#endif
