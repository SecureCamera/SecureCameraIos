//
//  CacheDataSource.swift
//  SnapSafe
//
//  Created by Claude on 5/28/25.
//

import Foundation
import UIKit

final class CacheDataSource: CacheDataSourceProtocol {
    private let imageCache = NSCache<NSString, UIImage>()
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let preloadQueue = DispatchQueue(label: "com.snapsafe.cache.preload", qos: .background)

    init() {
        setupCaches()
    }

    func cacheImage(_ image: UIImage, forId id: String) {
        imageCache.setObject(image, forKey: NSString(string: id))
    }

    func getCachedImage(forId id: String) -> UIImage? {
        imageCache.object(forKey: NSString(string: id))
    }

    func cacheThumbnail(_ thumbnail: UIImage, forId id: String) {
        thumbnailCache.setObject(thumbnail, forKey: NSString(string: "\(id)_thumb"))
    }

    func getCachedThumbnail(forId id: String) -> UIImage? {
        thumbnailCache.object(forKey: NSString(string: "\(id)_thumb"))
    }

    func clearCache() {
        imageCache.removeAllObjects()
        thumbnailCache.removeAllObjects()
    }

    func clearCacheForId(_ id: String) {
        imageCache.removeObject(forKey: NSString(string: id))
        thumbnailCache.removeObject(forKey: NSString(string: "\(id)_thumb"))
    }

    func preloadImages(ids: [String], priority: CachePriority) {
        let qos: DispatchQoS = switch priority {
        case .high: .userInitiated
        case .normal: .default
        case .low: .background
        }

        DispatchQueue.global(qos: qos.qosClass).async {
            for id in ids {
                // Preloading would be handled by the repository
                // This is a placeholder for preload coordination
            }
        }
    }

    private func setupCaches() {
        // Configure cache limits
        imageCache.countLimit = 20 // Store up to 20 full-size images
        imageCache.totalCostLimit = 100 * 1024 * 1024 // 100MB for full images

        thumbnailCache.countLimit = 100 // Store up to 100 thumbnails
        thumbnailCache.totalCostLimit = 20 * 1024 * 1024 // 20MB for thumbnails
    }
}
