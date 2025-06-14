//
//  PhotoFilter.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/26/25.
//

import Foundation

enum PhotoFilter: String, CaseIterable {
    case all = "All Photos"
    case imported = "Imported Photos"
    case edited = "Edited Photos"
    case withLocation = "Photos with Location"

    var systemImage: String {
        switch self {
        case .all:
            "photo.stack"
        case .imported:
            "square.and.arrow.down"
        case .edited:
            "pencil.circle"
        case .withLocation:
            "location.circle"
        }
    }
}
