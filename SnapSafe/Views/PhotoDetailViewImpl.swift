//
//  PhotoDetailViewImpl.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/18/25.
//

import Foundation
import SwiftUI
import UIKit

// This file is now a forwarder to the refactored PhotoDetailView
// The refactored implementation is in the Views/PhotoDetail directory

// First, establish the SnapSafe namespace
enum SnapSafe {}

// Define the namespace hierarchy
extension SnapSafe {
    enum Views {
        enum PhotoDetail {
            // The actual implementation is in Views/PhotoDetail/PhotoDetailView.swift
        }
    }
}

// Use a typealias to forward to the new implementation
typealias PhotoDetailView = PhotoDetailView_Impl
