//
//  DataSourceProtocols.swift
//  SnapSafe
//
//  Created by Claude on 5/28/25.
//

import CryptoKit
import Foundation
import UIKit

// MARK: - FileSystem Data Source Protocol

protocol FileSystemDataSourceProtocol {
    func saveImageData(_ data: Data, withId id: String) async throws -> URL
    func loadImageData(withId id: String) async throws -> Data
    func deleteImageData(withId id: String) async throws
    func getAllImageIds() async throws -> [String]
    func getImageURL(withId id: String) -> URL?
    func imageExists(withId id: String) async -> Bool
}

// MARK: - Encryption Data Source Protocol

protocol EncryptionDataSourceProtocol {
    func encryptImageData(_ data: Data) async throws -> Data
    func decryptImageData(_ encryptedData: Data) async throws -> Data
    func generateSecureKey() async throws -> SymmetricKey
}

// MARK: - Metadata Data Source Protocol

protocol MetadataDataSourceProtocol {
    func saveMetadata(_ metadata: PhotoMetadata) async throws
    func loadMetadata(withId id: String) async throws -> PhotoMetadata?
    func loadAllMetadata() async throws -> [PhotoMetadata]
    func deleteMetadata(withId id: String) async throws
    func updateMetadata(_ metadata: PhotoMetadata) async throws
    func findMetadata(matching predicate: PhotoPredicate) async throws -> [PhotoMetadata]
}

// MARK: - Cache Data Source Protocol

enum CachePriority {
    case high
    case normal
    case low
}

protocol CacheDataSourceProtocol {
    func cacheImage(_ image: UIImage, forId id: String)
    func getCachedImage(forId id: String) -> UIImage?
    func cacheThumbnail(_ thumbnail: UIImage, forId id: String)
    func getCachedThumbnail(forId id: String) -> UIImage?
    func clearCache()
    func clearCacheForId(_ id: String)
    func preloadImages(ids: [String], priority: CachePriority)
}
