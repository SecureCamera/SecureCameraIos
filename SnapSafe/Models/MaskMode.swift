//
//  MaskMode.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/22/25.
//

import Foundation

// Different masking modes for face obfuscation
enum MaskMode: String, CaseIterable, Codable {
    case none
    case blur
    case pixelate
    case blackout
    case noise

    var displayName: String {
        switch self {
        case .none:
            "None"
        case .blur:
            "Blur"
        case .pixelate:
            "Pixelate"
        case .blackout:
            "Blackout"
        case .noise:
            "Noise"
        }
    }
}
