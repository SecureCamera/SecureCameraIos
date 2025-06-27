//
//  PhotoMetadata.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/28/25.
//

import Foundation

struct PhotoMetadata: Codable, Equatable {
    let id: String
    let creationDate: Date
    let modificationDate: Date
    let fileSize: Int
    let faces: [DetectedFace]
    let maskMode: MaskMode
    let isDecoy: Bool

    init(id: String, creationDate: Date = Date(), modificationDate: Date = Date(), fileSize: Int, faces: [DetectedFace] = [], maskMode: MaskMode = .none, isDecoy: Bool = false) {
        self.id = id
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.fileSize = fileSize
        self.faces = faces
        self.maskMode = maskMode
        self.isDecoy = isDecoy
    }
}

// struct PhotoPredicate {
//    let dateRange: ClosedRange<Date>?
//    let hasFaces: Bool?
//    let maskMode: MaskMode?
//
//    init(dateRange: ClosedRange<Date>? = nil, hasFaces: Bool? = nil, maskMode: MaskMode? = nil) {
//        self.dateRange = dateRange
//        self.hasFaces = hasFaces
//        self.maskMode = maskMode
//    }
// }

// enum ExportFormat {
//    case jpeg(quality: CGFloat)
//    case png
//    case heic
// }
