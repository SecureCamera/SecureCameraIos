//
//  MemoryManager.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/20/25.
//

import Foundation

// Singleton memory manager to track and clean up photo memory usage
// TODO: I think we can remove this
class MemoryManager {
    static let shared = MemoryManager()

    // Memory tracking counters
    private var loadedFullImages: Int = 0
    private var loadedThumbnails: Int = 0

    // Memory thresholds
    private let maxLoadedFullImages = 3 // Maximum number of full images to keep in memory
    private let maxLoadedThumbnails = 30 // Maximum number of thumbnails to keep in memory
    private let thumbnailCacheDuration: TimeInterval = 60.0 // Time in seconds to keep thumbnails in cache

    private init() {}

    // Report when a full image is loaded
    func reportFullImageLoaded() {
        loadedFullImages += 1
        checkMemoryUsage()
    }

    // Report when a full image is unloaded
    func reportFullImageUnloaded() {
        loadedFullImages = max(0, loadedFullImages - 1)
    }

    // Report when a thumbnail is loaded
    func reportThumbnailLoaded() {
        loadedThumbnails += 1
        checkMemoryUsage()
    }

    // Report when a thumbnail is unloaded
    func reportThumbnailUnloaded() {
        loadedThumbnails = max(0, loadedThumbnails - 1)
    }

    // Check and clean up memory if needed
    func checkMemoryUsage() {
        // Clean up full images if over threshold
        if loadedFullImages > maxLoadedFullImages {
            cleanupFullImages()
        }

        // Clean up thumbnails if over threshold
        if loadedThumbnails > maxLoadedThumbnails {
            cleanupThumbnails()
        }
    }

    // Free memory for photos that are not visible
    private func cleanupFullImages() {

    }

    // Free memory for thumbnail images of photos that haven't been accessed recently
    private func cleanupThumbnails() {

    }

    // Free all memory to reset state
    func freeAllMemory() {

    }
}
