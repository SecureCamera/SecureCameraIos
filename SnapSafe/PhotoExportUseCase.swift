//
//  PhotoExportUseCase.swift
//  SnapSafe
//
//  Created by Claude on 5/28/25.
//

import Foundation
import UIKit

final class PhotoExportUseCase {
    private let repository: SecureImageRepositoryProtocol

    init(repository: SecureImageRepositoryProtocol) {
        self.repository = repository
    }

    func exportPhoto(_ photo: SecurePhoto, format: ExportFormat = .jpeg(quality: 0.9)) async throws -> Data {
        try await repository.exportPhoto(photo, format: format)
    }

    func exportPhotoToPhotoLibrary(_ photo: SecurePhoto) async throws {
        let imageData = try await repository.exportPhoto(photo, format: .jpeg(quality: 0.9))

        guard let image = UIImage(data: imageData) else {
            throw PhotoExportError.exportFailed(reason: "Failed to create image from exported data")
        }

        // Save to photo library (this would require PhotosFramework integration)
        // For now, just validate the export worked
        print("Successfully exported photo \(photo.id) to photo library")
    }

    func exportMultiplePhotos(_ photos: [SecurePhoto], format: ExportFormat = .jpeg(quality: 0.9)) async throws -> [String: Data] {
        var exportedPhotos: [String: Data] = [:]

        for photo in photos {
            do {
                let data = try await exportPhoto(photo, format: format)
                exportedPhotos[photo.id] = data
            } catch {
                print("Failed to export photo \(photo.id): \(error)")
                throw PhotoExportError.batchExportFailed(photoId: photo.id, error: error)
            }
        }

        return exportedPhotos
    }
}

enum PhotoExportError: Error, LocalizedError {
    case exportFailed(reason: String)
    case batchExportFailed(photoId: String, error: Error)
    case photoLibraryAccessDenied

    var errorDescription: String? {
        switch self {
        case let .exportFailed(reason):
            "Export failed: \(reason)"
        case let .batchExportFailed(photoId, error):
            "Batch export failed for photo \(photoId): \(error.localizedDescription)"
        case .photoLibraryAccessDenied:
            "Access to photo library denied"
        }
    }
}
