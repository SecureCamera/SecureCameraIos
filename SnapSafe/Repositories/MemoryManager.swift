//
//  MemoryManager.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/20/25.
//

import Foundation

// Singleton memory manager to track and clean up photo memory usage
class MemoryManager {
    static let shared = MemoryManager()

    // Memory tracking counters
    private var loadedFullImages: Int = 0
    private var loadedThumbnails: Int = 0

    // Memory thresholds
    private let maxLoadedFullImages = 3 // Maximum number of full images to keep in memory
    private let maxLoadedThumbnails = 30 // Maximum number of thumbnails to keep in memory
    private let thumbnailCacheDuration: TimeInterval = 60.0 // Time in seconds to keep thumbnails in cache

    // Registry of photos to manage
    private var managedPhotos: [SecurePhoto] = []

    private init() {}

    // Register photos for memory management
    func registerPhotos(_ photos: [SecurePhoto]) {
        managedPhotos = photos
    }

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
        let nonVisiblePhotos = managedPhotos.filter { !$0.isVisible }

        // Sort by last access time (oldest first)
        let sortedPhotos = nonVisiblePhotos.sorted { $0.timeSinceLastAccess > $1.timeSinceLastAccess }

        // Clear memory for the oldest photos
        for photo in sortedPhotos {
            photo.clearMemory(keepThumbnail: true)

            // Stop when we're below threshold
            if loadedFullImages <= maxLoadedFullImages {
                break
            }
        }
    }

    // Free memory for thumbnail images of photos that haven't been accessed recently
    private func cleanupThumbnails() {
        let nonVisiblePhotos = managedPhotos.filter { !$0.isVisible }

        // Find photos whose thumbnails haven't been accessed in a while
        let oldThumbnails = nonVisiblePhotos.filter { $0.timeSinceLastAccess > thumbnailCacheDuration }

        // Clear thumbnails for old photos
        for photo in oldThumbnails {
            photo.clearMemory(keepThumbnail: false)

            // Stop when we're below threshold
            if loadedThumbnails <= maxLoadedThumbnails {
                break
            }
        }
    }

    // Free all memory to reset state
    func freeAllMemory() {
        for photo in managedPhotos {
            photo.clearMemory(keepThumbnail: false)
        }

        loadedFullImages = 0
        loadedThumbnails = 0
    }
}
