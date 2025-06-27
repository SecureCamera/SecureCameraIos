//
//  RepositoryEnvironment.swift
//  SnapSafe
//
//  Created by Claude on 5/28/25.
//

import SwiftUI

// MARK: - Environment Keys

private struct SecureImageRepositoryKey: EnvironmentKey {
    static let defaultValue: SecureImageRepositoryProtocol = {
        do {
            let keyManager = KeyManager()
            let fileSystemDataSource = try FileSystemDataSource()
            let encryptionDataSource = EncryptionDataSource(keyManager: keyManager)
            let metadataDataSource = try MetadataDataSource()
            let cacheDataSource = CacheDataSource()

            return SecureImageRepository(
                fileSystemDataSource: fileSystemDataSource,
                encryptionDataSource: encryptionDataSource,
                metadataDataSource: metadataDataSource,
                cacheDataSource: cacheDataSource
            )
        } catch {
            fatalError("Failed to initialize SecureImageRepository: \(error)")
        }
    }()
}

private struct PhotoLibraryUseCaseKey: EnvironmentKey {
    static let defaultValue: PhotoLibraryUseCase = .init(repository: SecureImageRepositoryKey.defaultValue)
}

private struct PhotoImportUseCaseKey: EnvironmentKey {
    static let defaultValue: PhotoImportUseCase = .init(repository: SecureImageRepositoryKey.defaultValue)
}

private struct PhotoExportUseCaseKey: EnvironmentKey {
    static let defaultValue: PhotoExportUseCase = .init(repository: SecureImageRepositoryKey.defaultValue)
}

// MARK: - Environment Extensions

extension EnvironmentValues {
    var secureImageRepository: SecureImageRepositoryProtocol {
        get { self[SecureImageRepositoryKey.self] }
        set { self[SecureImageRepositoryKey.self] = newValue }
    }

    var photoLibraryUseCase: PhotoLibraryUseCase {
        get { self[PhotoLibraryUseCaseKey.self] }
        set { self[PhotoLibraryUseCaseKey.self] = newValue }
    }

    var photoImportUseCase: PhotoImportUseCase {
        get { self[PhotoImportUseCaseKey.self] }
        set { self[PhotoImportUseCaseKey.self] = newValue }
    }

    var photoExportUseCase: PhotoExportUseCase {
        get { self[PhotoExportUseCaseKey.self] }
        set { self[PhotoExportUseCaseKey.self] = newValue }
    }
}

// MARK: - Dependency Container

enum DependencyContainer {
    static func setupLiveEnvironment() -> some View {
        EmptyView()
            .environment(\.secureImageRepository, createLiveRepository())
            .environment(\.photoLibraryUseCase, createLivePhotoLibraryUseCase())
            .environment(\.photoImportUseCase, createLivePhotoImportUseCase())
            .environment(\.photoExportUseCase, createLivePhotoExportUseCase())
    }

    static func setupTestEnvironment(
        repository: SecureImageRepositoryProtocol? = nil,
        photoLibraryUseCase: PhotoLibraryUseCase? = nil,
        photoImportUseCase: PhotoImportUseCase? = nil,
        photoExportUseCase: PhotoExportUseCase? = nil
    ) -> some View {
        let testRepository = repository ?? createTestRepository()

        return EmptyView()
            .environment(\.secureImageRepository, testRepository)
            .environment(\.photoLibraryUseCase, photoLibraryUseCase ?? PhotoLibraryUseCase(repository: testRepository))
            .environment(\.photoImportUseCase, photoImportUseCase ?? PhotoImportUseCase(repository: testRepository))
            .environment(\.photoExportUseCase, photoExportUseCase ?? PhotoExportUseCase(repository: testRepository))
    }

    private static func createLiveRepository() -> SecureImageRepositoryProtocol {
        do {
            let keyManager = KeyManager()
            let fileSystemDataSource = try FileSystemDataSource()
            let encryptionDataSource = EncryptionDataSource(keyManager: keyManager)
            let metadataDataSource = try MetadataDataSource()
            let cacheDataSource = CacheDataSource()

            return SecureImageRepository(
                fileSystemDataSource: fileSystemDataSource,
                encryptionDataSource: encryptionDataSource,
                metadataDataSource: metadataDataSource,
                cacheDataSource: cacheDataSource
            )
        } catch {
            fatalError("Failed to create live repository: \(error)")
        }
    }

    private static func createLivePhotoLibraryUseCase() -> PhotoLibraryUseCase {
        PhotoLibraryUseCase(repository: createLiveRepository())
    }

    private static func createLivePhotoImportUseCase() -> PhotoImportUseCase {
        PhotoImportUseCase(repository: createLiveRepository())
    }

    private static func createLivePhotoExportUseCase() -> PhotoExportUseCase {
        PhotoExportUseCase(repository: createLiveRepository())
    }

    private static func createTestRepository() -> SecureImageRepositoryProtocol {
        // For testing, return a mock repository
        // Note: In actual tests, import the shared MockSecureImageRepository
        fatalError("Use MockSecureImageRepository from test target")
    }
}
