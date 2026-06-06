//
//  SecureImageRepositoryTests.swift
//  SnapSafeTests
//
//  Created by Claude on 9/7/25.
//

import XCTest
import UIKit
import CoreLocation
@testable import SnapSafe


@MainActor
final class SecureImageRepositoryTests: XCTestCase {
    
    // MARK: - Properties
    
    private var repository: SecureImageRepository!
    private var mockThumbnailCache: FakeThumbnailCache!
    private var mockEncryptionScheme: FakeEncryptionScheme!
    private var tempDirectory: URL!
    private var galleryDirectory: URL!
    private var decoyDirectory: URL!
    private var thumbnailsDirectory: URL!
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create temporary directory for testing
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Set up subdirectories
        galleryDirectory = tempDirectory.appendingPathComponent(SecureImageRepository.photosDir)
        decoyDirectory = tempDirectory.appendingPathComponent(SecureImageRepository.decoysDir)
        thumbnailsDirectory = tempDirectory.appendingPathComponent(SecureImageRepository.thumbnailsDir)
        
        // Create mock dependencies
        mockThumbnailCache = FakeThumbnailCache()
        mockEncryptionScheme = FakeEncryptionScheme()
        
        // Create repository with test directory
        repository = TestableSecureImageRepository(
            tempDirectory: tempDirectory,
            thumbnailCache: mockThumbnailCache,
            encryptionScheme: mockEncryptionScheme
        )
    }
    
    override func tearDown() async throws {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDirectory)
        
        repository = nil
        mockThumbnailCache = nil
        mockEncryptionScheme = nil
        tempDirectory = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Directory Tests
    
    func testGetGalleryDirectoryReturnsCorrectDirectory() {
        // When
        let galleryDir = repository.getGalleryDirectory()
        
        // Then
        XCTAssertEqual(galleryDir, galleryDirectory)
    }
    
    func testGetDecoyDirectoryReturnsCorrectDirectory() {
        // When
        let decoyDir = repository.getDecoyDirectory()

        // Then
        XCTAssertEqual(decoyDir, decoyDirectory)
    }

    /// Regression: hosted unit tests run inside the app's container, so any
    /// directory that is NOT redirected to the temp directory points at the
    /// real app's data. The destructive reset/poison-pill tests delete the
    /// video-thumbnail directories, which would wipe real (unrecoverable)
    /// thumbnails. Every directory the repository writes to must live under
    /// the test temp directory.
    func testAllDirectoriesAreIsolatedToTempDirectory() {
        let dirs: [(String, URL)] = [
            ("gallery", repository.getGalleryDirectory()),
            ("decoy", repository.getDecoyDirectory()),
            ("videos", repository.getVideosDirectory()),
            ("videoThumbnails", repository.getVideoThumbnailsDirectory()),
            ("decoyVideoThumbnails", repository.getDecoyVideoThumbnailsDirectory())
        ]
        for (name, dir) in dirs {
            XCTAssertTrue(
                dir.path.hasPrefix(tempDirectory.path),
                "\(name) directory must be isolated to the test temp dir, got \(dir.path)"
            )
        }
    }
    
    // MARK: - Security Tests
    
    func testEvictKeyCallsEncryptionScheme() async {
        // When
        await repository.evictKey()

        // Then
        XCTAssertTrue(mockEncryptionScheme.evictKeyCalled)
    }

    func testSecurityFailureResetDeletesAllImagesAndEvictsKey() async {
        // Given
        try! FileManager.default.createDirectory(at: galleryDirectory, withIntermediateDirectories: true)

        let photo1 = galleryDirectory.appendingPathComponent("photo_20230101_120000_00.jpg")
        let photo2 = galleryDirectory.appendingPathComponent("photo_20230101_120001_00.jpg")
        try! Data().write(to: photo1)
        try! Data().write(to: photo2)

        // When
        await repository.securityFailureReset()

        // Then
        let photos = repository.getPhotos()
        XCTAssertTrue(photos.isEmpty)
        XCTAssertTrue(mockEncryptionScheme.evictKeyCalled)
    }

    func testActivatePoisonPillDeletesNonDecoyImagesAndEvictsKey() async {
        // Given
        try! FileManager.default.createDirectory(at: galleryDirectory, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: decoyDirectory, withIntermediateDirectories: true)

        // Create regular photos
        let photo1 = galleryDirectory.appendingPathComponent("photo_20230101_120000_00.jpg")
        let photo2 = galleryDirectory.appendingPathComponent("photo_20230101_120001_00.jpg")
        try! Data().write(to: photo1)
        try! Data().write(to: photo2)

        // Create decoy
        let decoyContent = "decoy content".data(using: .utf8)!
        let decoyFile = decoyDirectory.appendingPathComponent("photo_20230101_120000_00.jpg")
        try! decoyContent.write(to: decoyFile)

        // When
        await repository.activatePoisonPill()
        
        // Then
        let photos = repository.getPhotos()
        XCTAssertEqual(photos.count, 1)
        XCTAssertEqual(photos[0].photoName, "photo_20230101_120000_00.jpg")
        
        let targetFile = galleryDirectory.appendingPathComponent("photo_20230101_120000_00.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetFile.path))
        
        let restoredContent = try! Data(contentsOf: targetFile)
        XCTAssertEqual(restoredContent, decoyContent)
        
        XCTAssertTrue(mockEncryptionScheme.evictKeyCalled)
    }
    
    // MARK: - Photo Management Tests
    
    func testGetPhotosReturnsEmptyListWhenDirectoryDoesNotExist() {
        // Given - gallery directory doesn't exist
        
        // When
        let photos = repository.getPhotos()
        
        // Then
        XCTAssertTrue(photos.isEmpty)
    }
    
    func testGetPhotosReturnsListOfPhotosWhenDirectoryExistsWithFiles() {
        // Given
        try! FileManager.default.createDirectory(at: galleryDirectory, withIntermediateDirectories: true)
        
        let photo1 = galleryDirectory.appendingPathComponent("photo_20230101_120000_00.jpg")
        let photo2 = galleryDirectory.appendingPathComponent("photo_20230101_120001_00.jpg")
        try! Data().write(to: photo1)
        try! Data().write(to: photo2)
        
        // When
        let photos = repository.getPhotos()
        
        // Then
        XCTAssertEqual(photos.count, 2)
        XCTAssertTrue(photos.contains { $0.photoName == "photo_20230101_120000_00.jpg" })
        XCTAssertTrue(photos.contains { $0.photoName == "photo_20230101_120001_00.jpg" })
    }
    
    func testDeleteImageRemovesPhotoFileAndThumbnail() {
        // Given
        try! FileManager.default.createDirectory(at: galleryDirectory, withIntermediateDirectories: true)
        
        let photoFile = galleryDirectory.appendingPathComponent("photo_20230101_120000_00.jpg")
        try! Data().write(to: photoFile)
        
        let photoDef = PhotoDef(
            photoName: "photo_20230101_120000_00.jpg",
            photoFormat: "jpg",
            photoFile: photoFile
        )
        
        // When
        let result = repository.deleteImage(photoDef)
        
        // Then
        XCTAssertTrue(result)
        XCTAssertFalse(FileManager.default.fileExists(atPath: photoFile.path))
        XCTAssertTrue(mockThumbnailCache.evictThumbnailCalled)
    }
    
    func testDeleteImageReturnsFalseWhenPhotoDoesNotExist() {
        // Given
        try! FileManager.default.createDirectory(at: galleryDirectory, withIntermediateDirectories: true)
        
        let photoFile = galleryDirectory.appendingPathComponent("photo_20230101_120000_00.jpg")
        // Don't create the file
        
        let photoDef = PhotoDef(
            photoName: "photo_20230101_120000_00.jpg",
            photoFormat: "jpg",
            photoFile: photoFile
        )
        
        // When
        let result = repository.deleteImage(photoDef)
        
        // Then
        XCTAssertFalse(result)
    }
    
    func testDeleteAllImagesDeletesAllPhotos() {
        // Given
        try! FileManager.default.createDirectory(at: galleryDirectory, withIntermediateDirectories: true)
        
        let photo1 = galleryDirectory.appendingPathComponent("photo_20230101_120000_00.jpg")
        let photo2 = galleryDirectory.appendingPathComponent("photo_20230101_120001_00.jpg")
        try! Data().write(to: photo1)
        try! Data().write(to: photo2)
        
        // When
        repository.deleteAllImages()
        
        // Then
        let photos = repository.getPhotos()
        XCTAssertTrue(photos.isEmpty)
    }
    
    // MARK: - Decoy Tests
    
    func testIsDecoyPhotoReturnsTrueWhenDecoyExists() {
        // Given
        try! FileManager.default.createDirectory(at: galleryDirectory, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: decoyDirectory, withIntermediateDirectories: true)
        
        let photoFile = galleryDirectory.appendingPathComponent("photo_20230101_120000_00.jpg")
        let decoyFile = decoyDirectory.appendingPathComponent("photo_20230101_120000_00.jpg")
        try! Data().write(to: photoFile)
        try! Data().write(to: decoyFile)
        
        let photoDef = PhotoDef(
            photoName: "photo_20230101_120000_00.jpg",
            photoFormat: "jpg",
            photoFile: photoFile
        )
        
        // When
        let result = repository.isDecoyPhoto(photoDef)
        
        // Then
        XCTAssertTrue(result)
    }
    
    func testIsDecoyPhotoReturnsFalseWhenDecoyDoesNotExist() {
        // Given
        try! FileManager.default.createDirectory(at: galleryDirectory, withIntermediateDirectories: true)
        
        let photoFile = galleryDirectory.appendingPathComponent("photo_20230101_120000_00.jpg")
        try! Data().write(to: photoFile)
        
        let photoDef = PhotoDef(
            photoName: "photo_20230101_120000_00.jpg",
            photoFormat: "jpg",
            photoFile: photoFile
        )
        
        // When
        let result = repository.isDecoyPhoto(photoDef)
        
        // Then
        XCTAssertFalse(result)
    }
    
    func testNumDecoysReturnsCorrectCount() {
        // Given
        try! FileManager.default.createDirectory(at: decoyDirectory, withIntermediateDirectories: true)
        
        let decoy1 = decoyDirectory.appendingPathComponent("photo_20230101_120000_00.jpg")
        let decoy2 = decoyDirectory.appendingPathComponent("photo_20230101_120001_00.jpg")
        try! Data().write(to: decoy1)
        try! Data().write(to: decoy2)
        
        // When
        let count = repository.numDecoys()
        
        // Then
        XCTAssertEqual(count, 2)
    }
    
    func testAddDecoyPhotoWithKeyAddsPhotoToDecoysWhenUnderLimit() async throws {
        // Given
        try! FileManager.default.createDirectory(at: galleryDirectory, withIntermediateDirectories: true)
        
        let testImageData = createTestImageData()
        let photoFile = galleryDirectory.appendingPathComponent("photo_20230101_120000_00.jpg")
        try! testImageData.write(to: photoFile)
        
        let photoDef = PhotoDef(
            photoName: "photo_20230101_120000_00.jpg",
            photoFormat: "jpg",
            photoFile: photoFile
        )
        
        mockEncryptionScheme.decryptResult = testImageData
        
        // When
        let result = try await repository.addDecoyPhotoWithKey(photoDef, keyData: Data([0x00]))
        
        // Then
        XCTAssertTrue(result)
        XCTAssertTrue(mockEncryptionScheme.encryptWithKeyDataCalled)
    }
    
    func testAddDecoyPhotoReturnsFalseWhenAtLimit() async throws {
        // Given
        try! FileManager.default.createDirectory(at: decoyDirectory, withIntermediateDirectories: true)
        
        // Create max number of decoys
        for i in 0..<SecureImageRepository.maxDecoyPhotos {
            let decoyFile = decoyDirectory.appendingPathComponent("photo_20230101_120000_0\(i).jpg")
            try! Data().write(to: decoyFile)
        }
        
        let photoFile = galleryDirectory.appendingPathComponent("photo_20230101_120000_00.jpg")
        let photoDef = PhotoDef(
            photoName: "photo_20230101_120000_00.jpg",
            photoFormat: "jpg",
            photoFile: photoFile
        )
        
        // When
        let result = try await repository.addDecoyPhotoWithKey(photoDef, keyData: Data([0x00]))
        
        // Then
        XCTAssertFalse(result)
    }
    
    func testRemoveDecoyPhotoRemovesPhotoFromDecoys() async throws {
        // Given
        try! FileManager.default.createDirectory(at: galleryDirectory, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: decoyDirectory, withIntermediateDirectories: true)
        
        let photoFile = galleryDirectory.appendingPathComponent("photo_20230101_120000_00.jpg")
        let decoyFile = decoyDirectory.appendingPathComponent("photo_20230101_120000_00.jpg")
        try! Data().write(to: photoFile)
        try! Data().write(to: decoyFile)
        
        let photoDef = PhotoDef(
            photoName: "photo_20230101_120000_00.jpg",
            photoFormat: "jpg",
            photoFile: photoFile
        )
        
        // When
        let result = repository.removeDecoyPhoto(photoDef)
        
        // Then
        XCTAssertTrue(result)
        XCTAssertFalse(repository.isDecoyPhoto(photoDef))
    }
    
    // MARK: - Image I/O Tests
    
    func testSaveImageEncryptsAndSavesImage() async throws {
        // Given
        let testImage = createTestUIImage()
        let location = CLLocation(latitude: 37.7749, longitude: -122.4194)

        let capturedImage = CapturedImage(
            sensorBitmap: testImage,
            timestamp: Date(timeIntervalSince1970: 1),
            rotationDegrees: 0
        )

        // When
        let photoDef = try await repository.saveImage(
            capturedImage,
            location: location,
            applyRotation: true
        )
        
        // Then
        XCTAssertTrue(FileManager.default.fileExists(atPath: photoDef.photoFile.path))
        XCTAssertTrue(mockEncryptionScheme.encryptToFileCalled)
    }
    
    func testReadImageDecryptsAndReturnsImage() async throws {
        // Given
        try! FileManager.default.createDirectory(at: galleryDirectory, withIntermediateDirectories: true)
        
        let testImageData = createTestImageData()
        let photoFile = galleryDirectory.appendingPathComponent("photo_20230101_120000_00.jpg")
        
        let photoDef = PhotoDef(
            photoName: "photo_20230101_120000_00.jpg",
            photoFormat: "jpg",
            photoFile: photoFile
        )
        
        mockEncryptionScheme.decryptResult = testImageData
        
        // When
        let result = try await repository.readImage(photoDef)
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertTrue(mockEncryptionScheme.decryptFileCalled)
    }
    
    func testDecryptJpgDecryptsAndReturnsImageBytes() async throws {
        // Given
        try! FileManager.default.createDirectory(at: galleryDirectory, withIntermediateDirectories: true)
        
        let testImageData = createTestImageData()
        let photoFile = galleryDirectory.appendingPathComponent("photo_20230101_120000_00.jpg")
        
        let photoDef = PhotoDef(
            photoName: "photo_20230101_120000_00.jpg",
            photoFormat: "jpg",
            photoFile: photoFile
        )
        
        mockEncryptionScheme.decryptResult = testImageData
        
        // When
        let result = try await repository.decryptJpg(photoDef)
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result, testImageData)
        XCTAssertTrue(mockEncryptionScheme.decryptFileCalled)
    }
    
    // MARK: - Thumbnail Tests
    
    func testReadThumbnailReturnsCachedThumbnailIfAvailable() async {
        // Given
        let mockThumbnail = createTestUIImage()
        mockThumbnailCache.mockThumbnail = mockThumbnail
        
        let photoFile = galleryDirectory.appendingPathComponent("photo_20230101_120000_00.jpg")
        let photoDef = PhotoDef(
            photoName: "photo_20230101_120000_00.jpg",
            photoFormat: "jpg",
            photoFile: photoFile
        )
        
        // When
        let result = await repository.readThumbnail(photoDef)
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result, mockThumbnail)
        XCTAssertTrue(mockThumbnailCache.getThumbnailCalled)
        XCTAssertFalse(mockThumbnailCache.putThumbnailCalled)
    }
    
    func testReadThumbnailCreatesThumbnailIfNotInCacheOrFile() async {
        // Given
        try! FileManager.default.createDirectory(at: galleryDirectory, withIntermediateDirectories: true)
        
        let testImageData = createTestImageData()
        let photoFile = galleryDirectory.appendingPathComponent("photo_20230101_120000_00.jpg")
        
        // Create the actual photo file that the repository will try to decrypt
        try! testImageData.write(to: photoFile)
        
        let photoDef = PhotoDef(
            photoName: "photo_20230101_120000_00.jpg",
            photoFormat: "jpg",
            photoFile: photoFile
        )
        
        mockThumbnailCache.mockThumbnail = nil // Cache miss
        mockEncryptionScheme.decryptResult = testImageData
        
        // When
        let result = await repository.readThumbnail(photoDef)
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertTrue(mockThumbnailCache.putThumbnailCalled)
        XCTAssertTrue(mockEncryptionScheme.decryptFileCalled)
    }
    
    // MARK: - Helper Methods
    
    private func createTestUIImage() -> UIImage {
        let size = CGSize(width: 100, height: 100)
        UIGraphicsBeginImageContext(size)
        UIColor.red.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return image
    }
    
    private func createTestImageData() -> Data {
        let image = createTestUIImage()
        return image.jpegData(compressionQuality: 1.0)!
    }
}

// MARK: - Testable Repository

/// Routes every storage directory (including the caches-backed photo thumbnail
/// dir, which is private and was previously un-redirectable) into a temp
/// directory by injecting the base roots. Hosted tests therefore never touch the
/// real app container.
@MainActor
final class TestableSecureImageRepository: SecureImageRepository {
    init(tempDirectory: URL, thumbnailCache: ThumbnailCache, encryptionScheme: EncryptionScheme) {
        super.init(
            thumbnailCache: thumbnailCache,
            encryptionScheme: encryptionScheme,
            applicationSupportDirectory: tempDirectory,
            cachesDirectory: tempDirectory
        )
    }
}
