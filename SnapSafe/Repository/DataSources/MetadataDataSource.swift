//
//  MetadataDataSource.swift
//  SnapSafe
//
//  Created by Claude on 5/28/25.
//

import Foundation

final class MetadataDataSource: MetadataDataSourceProtocol {
    private let documentsDirectory: URL
    private let metadataDirectory: URL

    init() throws {
        documentsDirectory = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        metadataDirectory = documentsDirectory.appendingPathComponent("PhotoMetadata")
        try createMetadataDirectoryIfNeeded()
    }

    func saveMetadata(_ metadata: PhotoMetadata) async throws {
        let fileURL = metadataDirectory.appendingPathComponent("\(metadata.id).json")
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: fileURL)
    }

    func loadMetadata(withId id: String) async throws -> PhotoMetadata? {
        let fileURL = metadataDirectory.appendingPathComponent("\(id).json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(PhotoMetadata.self, from: data)
    }

    func loadAllMetadata() async throws -> [PhotoMetadata] {
        let contents = try FileManager.default.contentsOfDirectory(at: metadataDirectory, includingPropertiesForKeys: nil)
        var allMetadata: [PhotoMetadata] = []

        for fileURL in contents.filter({ $0.pathExtension == "json" }) {
            let data = try Data(contentsOf: fileURL)
            let metadata = try JSONDecoder().decode(PhotoMetadata.self, from: data)
            allMetadata.append(metadata)
        }

        return allMetadata.sorted { $0.creationDate > $1.creationDate }
    }

    func deleteMetadata(withId id: String) async throws {
        let fileURL = metadataDirectory.appendingPathComponent("\(id).json")
        try FileManager.default.removeItem(at: fileURL)
    }

    func updateMetadata(_ metadata: PhotoMetadata) async throws {
        let updatedMetadata = PhotoMetadata(
            id: metadata.id,
            creationDate: metadata.creationDate,
            modificationDate: Date(),
            fileSize: metadata.fileSize,
            faces: metadata.faces,
            maskMode: metadata.maskMode
        )
        try await saveMetadata(updatedMetadata)
    }

    func findMetadata(matching predicate: PhotoPredicate) async throws -> [PhotoMetadata] {
        let allMetadata = try await loadAllMetadata()

        return allMetadata.filter { metadata in
            if let dateRange = predicate.dateRange {
                guard dateRange.contains(metadata.creationDate) else { return false }
            }

            if let hasFaces = predicate.hasFaces {
                guard (metadata.faces.count > 0) == hasFaces else { return false }
            }

            if let maskMode = predicate.maskMode {
                guard metadata.maskMode == maskMode else { return false }
            }

            return true
        }
    }

    private func createMetadataDirectoryIfNeeded() throws {
        if !FileManager.default.fileExists(atPath: metadataDirectory.path) {
            try FileManager.default.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        }
    }
}
