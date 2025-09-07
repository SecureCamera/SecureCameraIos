//
//  FakeThumbnailCache.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/7/25.
//

@testable import SnapSafe
import UIKit

@MainActor
final class FakeThumbnailCache: ThumbnailCache {
    var mockThumbnail: UIImage?
    var getThumbnailCalled = false
    var putThumbnailCalled = false
    var evictThumbnailCalled = false
    var clearCalled = false
    
    override func getThumbnail(_ photoDef: PhotoDef) -> UIImage? {
        getThumbnailCalled = true
        return mockThumbnail
    }
    
    override func putThumbnail(_ photoDef: PhotoDef, _ image: UIImage) {
        putThumbnailCalled = true
    }
    
    override func evictThumbnail(_ photoDef: PhotoDef) {
        evictThumbnailCalled = true
    }
    
    override func clear() {
        clearCalled = true
    }
}
