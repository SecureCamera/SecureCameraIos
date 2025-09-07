//
//  ThumbnailCache.swift
//  SnapSafe
//
//  Created by Claude on 9/7/25.
//

import UIKit

@MainActor
class ThumbnailCache {
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
    
    func clear() {
        cache.removeAllObjects()
    }
}
