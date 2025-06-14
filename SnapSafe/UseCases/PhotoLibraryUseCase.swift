//
//  PhotoLibraryUseCase.swift
//  SnapSafe
//
//  Created by Claude on 5/28/25.
//

import Foundation

final class PhotoLibraryUseCase {
    private let repository: SecureImageRepositoryProtocol

    init(repository: SecureImageRepositoryProtocol) {
        self.repository = repository
    }

    func loadAllPhotos() async throws -> [SecurePhoto] {
        try await repository.loadAllPhotos()
    }

    func loadPhoto(withId id: String) async throws -> SecurePhoto {
        try await repository.loadPhoto(withId: id)
    }

    func deletePhoto(withId id: String) async throws {
        try await repository.deletePhoto(withId: id)
    }

    func searchPhotos(dateRange: ClosedRange<Date>? = nil, hasFaces: Bool? = nil, maskMode: MaskMode? = nil) async throws -> [SecurePhoto] {
        let predicate = PhotoPredicate(dateRange: dateRange, hasFaces: hasFaces, maskMode: maskMode)
        return try await repository.loadPhotosWithPredicate(predicate)
    }

    func preloadAdjacentPhotos(currentId: String, adjacentCount: Int = 2) async {
        await repository.preloadAdjacentPhotos(currentId: currentId, adjacentCount: adjacentCount)
    }

    func updateFaceDetectionResults(photoId: String, faces: [DetectedFace]) async throws -> SecurePhoto {
        try await repository.updateFaceDetectionResults(photoId, faces: faces)
    }
}
