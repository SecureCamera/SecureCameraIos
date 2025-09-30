//
//  PhotoDef.swift
//  SnapSafe
//
//  Created by Claude on 9/7/25.
//

import Foundation
import UIKit

struct PhotoDef: Hashable, Identifiable {
    public let id = UUID()
    let photoName: String
    let photoFormat: String
    let photoFile: URL
    
    init(photoName: String, photoFormat: String, photoFile: URL) {
        self.photoName = photoName
        self.photoFormat = photoFormat
        self.photoFile = photoFile
    }
    
    func dateTaken() -> Date? {
        // Extract date from filename format: "photo_yyyyMMdd_HHmmss_SS.jpg"
        let dateString = photoName.replacingOccurrences(of: "photo_", with: "")
            .replacingOccurrences(of: ".jpg", with: "")
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss_SS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        return formatter.date(from: dateString)
    }
}
