//
//  MockSecureImageRepository.swift
//  SnapSafeTests
//
//  Created by Bill Booth on 5/28/25.
//

import Foundation
@testable import SnapSafe

// MARK: - Mock Repository

// class MockSecureImageRepository: SecureImageRepositoryProtocol {
//    var mockPhotos: [SecurePhoto] = []
//    var mockUpdatedPhoto: SecurePhoto?
//    var loadAllPhotosCalled = false
//    var loadPhotoCalled = false
//    var deletePhotoCalled = false
//    var loadPhotosWithPredicateCalled = false
//    var preloadAdjacentPhotosCalled = false
//    var updateFaceDetectionResultsCalled = false
//
//    var lastLoadedPhotoId: String?
//    var lastDeletedPhotoId: String?
//    var lastPredicate: PhotoPredicate?
//    var lastPreloadCurrentId: String?
//    var lastPreloadAdjacentCount: Int?
//    var lastUpdatedPhotoId: String?
//    var lastUpdatedFaces: [DetectedFace]?
//
//    func savePhoto(_ imageData: Data, metadata: PhotoMetadata) async throws -> SecurePhoto {
//        let photo = SecurePhoto(id: metadata.id, encryptedData: imageData, metadata: metadata)
//        mockPhotos.append(photo)
//        return photo
//    }
//
//    func loadPhoto(withId id: String) async throws -> SecurePhoto {
//        loadPhotoCalled = true
//        lastLoadedPhotoId = id
//        guard let photo = mockPhotos.first(where: { $0.id == id }) else {
//            throw SecureImageRepositoryError.photoNotFound(id: id)
//        }
//        return photo
//    }
//
//    func loadAllPhotos() async throws -> [SecurePhoto] {
//        loadAllPhotosCalled = true
//        return mockPhotos
//    }
//
//    func deletePhoto(withId id: String) async throws {
//        deletePhotoCalled = true
//        lastDeletedPhotoId = id
//        mockPhotos.removeAll { $0.id == id }
//    }
//
//    func loadPhotosWithPredicate(_ predicate: PhotoPredicate) async throws -> [SecurePhoto] {
//        loadPhotosWithPredicateCalled = true
//        lastPredicate = predicate
//        return mockPhotos
//    }
//
//    func preloadAdjacentPhotos(currentId: String, adjacentCount: Int) async {
//        preloadAdjacentPhotosCalled = true
//        lastPreloadCurrentId = currentId
//        lastPreloadAdjacentCount = adjacentCount
//    }
//
//    func importFromCamera(_ imageData: Data) async throws -> SecurePhoto {
//        let id = UUID().uuidString
//        let metadata = PhotoMetadata(id: id, fileSize: imageData.count)
//        return try await savePhoto(imageData, metadata: metadata)
//    }
//
//    func importFromLibrary(_ imageData: Data) async throws -> SecurePhoto {
//        let id = UUID().uuidString
//        let metadata = PhotoMetadata(id: id, fileSize: imageData.count)
//        return try await savePhoto(imageData, metadata: metadata)
//    }
//
//    func exportPhoto(_: SecurePhoto, format _: ExportFormat) async throws -> Data {
//        return Data("exported".utf8)
//    }
//
//    func updateFaceDetectionResults(_ photoId: String, faces: [DetectedFace]) async throws -> SecurePhoto {
//        updateFaceDetectionResultsCalled = true
//        lastUpdatedPhotoId = photoId
//        lastUpdatedFaces = faces
//        return mockUpdatedPhoto ?? mockPhotos.first(where: { $0.id == photoId })!
//    }
//
//    func preloadThumbnails(for _: [String]) async {}
//
//    func clearCache() {}
// }
