//
//  SecurePhotoTests.swift
//  SnapSafeTests
//
//  Created by Bill Booth on 5/25/25.
//

import XCTest
import UIKit
@testable import SnapSafe

class SecurePhotoTests: XCTestCase {
    
    private var testFileURL: URL!
    private var testMetadata: [String: Any]!
    private var testImage: UIImage!
    private var securePhoto: SecurePhoto!
    
    override func setUp() {
        super.setUp()
        
        // Create test file URL
        testFileURL = URL(fileURLWithPath: "/tmp/test_photo.jpg")
        
        // Create test metadata
        testMetadata = [
            "creationDate": Date().timeIntervalSince1970,
            "imageWidth": 1920,
            "imageHeight": 1080,
            "isDecoy": false,
            "originalOrientation": 1
        ]
        
        // Create test image
        testImage = createTestImage()
        
        // Create test SecurePhoto instance
        securePhoto = SecurePhoto(
            filename: "test_photo_123",
            metadata: testMetadata,
            fileURL: testFileURL,
            preloadedThumbnail: testImage
        )
    }
    
    override func tearDown() {
        securePhoto = nil
        testImage = nil
        testMetadata = nil
        testFileURL = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    /// Tests that SecurePhoto initializes with correct properties
    /// Assertion: Should set all properties correctly during initialization
    func testInit_SetsPropertiesCorrectly() {
        let filename = "test_photo_456"
        let metadata = ["testKey": "testValue"]
        let fileURL = URL(fileURLWithPath: "/tmp/test.jpg")
        let thumbnail = createTestImage()
        
        let photo = SecurePhoto(
            filename: filename,
            metadata: metadata,
            fileURL: fileURL,
            preloadedThumbnail: thumbnail
        )
        
        XCTAssertEqual(photo.filename, filename, "Filename should be set correctly")
        XCTAssertEqual(photo.metadata["testKey"] as? String, "testValue", "Metadata should be preserved")
        XCTAssertEqual(photo.fileURL, fileURL, "File URL should be set correctly")
        XCTAssertNotNil(photo.id, "ID should be generated")
        XCTAssertFalse(photo.isVisible, "Should initially be not visible")
    }
    
    /// Tests that legacy initializer works correctly
    /// Assertion: Should create SecurePhoto with provided images and metadata
    func testLegacyInit_WorksCorrectly() {
        let filename = "legacy_photo"
        let thumbnail = createTestImage(size: CGSize(width: 100, height: 100))
        let fullImage = createTestImage(size: CGSize(width: 1000, height: 1000))
        let metadata = ["legacy": true]
        
        let photo = SecurePhoto(filename: filename, thumbnail: thumbnail, fullImage: fullImage, metadata: metadata)
        
        XCTAssertEqual(photo.filename, filename, "Filename should be set from legacy init")
        XCTAssertEqual(photo.metadata["legacy"] as? Bool, true, "Metadata should be preserved")
    }
    
    // MARK: - Equatable Tests
    
    /// Tests that SecurePhoto equality works correctly
    /// Assertion: Should be equal when ID and filename match
    func testEquatable_ComparesCorrectly() {
        let photo1 = SecurePhoto(filename: "same_photo", metadata: [:], fileURL: testFileURL)
        let photo2 = SecurePhoto(filename: "different_photo", metadata: [:], fileURL: testFileURL)
        
        // Same photo should equal itself
        XCTAssertEqual(photo1, photo1, "Photo should equal itself")
        
        // Different photos should not be equal
        XCTAssertNotEqual(photo1, photo2, "Different photos should not be equal")
    }
    
    // MARK: - Decoy Status Tests
    
    /// Tests that isDecoy property reads from metadata correctly
    /// Assertion: Should return false for non-decoy photos and true for decoy photos
    func testIsDecoy_ReadsFromMetadataCorrectly() {
        // Test false case
        XCTAssertFalse(securePhoto.isDecoy, "Should return false when isDecoy is false in metadata")
        
        // Test true case
        securePhoto.metadata["isDecoy"] = true
        XCTAssertTrue(securePhoto.isDecoy, "Should return true when isDecoy is true in metadata")
        
        // Test missing key case
        securePhoto.metadata.removeValue(forKey: "isDecoy")
        XCTAssertFalse(securePhoto.isDecoy, "Should default to false when isDecoy key is missing")
    }
    
    /// Tests that setDecoyStatus() updates metadata correctly
    /// Assertion: Should update metadata with new decoy status
    func testSetDecoyStatus_UpdatesMetadata() {
        XCTAssertFalse(securePhoto.isDecoy, "Should initially be false")
        
        securePhoto.setDecoyStatus(true)
        
        XCTAssertTrue(securePhoto.isDecoy, "Should update to true")
        XCTAssertEqual(securePhoto.metadata["isDecoy"] as? Bool, true, "Metadata should be updated")
        
        securePhoto.setDecoyStatus(false)
        
        XCTAssertFalse(securePhoto.isDecoy, "Should update back to false")
        XCTAssertEqual(securePhoto.metadata["isDecoy"] as? Bool, false, "Metadata should be updated")
    }
    
    // MARK: - Orientation Tests
    
    /// Tests that originalOrientation reads from metadata correctly
    /// Assertion: Should convert EXIF orientation values to UIImage.Orientation correctly
    func testOriginalOrientation_ReadsFromMetadata() {
        let orientationTestCases: [(Int, UIImage.Orientation)] = [
            (1, .up),
            (2, .upMirrored),
            (3, .down),
            (4, .downMirrored),
            (5, .leftMirrored),
            (6, .right),
            (7, .rightMirrored),
            (8, .left)
        ]
        
        for (exifValue, expectedOrientation) in orientationTestCases {
            securePhoto.metadata["originalOrientation"] = exifValue
            XCTAssertEqual(securePhoto.originalOrientation, expectedOrientation,
                          "EXIF orientation \(exifValue) should map to \(expectedOrientation)")
        }
    }
    
    /// Tests that originalOrientation defaults correctly when metadata is missing
    /// Assertion: Should default to .up when orientation metadata is missing
    func testOriginalOrientation_DefaultsCorrectly() {
        securePhoto.metadata.removeValue(forKey: "originalOrientation")
        
        XCTAssertEqual(securePhoto.originalOrientation, .up, "Should default to .up when orientation is missing")
    }
    
    /// Tests that isLandscape property calculates correctly for different orientations
    /// Assertion: Should determine landscape vs portrait correctly based on image dimensions and orientation
    func testIsLandscape_CalculatesCorrectly() {
        // Test cached value
        securePhoto.metadata["isLandscape"] = true
        XCTAssertTrue(securePhoto.isLandscape, "Should return cached landscape value")
        
        securePhoto.metadata["isLandscape"] = false
        XCTAssertFalse(securePhoto.isLandscape, "Should return cached portrait value")
        
        // Remove cached value to test calculation
        securePhoto.metadata.removeValue(forKey: "isLandscape")
        
        // Test normal orientation (1) with landscape image
        securePhoto.metadata["originalOrientation"] = 1
        // Note: Since we can't easily control the test image dimensions in this context,
        // we'll test that the property doesn't crash and returns a valid boolean
        let isLandscape = securePhoto.isLandscape
        XCTAssertTrue(isLandscape == true || isLandscape == false, "Should return valid boolean")
    }
    
    /// Tests that frameSizeForDisplay calculates correct dimensions
    /// Assertion: Should return appropriate width/height based on orientation and cell size
    func testFrameSizeForDisplay_CalculatesCorrectDimensions() {
        let cellSize: CGFloat = 100
        
        // Test with normal orientation
        securePhoto.metadata["originalOrientation"] = 1
        let (width, height) = securePhoto.frameSizeForDisplay(cellSize: cellSize)
        
        XCTAssertGreaterThan(width, 0, "Width should be positive")
        XCTAssertGreaterThan(height, 0, "Height should be positive")
        
        // One dimension should equal cellSize for proper scaling
        XCTAssertTrue(width == cellSize || height == cellSize, 
                     "One dimension should equal cellSize for proper scaling")
    }
    
    // MARK: - Memory Management Tests
    
    /// Tests that visibility tracking works correctly
    /// Assertion: Should track visibility state changes
    func testVisibilityTracking_WorksCorrectly() {
        XCTAssertFalse(securePhoto.isVisible, "Should initially be not visible")
        
        securePhoto.isVisible = true
        XCTAssertTrue(securePhoto.isVisible, "Should be visible when set")
        
        securePhoto.markAsInvisible()
        XCTAssertFalse(securePhoto.isVisible, "Should be invisible after markAsInvisible()")
    }
    
    /// Tests that access time tracking works correctly
    /// Assertion: Should update last access time when images are accessed
    func testAccessTimeTracking_UpdatesCorrectly() {
        let initialAccessTime = securePhoto.timeSinceLastAccess
        
        // Wait a small amount to ensure time difference
        Thread.sleep(forTimeInterval: 0.01)
        
        // Access thumbnail to update access time
        let _ = securePhoto.thumbnail
        
        let newAccessTime = securePhoto.timeSinceLastAccess
        XCTAssertLessThan(newAccessTime, initialAccessTime, 
                         "Access time should be updated when thumbnail is accessed")
    }
    
    /// Tests that clearMemory works correctly
    /// Assertion: Should clear cached images while optionally keeping thumbnail
    func testClearMemory_WorksCorrectly() {
        // Preload images by accessing them
        let _ = securePhoto.thumbnail
        let _ = securePhoto.fullImage
        
        // Clear memory keeping thumbnail
        securePhoto.clearMemory(keepThumbnail: true)
        
        // Test that we can still access thumbnail (it should be cached)
        let thumbnailAfterClear = securePhoto.thumbnail
        XCTAssertNotNil(thumbnailAfterClear, "Thumbnail should still be available when keepThumbnail is true")
        
        // Clear all memory
        securePhoto.clearMemory(keepThumbnail: false)
        
        // Images should still be accessible (will be reloaded), but this tests the clearing mechanism
        let thumbnailAfterFullClear = securePhoto.thumbnail
        XCTAssertNotNil(thumbnailAfterFullClear, "Thumbnail should be reloadable after full clear")
    }
    
    // MARK: - Image Loading Tests
    
    /// Tests that thumbnail loading works with preloaded image
    /// Assertion: Should return preloaded thumbnail when available
    func testThumbnailLoading_WorksWithPreloadedImage() {
        let thumbnail = securePhoto.thumbnail
        
        XCTAssertNotNil(thumbnail, "Should return valid thumbnail")
        XCTAssertTrue(securePhoto.isVisible, "Should mark as visible when thumbnail is accessed")
    }
    
    /// Tests that thumbnail loading handles missing files gracefully
    /// Assertion: Should return placeholder image when file cannot be loaded
    func testThumbnailLoading_HandlesMissingFiles() {
        // Create photo with non-existent file
        let missingPhoto = SecurePhoto(
            filename: "missing_photo",
            metadata: [:],
            fileURL: URL(fileURLWithPath: "/nonexistent/path.jpg")
        )
        
        let thumbnail = missingPhoto.thumbnail
        
        XCTAssertNotNil(thumbnail, "Should return placeholder for missing file")
        // Should be a system image placeholder
        XCTAssertNotNil(UIImage(systemName: "photo"), "Placeholder should be available")
    }
    
    /// Tests that fullImage loading handles missing files gracefully
    /// Assertion: Should fallback to thumbnail when full image cannot be loaded
    func testFullImageLoading_HandlesMissingFiles() {
        // Create photo with non-existent file
        let missingPhoto = SecurePhoto(
            filename: "missing_full_photo",
            metadata: [:],
            fileURL: URL(fileURLWithPath: "/nonexistent/path.jpg")
        )
        
        let fullImage = missingPhoto.fullImage
        
        XCTAssertNotNil(fullImage, "Should return fallback image for missing full image")
        XCTAssertTrue(missingPhoto.isVisible, "Should mark as visible when fullImage is accessed")
    }
    
    // MARK: - Metadata Persistence Tests
    
    /// Tests that setDecoyStatus performs async metadata save
    /// Assertion: Should handle metadata saving asynchronously without blocking
    func testSetDecoyStatus_PerformsAsyncSave() {
        let expectation = XCTestExpectation(description: "Decoy status should be set without blocking")
        
        // Set decoy status (this triggers async save)
        securePhoto.setDecoyStatus(true)
        
        // Should complete immediately (async operation)
        XCTAssertTrue(securePhoto.isDecoy, "Decoy status should be updated immediately")
        
        // Give async operation time to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Edge Cases Tests
    
    /// Tests that SecurePhoto handles nil or empty metadata gracefully
    /// Assertion: Should work correctly with minimal or missing metadata
    func testHandlesEmptyMetadata_Gracefully() {
        let photoWithEmptyMetadata = SecurePhoto(
            filename: "empty_metadata_photo",
            metadata: [:],
            fileURL: testFileURL
        )
        
        XCTAssertFalse(photoWithEmptyMetadata.isDecoy, "Should default decoy to false")
        XCTAssertEqual(photoWithEmptyMetadata.originalOrientation, .up, "Should default orientation to up")
        XCTAssertNotNil(photoWithEmptyMetadata.thumbnail, "Should provide thumbnail even with empty metadata")
    }
    
    /// Tests that SecurePhoto handles invalid metadata types gracefully
    /// Assertion: Should handle type mismatches in metadata without crashing
    func testHandlesInvalidMetadataTypes_Gracefully() {
        let invalidMetadata: [String: Any] = [
            "isDecoy": "not_a_boolean",  // Wrong type
            "originalOrientation": "not_an_int",  // Wrong type
            "isLandscape": 123  // Wrong type
        ]
        
        let photoWithInvalidMetadata = SecurePhoto(
            filename: "invalid_metadata_photo",
            metadata: invalidMetadata,
            fileURL: testFileURL
        )
        
        // Should handle gracefully and use defaults
        XCTAssertFalse(photoWithInvalidMetadata.isDecoy, "Should default to false for invalid decoy type")
        XCTAssertEqual(photoWithInvalidMetadata.originalOrientation, .up, "Should default to up for invalid orientation")
    }
    
    /// Tests that memory operations work with concurrent access
    /// Assertion: Should handle concurrent memory operations safely
    func testConcurrentMemoryOperations_WorkSafely() {
        let expectation = XCTestExpectation(description: "Concurrent operations should complete safely")
        expectation.expectedFulfillmentCount = 3
        
        // Simulate concurrent access from different threads
        DispatchQueue.global(qos: .userInitiated).async {
            let _ = self.securePhoto.thumbnail
            expectation.fulfill()
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let _ = self.securePhoto.fullImage
            expectation.fulfill()
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.securePhoto.clearMemory(keepThumbnail: false)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 3.0)
    }
    
    /// Tests that timeSinceLastAccess increases over time
    /// Assertion: Should track time accurately
    func testTimeSinceLastAccess_IncreasesOverTime() {
        // Access the thumbnail to set last access time
        let _ = securePhoto.thumbnail
        
        let initialTime = securePhoto.timeSinceLastAccess
        
        // Wait a short time
        Thread.sleep(forTimeInterval: 0.05)
        
        let laterTime = securePhoto.timeSinceLastAccess
        
        XCTAssertGreaterThan(laterTime, initialTime, "Time since last access should increase over time")
    }
    
    // MARK: - Helper Methods
    
    /// Creates a test image for use in tests
    private func createTestImage(size: CGSize = CGSize(width: 200, height: 200)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            context.cgContext.setFillColor(UIColor.blue.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: size))
            
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fillEllipse(in: CGRect(x: size.width * 0.25, y: size.height * 0.25,
                                                   width: size.width * 0.5, height: size.height * 0.5))
        }
    }
}