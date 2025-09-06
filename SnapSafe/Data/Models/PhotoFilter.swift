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
            return "photo.stack"
        case .imported:
            return "square.and.arrow.down"
        case .edited:
            return "pencil.circle"
        case .withLocation:
            return "location.circle"
        }
    }
}