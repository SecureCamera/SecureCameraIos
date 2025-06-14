//
//  PhotoImportUseCase.swift
//  SnapSafe
//
//  Created by Claude on 5/28/25.
//

import Foundation
import UIKit

final class PhotoImportUseCase {
    private let repository: SecureImageRepositoryProtocol

    init(repository: SecureImageRepositoryProtocol) {
        self.repository = repository
    }

    func importFromCamera(_ image: UIImage) async throws -> SecurePhoto {
        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            throw PhotoImportError.invalidImageData
        }
        return try await repository.importFromCamera(imageData)
    }

    func importFromLibrary(_ image: UIImage) async throws -> SecurePhoto {
        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            throw PhotoImportError.invalidImageData
        }
        return try await repository.importFromLibrary(imageData)
    }

    func importImageData(_ data: Data, source: ImportSource) async throws -> SecurePhoto {
        switch source {
        case .camera:
            try await repository.importFromCamera(data)
        case .photoLibrary:
            try await repository.importFromLibrary(data)
        }
    }
}

enum ImportSource {
    case camera
    case photoLibrary
}

enum PhotoImportError: Error, LocalizedError {
    case invalidImageData
    case importFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            "Invalid image data provided"
        case let .importFailed(reason):
            "Import failed: \(reason)"
        }
    }
}
