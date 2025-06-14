//
//  FileSystemDataSource.swift
//  SnapSafe
//
//  Created by Claude on 5/28/25.
//

import Foundation

final class FileSystemDataSource: FileSystemDataSourceProtocol {
    private let documentsDirectory: URL
    private let photosDirectory: URL

    init() throws {
        documentsDirectory = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        photosDirectory = documentsDirectory.appendingPathComponent("SecurePhotos")
        try createPhotosDirectoryIfNeeded()
    }

    func saveImageData(_ data: Data, withId id: String) async throws -> URL {
        let fileURL = photosDirectory.appendingPathComponent("\(id).enc")
        try data.write(to: fileURL)
        return fileURL
    }

    func loadImageData(withId id: String) async throws -> Data {
        let fileURL = photosDirectory.appendingPathComponent("\(id).enc")
        return try Data(contentsOf: fileURL)
    }

    func deleteImageData(withId id: String) async throws {
        let fileURL = photosDirectory.appendingPathComponent("\(id).enc")
        try FileManager.default.removeItem(at: fileURL)
    }

    func getAllImageIds() async throws -> [String] {
        let contents = try FileManager.default.contentsOfDirectory(at: photosDirectory, includingPropertiesForKeys: nil)
        return contents
            .filter { $0.pathExtension == "enc" }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    func getImageURL(withId id: String) -> URL? {
        let fileURL = photosDirectory.appendingPathComponent("\(id).enc")
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    func imageExists(withId id: String) async -> Bool {
        let fileURL = photosDirectory.appendingPathComponent("\(id).enc")
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    private func createPhotosDirectoryIfNeeded() throws {
        if !FileManager.default.fileExists(atPath: photosDirectory.path) {
            try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        }
    }
}
