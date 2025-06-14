//
//  EditedPhotoTrackingTests.swift
//  SnapSafeTests
//
//  Created by Bill Booth on 5/26/25.
//

@testable import SnapSafe
import XCTest

class EditedPhotoTrackingTests: XCTestCase {
    var testFileManager: SecureFileManager!
    var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        testFileManager = SecureFileManager()

        // Create a temporary directory for testing
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        testFileManager = nil
        super.tearDown()
    }

    // MARK: - Edited Photo Saving Tests

    func testSavePhoto_WithEditedFlag_ShouldMarkAsEdited() throws {
        // Create test image data
        let testImage = UIImage(systemName: "photo")!
        let imageData = testImage.jpegData(compressionQuality: 0.9)!

        // Save photo with edited flag
        let filename = try testFileManager.savePhoto(
            imageData,
            withMetadata: [:],
            isEdited: true,
            originalFilename: "original_photo_123"
        )

        // Verify file was saved
        XCTAssertFalse(filename.isEmpty, "Filename should not be empty")

        // Load the metadata and verify edited flag
        let (_, metadata) = try testFileManager.loadPhoto(filename: filename)

        XCTAssertTrue(metadata["isEdited"] as? Bool == true, "Photo should be marked as edited")
        XCTAssertEqual(metadata["originalFilename"] as? String, "original_photo_123", "Original filename should be preserved")
    }

    func testSavePhoto_WithoutEditedFlag_ShouldNotMarkAsEdited() throws {
        // Create test image data
        let testImage = UIImage(systemName: "photo")!
        let imageData = testImage.jpegData(compressionQuality: 0.9)!

        // Save photo without edited flag (default behavior)
        let filename = try testFileManager.savePhoto(imageData, withMetadata: [:])

        // Verify file was saved
        XCTAssertFalse(filename.isEmpty, "Filename should not be empty")

        // Load the metadata and verify no edited flag
        let (_, metadata) = try testFileManager.loadPhoto(filename: filename)

        XCTAssertNil(metadata["isEdited"], "Photo should not have isEdited flag")
        XCTAssertNil(metadata["originalFilename"], "Photo should not have originalFilename")
    }

    func testSavePhoto_WithEditedFlagFalse_ShouldNotMarkAsEdited() throws {
        // Create test image data
        let testImage = UIImage(systemName: "photo")!
        let imageData = testImage.jpegData(compressionQuality: 0.9)!

        // Save photo with edited flag explicitly set to false
        let filename = try testFileManager.savePhoto(
            imageData,
            withMetadata: [:],
            isEdited: false
        )

        // Verify file was saved
        XCTAssertFalse(filename.isEmpty, "Filename should not be empty")

        // Load the metadata and verify no edited flag
        let (_, metadata) = try testFileManager.loadPhoto(filename: filename)

        XCTAssertNil(metadata["isEdited"], "Photo should not have isEdited flag when explicitly set to false")
        XCTAssertNil(metadata["originalFilename"], "Photo should not have originalFilename when not edited")
    }

    func testSavePhoto_WithEditedFlagButNoOriginal_ShouldMarkAsEditedWithoutOriginal() throws {
        // Create test image data
        let testImage = UIImage(systemName: "photo")!
        let imageData = testImage.jpegData(compressionQuality: 0.9)!

        // Save photo with edited flag but no original filename
        let filename = try testFileManager.savePhoto(
            imageData,
            withMetadata: [:],
            isEdited: true
        )

        // Verify file was saved
        XCTAssertFalse(filename.isEmpty, "Filename should not be empty")

        // Load the metadata and verify edited flag without original
        let (_, metadata) = try testFileManager.loadPhoto(filename: filename)

        XCTAssertTrue(metadata["isEdited"] as? Bool == true, "Photo should be marked as edited")
        XCTAssertNil(metadata["originalFilename"], "Photo should not have originalFilename when not provided")
    }

    // MARK: - Metadata Preservation Tests

    func testSavePhoto_WithExistingMetadata_ShouldPreserveAndAddEditedFlag() throws {
        // Create test image data
        let testImage = UIImage(systemName: "photo")!
        let imageData = testImage.jpegData(compressionQuality: 0.9)!

        // Create existing metadata
        let existingMetadata: [String: Any] = [
            "customField": "customValue",
            "imported": true,
            "importSource": "PhotosPicker",
        ]

        // Save photo with edited flag and existing metadata
        let filename = try testFileManager.savePhoto(
            imageData,
            withMetadata: existingMetadata,
            isEdited: true,
            originalFilename: "original_photo_456"
        )

        // Load the metadata and verify everything is preserved
        let (_, metadata) = try testFileManager.loadPhoto(filename: filename)

        // Check edited flag and original filename were added
        XCTAssertTrue(metadata["isEdited"] as? Bool == true, "Photo should be marked as edited")
        XCTAssertEqual(metadata["originalFilename"] as? String, "original_photo_456", "Original filename should be preserved")

        // Check existing metadata was preserved
        XCTAssertEqual(metadata["customField"] as? String, "customValue", "Custom metadata should be preserved")
        XCTAssertTrue(metadata["imported"] as? Bool == true, "Imported flag should be preserved")
        XCTAssertEqual(metadata["importSource"] as? String, "PhotosPicker", "Import source should be preserved")

        // Check automatic metadata was added
        XCTAssertNotNil(metadata["creationDate"], "Creation date should be added automatically")
    }

    // MARK: - Edge Cases

    func testSavePhoto_WithEmptyOriginalFilename_ShouldMarkAsEditedWithEmptyOriginal() throws {
        // Create test image data
        let testImage = UIImage(systemName: "photo")!
        let imageData = testImage.jpegData(compressionQuality: 0.9)!

        // Save photo with edited flag and empty original filename
        let filename = try testFileManager.savePhoto(
            imageData,
            withMetadata: [:],
            isEdited: true,
            originalFilename: ""
        )

        // Load the metadata and verify edited flag with empty original
        let (_, metadata) = try testFileManager.loadPhoto(filename: filename)

        XCTAssertTrue(metadata["isEdited"] as? Bool == true, "Photo should be marked as edited")
        XCTAssertEqual(metadata["originalFilename"] as? String, "", "Empty original filename should be preserved")
    }
}
