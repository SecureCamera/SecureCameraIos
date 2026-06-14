//
//  ThumbnailCache.swift
//  SnapSafe
//
//  Created by Claude on 9/7/25.
//

import UIKit

final class ThumbnailCache {
    private var cache = NSCache<NSString, UIImage>()
    
    init() {
        cache.countLimit = 100
    }
    
    func getThumbnail(_ photoDef: PhotoDef) -> UIImage? {
        return cache.object(forKey: photoDef.photoName as NSString)
    }
    
    func putThumbnail(_ photoDef: PhotoDef, _ image: UIImage) {
        cache.setObject(image, forKey: photoDef.photoName as NSString)
    }
    
    func evictThumbnail(_ photoDef: PhotoDef) {
        cache.removeObject(forKey: photoDef.photoName as NSString)
    }

    // MARK: - Video thumbnails (keyed by video name, prefixed to avoid collisions)

    private func videoKey(_ name: String) -> NSString { "video:\(name)" as NSString }

    func getVideoThumbnail(_ name: String) -> UIImage? {
        return cache.object(forKey: videoKey(name))
    }

    func putVideoThumbnail(_ name: String, _ image: UIImage) {
        cache.setObject(image, forKey: videoKey(name))
    }

    func evictVideoThumbnail(_ name: String) {
        cache.removeObject(forKey: videoKey(name))
    }

    func clearThumbnail(_ photoName: String) {
        cache.removeObject(forKey: photoName as NSString)
    }
    
    func clear() {
        cache.removeAllObjects()
    }
}

// MARK: - Sendable

// NSCache is documented thread-safe; direct access to the backing `cache`
// only happens through this class's own methods, so @unchecked Sendable is
// legitimate here.
extension ThumbnailCache: @unchecked Sendable {}
