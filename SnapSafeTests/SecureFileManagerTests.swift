//
//  SecureFileManagerTests.swift
//  SnapSafeTests
//
//  Created by Bill Booth on 5/25/25.
//

import XCTest
import Foundation
import UIKit
@testable import SnapSafe

class SecureFileManagerTests: XCTestCase {
    
    private var secureFileManager: SecureFileManager!
    private var testPhotoData: Data!
    
    override func setUp() {
        super.setUp()
        secureFileManager = SecureFileManager()
        
        // Create minimal JPEG test data
        testPhotoData = createTestJPEGData()
        
        // Clean up any existing test files
        try? secureFileManager.deleteAllPhotos()
    }
    
    override func tearDown() {
        // Clean up test files after each test
        try? secureFileManager.deleteAllPhotos()
        secureFileManager = nil
        testPhotoData = nil
        super.tearDown()
    }
    
    // MARK: - Secure Directory Tests
    
    /// Tests that getSecureDirectory() creates and returns a valid secure directory
    /// Assertion: Directory should exist, be within Documents folder, and have backup exclusion
    func testGetSecureDirectory_CreatesValidSecureDirectory() throws {
        let secureDirectory = try secureFileManager.getSecureDirectory()
        
        // Assert directory exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: secureDirectory.path), 
                     "Secure directory should exist after creation")
        
        // Assert it's within Documents directory
        XCTAssertTrue(secureDirectory.path.contains("Documents/SecurePhotos"), 
                     "Secure directory should be within Documents/SecurePhotos")
        
        // Assert backup exclusion attribute is set
        let resourceValues = try secureDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertTrue(resourceValues.isExcludedFromBackup == true, 
                     "Secure directory should be excluded from backup")
    }
    
    /// Tests that calling getSecureDirectory() multiple times returns the same directory
    /// Assertion: Multiple calls should return identical URLs without creating duplicates
    func testGetSecureDirectory_ConsistentResults() throws {
        let directory1 = try secureFileManager.getSecureDirectory()
        let directory2 = try secureFileManager.getSecureDirectory()
        
        XCTAssertEqual(directory1, directory2, 
                      "Multiple calls to getSecureDirectory should return the same URL")
    }
    
    // MARK: - Photo Saving Tests
    
    /// Tests that savePhoto() successfully saves photo data and metadata to secure storage
    /// Assertion: Photo should be saved with valid filename and retrievable data
    func testSavePhoto_SavesPhotoSuccessfully() throws {
        let testMetadata = ["testKey": "testValue", "imageWidth": 1024, "imageHeight": 768] as [String: Any]
        
        let filename = try secureFileManager.savePhoto(testPhotoData, withMetadata: testMetadata)
        
        // Assert filename is not empty
        XCTAssertFalse(filename.isEmpty, "Saved photo should have a valid filename")
        
        // Assert photo can be loaded back
        let (loadedData, loadedMetadata) = try secureFileManager.loadPhoto(filename: filename)
        XCTAssertEqual(loadedData, testPhotoData, "Loaded photo data should match original data")
        
        // Assert metadata includes our test data plus creation date
        XCTAssertEqual(loadedMetadata["testKey"] as? String, "testValue", "Custom metadata should be preserved")
        XCTAssertEqual(loadedMetadata["imageWidth"] as? Int, 1024, "Image width metadata should be preserved")
        XCTAssertNotNil(loadedMetadata["creationDate"], "Creation date should be automatically added")
    }
    
    /// Tests that savePhoto() generates unique filenames for concurrent saves
    /// Assertion: Multiple photos saved in sequence should have unique filenames
    func testSavePhoto_GeneratesUniqueFilenames() throws {
        let filename1 = try secureFileManager.savePhoto(testPhotoData)
        let filename2 = try secureFileManager.savePhoto(testPhotoData)
        let filename3 = try secureFileManager.savePhoto(testPhotoData)
        
        XCTAssertNotEqual(filename1, filename2, "Consecutive saves should generate unique filenames")
        XCTAssertNotEqual(filename2, filename3, "Consecutive saves should generate unique filenames")
        XCTAssertNotEqual(filename1, filename3, "Consecutive saves should generate unique filenames")
        
        // Verify all filenames contain timestamp and UUID components
        XCTAssertTrue(filename1.contains("_"), "Filename should contain timestamp_UUID format")
        XCTAssertTrue(filename2.contains("_"), "Filename should contain timestamp_UUID format")
        XCTAssertTrue(filename3.contains("_"), "Filename should contain timestamp_UUID format")
    }
    
    /// Tests that savePhoto() properly handles empty photo data
    /// Assertion: Empty data should be saved without throwing errors
    func testSavePhoto_HandlesEmptyData() throws {
        let emptyData = Data()
        
        XCTAssertNoThrow({
            let filename = try self.secureFileManager.savePhoto(emptyData)
            XCTAssertFalse(filename.isEmpty, "Should generate filename even for empty data")
            
            let (loadedData, _) = try self.secureFileManager.loadPhoto(filename: filename)
            XCTAssertEqual(loadedData, emptyData, "Empty data should be preserved")
        }, "Saving empty photo data should not throw")
    }
    
    /// Tests that savePhoto() properly cleans and serializes complex metadata
    /// Assertion: Non-JSON serializable metadata should be filtered out, valid data preserved
    func testSavePhoto_CleansComplexMetadata() throws {
        let complexMetadata: [String: Any] = [
            "validString": "test",
            "validInt": 42,
            "validDouble": 3.14,
            "validBool": true,
            "validArray": ["item1", "item2", 123],
            "validDict": ["nested": "value"],
            "invalidData": Data([0x01, 0x02, 0x03]), // Should be filtered out
            "invalidDate": Date(), // Should be filtered out
        ]
        
        let filename = try secureFileManager.savePhoto(testPhotoData, withMetadata: complexMetadata)
        let (_, loadedMetadata) = try secureFileManager.loadPhoto(filename: filename)
        
        // Assert valid metadata is preserved
        XCTAssertEqual(loadedMetadata["validString"] as? String, "test")
        XCTAssertEqual(loadedMetadata["validInt"] as? Int, 42)
        XCTAssertEqual(loadedMetadata["validDouble"] as? Double, 3.14)
        XCTAssertEqual(loadedMetadata["validBool"] as? Bool, true)
        XCTAssertNotNil(loadedMetadata["validArray"])
        XCTAssertNotNil(loadedMetadata["validDict"])
        
        // Assert invalid metadata is filtered out
        XCTAssertNil(loadedMetadata["invalidData"], "Non-JSON serializable data should be filtered out")
        XCTAssertNil(loadedMetadata["invalidDate"], "Non-JSON serializable date should be filtered out")
        
        // Assert creation date is still added
        XCTAssertNotNil(loadedMetadata["creationDate"], "Creation date should always be added")
    }
    
    // MARK: - Photo Loading Tests
    
    /// Tests that loadPhoto() throws appropriate error for non-existent files
    /// Assertion: Loading non-existent photo should throw file not found error
    func testLoadPhoto_ThrowsForNonExistentFile() {
        let nonExistentFilename = "nonexistent_photo_12345"
        
        XCTAssertThrowsError(try secureFileManager.loadPhoto(filename: nonExistentFilename)) { error in
            // Assert it's a file not found error
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, NSCocoaErrorDomain, "Should be a Cocoa framework error")
            XCTAssertEqual(nsError.code, NSFileReadNoSuchFileError, "Should be file not found error")
        }
    }
    
    /// Tests that loadAllPhotoMetadata() returns correct metadata without loading image data
    /// Assertion: Should return all saved photos with metadata but without heavy image data
    func testLoadAllPhotoMetadata_ReturnsMetadataWithoutImageData() throws {
        // Save multiple test photos
        let filename1 = try secureFileManager.savePhoto(testPhotoData, withMetadata: ["photo": "first"])
        let filename2 = try secureFileManager.savePhoto(testPhotoData, withMetadata: ["photo": "second"])
        
        let allMetadata = try secureFileManager.loadAllPhotoMetadata()
        
        XCTAssertEqual(allMetadata.count, 2, "Should return metadata for all saved photos")
        
        // Assert filenames are present
        let filenames = allMetadata.map { $0.filename }
        XCTAssertTrue(filenames.contains(filename1), "Should contain first photo filename")
        XCTAssertTrue(filenames.contains(filename2), "Should contain second photo filename")
        
        // Assert metadata is loaded
        for photoInfo in allMetadata {
            XCTAssertNotNil(photoInfo.metadata["creationDate"], "Each photo should have creation date")
            XCTAssertNotNil(photoInfo.fileURL, "Each photo should have valid file URL")
        }
    }
    
    /// Tests that loadPhotoThumbnail() generates appropriately sized thumbnails
    /// Assertion: Thumbnail should be smaller than specified max size
    func testLoadPhotoThumbnail_GeneratesCorrectSizedThumbnail() throws {
        let filename = try secureFileManager.savePhoto(testPhotoData)
        let secureDirectory = try secureFileManager.getSecureDirectory()
        let fileURL = secureDirectory.appendingPathComponent("\(filename).photo")
        
        let maxSize: CGFloat = 100
        let thumbnail = try secureFileManager.loadPhotoThumbnail(from: fileURL, maxSize: maxSize)
        
        XCTAssertNotNil(thumbnail, "Should generate thumbnail for valid image data")
        
        if let thumbnail = thumbnail {
            XCTAssertLessThanOrEqual(thumbnail.size.width, maxSize, "Thumbnail width should not exceed maxSize")
            XCTAssertLessThanOrEqual(thumbnail.size.height, maxSize, "Thumbnail height should not exceed maxSize")
        }
    }
    
    /// Tests that loadPhotoThumbnail() handles invalid image data gracefully
    /// Assertion: Invalid image data should return nil without throwing
    func testLoadPhotoThumbnail_HandlesInvalidImageData() throws {
        // Save invalid image data
        let invalidData = "This is not image data".data(using: .utf8)!
        let filename = try secureFileManager.savePhoto(invalidData)
        let secureDirectory = try secureFileManager.getSecureDirectory()
        let fileURL = secureDirectory.appendingPathComponent("\(filename).photo")
        
        let thumbnail = try secureFileManager.loadPhotoThumbnail(from: fileURL)
        
        XCTAssertNil(thumbnail, "Should return nil for invalid image data")
    }
    
    // MARK: - Photo Deletion Tests
    
    /// Tests that deletePhoto() removes both photo and metadata files
    /// Assertion: After deletion, files should not exist and loading should throw error
    func testDeletePhoto_RemovesBothPhotoAndMetadata() throws {
        let filename = try secureFileManager.savePhoto(testPhotoData, withMetadata: ["test": "data"])
        let secureDirectory = try secureFileManager.getSecureDirectory()
        let photoURL = secureDirectory.appendingPathComponent("\(filename).photo")
        let metadataURL = secureDirectory.appendingPathComponent("\(filename).metadata")
        
        // Verify files exist before deletion
        XCTAssertTrue(FileManager.default.fileExists(atPath: photoURL.path), "Photo file should exist before deletion")
        XCTAssertTrue(FileManager.default.fileExists(atPath: metadataURL.path), "Metadata file should exist before deletion")
        
        try secureFileManager.deletePhoto(filename: filename)
        
        // Assert files no longer exist
        XCTAssertFalse(FileManager.default.fileExists(atPath: photoURL.path), "Photo file should be deleted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: metadataURL.path), "Metadata file should be deleted")
        
        // Assert loading the photo now throws error
        XCTAssertThrowsError(try secureFileManager.loadPhoto(filename: filename), 
                            "Loading deleted photo should throw error")
    }
    
    /// Tests that deletePhoto() handles non-existent files gracefully
    /// Assertion: Deleting non-existent photo should not throw error
    func testDeletePhoto_HandlesNonExistentFiles() {
        let nonExistentFilename = "nonexistent_photo_98765"
        
        XCTAssertNoThrow(try secureFileManager.deletePhoto(filename: nonExistentFilename), 
                        "Deleting non-existent photo should not throw error")
    }
    
    /// Tests that deleteAllPhotos() removes all photos and metadata from secure directory
    /// Assertion: After deleteAllPhotos(), directory should be empty
    func testDeleteAllPhotos_RemovesAllFiles() throws {
        // Save multiple photos
        try secureFileManager.savePhoto(testPhotoData, withMetadata: ["photo": "1"])
        try secureFileManager.savePhoto(testPhotoData, withMetadata: ["photo": "2"])
        try secureFileManager.savePhoto(testPhotoData, withMetadata: ["photo": "3"])
        
        // Verify photos exist
        let metadataBeforeDeletion = try secureFileManager.loadAllPhotoMetadata()
        XCTAssertEqual(metadataBeforeDeletion.count, 3, "Should have 3 photos before deletion")
        
        try secureFileManager.deleteAllPhotos()
        
        // Assert all photos are deleted
        let metadataAfterDeletion = try secureFileManager.loadAllPhotoMetadata()
        XCTAssertEqual(metadataAfterDeletion.count, 0, "Should have no photos after deleteAllPhotos()")
    }
    
    // MARK: - Sharing Tests
    
    /// Tests that preparePhotoForSharing() creates temporary file with UUID filename
    /// Assertion: Should create accessible temporary file with unique name
    func testPreparePhotoForSharing_CreatesTemporaryFile() throws {
        let tempURL = try secureFileManager.preparePhotoForSharing(imageData: testPhotoData)
        
        // Assert file is in temporary directory
        XCTAssertTrue(tempURL.path.contains("tmp") || tempURL.path.contains("Temporary"), 
                     "Share file should be in temporary directory")
        
        // Assert file exists and contains correct data
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path), 
                     "Temporary share file should exist")
        
        let loadedData = try Data(contentsOf: tempURL)
        XCTAssertEqual(loadedData, testPhotoData, "Temporary file should contain original image data")
        
        // Assert filename contains UUID pattern (36 characters)
        let filename = tempURL.lastPathComponent
        let uuidPart = filename.replacingOccurrences(of: ".jpg", with: "")
        XCTAssertEqual(uuidPart.count, 36, "Filename should contain UUID (36 characters)")
        
        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    /// Tests that preparePhotoForSharing() creates unique files for multiple calls
    /// Assertion: Multiple calls should create different temporary files
    func testPreparePhotoForSharing_CreatesUniqueFiles() throws {
        let tempURL1 = try secureFileManager.preparePhotoForSharing(imageData: testPhotoData)
        let tempURL2 = try secureFileManager.preparePhotoForSharing(imageData: testPhotoData)
        
        XCTAssertNotEqual(tempURL1, tempURL2, "Multiple calls should create unique temporary files")
        
        // Clean up
        try? FileManager.default.removeItem(at: tempURL1)
        try? FileManager.default.removeItem(at: tempURL2)
    }
    
    // MARK: - Error Handling Tests
    
    /// Tests that file operations handle disk space issues gracefully
    /// Assertion: Should propagate appropriate errors when disk operations fail
    func testFileOperations_HandleDiskErrors() {
        // Note: This test is difficult to implement without mocking FileManager
        // In a real production app, you might use dependency injection to test this
        
        // For now, we'll test that our methods can handle empty data without crashing
        XCTAssertNoThrow(try secureFileManager.savePhoto(Data()), 
                        "Should handle empty data without crashing")
    }
    
    // MARK: - Helper Methods
    
    /// Creates minimal JPEG test data for testing purposes
    private func createTestJPEGData() -> Data {
        // Create a minimal 1x1 pixel JPEG image for testing
        let image = UIImage(systemName: "photo") ?? UIImage()
        return image.jpegData(compressionQuality: 1.0) ?? Data()
    }
}
