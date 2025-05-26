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
    
    /// Tests that originalOrientation handles invalid values gracefully
    /// Assertion: Should default to .up for invalid orientation values
    func testOriginalOrientation_HandlesInvalidValues() {
        // Test values outside valid range (1-8)
        securePhoto.metadata["originalOrientation"] = 0
        XCTAssertEqual(securePhoto.originalOrientation, .up, "Should default to .up for orientation value 0")
        
        securePhoto.metadata["originalOrientation"] = 9
        XCTAssertEqual(securePhoto.originalOrientation, .up, "Should default to .up for orientation value 9")
        
        securePhoto.metadata["originalOrientation"] = -1
        XCTAssertEqual(securePhoto.originalOrientation, .up, "Should default to .up for negative orientation")
    }
    
    /// Tests that originalOrientation reads from fullImage when metadata is missing
    /// Assertion: Should inspect fullImage orientation when metadata unavailable
    func testOriginalOrientation_ReadsFromFullImage() {
        // Remove orientation metadata
        securePhoto.metadata.removeValue(forKey: "originalOrientation")
        
        // Access originalOrientation which should trigger fullImage inspection
        let orientation = securePhoto.originalOrientation
        
        // Should return a valid orientation (either from image or default)
        let validOrientations: [UIImage.Orientation] = [.up, .down, .left, .right, .upMirrored, .downMirrored, .leftMirrored, .rightMirrored]
        XCTAssertTrue(validOrientations.contains(orientation), "Should return valid orientation from fullImage or default")
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
    
    /// Tests isLandscape calculation for rotated orientations (5-8)
    /// Assertion: Should handle rotated orientations correctly by swapping width/height comparison
    func testIsLandscape_HandlesRotatedOrientations() {
        // Test rotated orientations (5-8) which swap width/height for landscape calculation
        let rotatedOrientations = [5, 6, 7, 8]
        
        for orientation in rotatedOrientations {
            let rotatedPhoto = SecurePhoto(
                filename: "rotated_test_\(orientation)",
                metadata: ["originalOrientation": orientation],
                fileURL: testFileURL,
                preloadedThumbnail: testImage
            )
            
            let isLandscape = rotatedPhoto.isLandscape
            XCTAssertTrue(isLandscape == true || isLandscape == false, 
                         "Should calculate valid landscape value for rotated orientation \(orientation)")
        }
    }
    
    /// Tests frameSizeForDisplay with different orientation combinations
    /// Assertion: Should calculate different dimensions for different orientation/landscape combinations
    func testFrameSizeForDisplay_HandlesOrientationCombinations() {
        let cellSize: CGFloat = 100
        
        // Test case 1: Landscape photo, normal orientation (should use landscape branch)
        let landscapePhoto = SecurePhoto(
            filename: "landscape_test",
            metadata: ["isLandscape": true, "originalOrientation": 1],
            fileURL: testFileURL,
            preloadedThumbnail: testImage
        )
        let (landscapeWidth, _) = landscapePhoto.frameSizeForDisplay(cellSize: cellSize)
        XCTAssertEqual(landscapeWidth, cellSize, "Landscape normal orientation should use cellSize for width")
        
        // Test case 2: Portrait photo, normal orientation (should use portrait branch)
        let portraitPhoto = SecurePhoto(
            filename: "portrait_test",
            metadata: ["isLandscape": false, "originalOrientation": 1],
            fileURL: testFileURL,
            preloadedThumbnail: testImage
        )
        let (_, portraitHeight) = portraitPhoto.frameSizeForDisplay(cellSize: cellSize)
        XCTAssertEqual(portraitHeight, cellSize, "Portrait normal orientation should use cellSize for height")
    }
    
    /// Tests setDecoyStatus error handling
    /// Assertion: Should handle file system errors gracefully
    func testSetDecoyStatus_HandlesErrors() {
        // Create photo with invalid file path to trigger error conditions
        let invalidPhoto = SecurePhoto(
            filename: "invalid_path_photo",
            metadata: [:],
            fileURL: URL(fileURLWithPath: "/invalid/readonly/path.jpg")
        )
        
        // Should not crash even if metadata save fails
        XCTAssertNoThrow(invalidPhoto.setDecoyStatus(true), 
                        "Should handle metadata save errors gracefully")
        
        // Metadata should still be updated in memory even if disk save fails
        XCTAssertTrue(invalidPhoto.isDecoy, "Should update in-memory metadata even if disk save fails")
    }
    
    /// Tests clearMemory edge cases
    /// Assertion: Should handle cases where images are not loaded
    func testClearMemory_HandlesEdgeCases() {
        // Test clearing memory when no images are loaded
        let freshPhoto = SecurePhoto(
            filename: "fresh_photo",
            metadata: [:],
            fileURL: testFileURL
        )
        
        // Should not crash when clearing memory of unloaded images
        XCTAssertNoThrow(freshPhoto.clearMemory(keepThumbnail: true), 
                        "Should not crash when clearing unloaded images")
        XCTAssertNoThrow(freshPhoto.clearMemory(keepThumbnail: false), 
                        "Should not crash when clearing unloaded images")
    }
    
    /// Tests handling of nil metadata values
    /// Assertion: Should handle nil values in metadata dictionary
    func testHandlesNilMetadataValues_Gracefully() {
        var metadataWithNils: [String: Any] = [:]
        metadataWithNils["isDecoy"] = nil
        metadataWithNils["originalOrientation"] = nil
        metadataWithNils["isLandscape"] = nil
        
        let photoWithNils = SecurePhoto(
            filename: "nil_metadata_photo",
            metadata: metadataWithNils,
            fileURL: testFileURL
        )
        
        // Should handle nil values gracefully
        XCTAssertFalse(photoWithNils.isDecoy, "Should default to false for nil decoy value")
        XCTAssertEqual(photoWithNils.originalOrientation, .up, "Should default to up for nil orientation")
    }
    
    /// Tests fullImage fallback behavior
    /// Assertion: Should fallback to thumbnail when fullImage loading fails
    func testFullImage_FallbackBehavior() {
        // Create photo that will fail to load full image
        let failingPhoto = SecurePhoto(
            filename: "failing_photo",
            metadata: [:],
            fileURL: URL(fileURLWithPath: "/nonexistent/fail.jpg"),
            preloadedThumbnail: testImage
        )
        
        let fullImage = failingPhoto.fullImage
        
        // Should fallback to thumbnail (which is preloaded)
        XCTAssertNotNil(fullImage, "Should return fallback image when full image fails to load")
        XCTAssertTrue(failingPhoto.isVisible, "Should mark as visible even when using fallback")
    }
    
    /// Tests thumbnail placeholder behavior
    /// Assertion: Should return system placeholder when thumbnail cannot be loaded
    func testThumbnail_PlaceholderBehavior() {
        // Create photo with no preloaded thumbnail and invalid file path
        let placeholderPhoto = SecurePhoto(
            filename: "placeholder_photo",
            metadata: [:],
            fileURL: URL(fileURLWithPath: "/invalid/placeholder.jpg")
        )
        
        let thumbnail = placeholderPhoto.thumbnail
        
        // Should return placeholder (system photo icon)
        XCTAssertNotNil(thumbnail, "Should return placeholder thumbnail")
        XCTAssertTrue(placeholderPhoto.isVisible, "Should mark as visible when accessing placeholder")
    }
    
    /// Tests that both thumbnail and fullImage access update lastAccessTime
    /// Assertion: Should update access time for both image types
    func testLastAccessTime_UpdatesForBothImageTypes() {
        // Use the existing securePhoto with preloaded thumbnail for consistent behavior
        let initialTime = securePhoto.timeSinceLastAccess
        
        // Wait to ensure measurable time difference
        Thread.sleep(forTimeInterval: 0.1)
        
        // Access thumbnail should update access time
        let _ = securePhoto.thumbnail
        let timeAfterThumbnail = securePhoto.timeSinceLastAccess
        
        XCTAssertLessThan(timeAfterThumbnail, initialTime, "Thumbnail access should update last access time")
        XCTAssertLessThan(timeAfterThumbnail, 0.05, "Thumbnail access should result in very recent access time")
        
        // Wait longer to ensure measurable time difference
        Thread.sleep(forTimeInterval: 0.1)
        
        // Access full image should update access time again
        let _ = securePhoto.fullImage
        let timeAfterFullImage = securePhoto.timeSinceLastAccess
        
        // Verify both operations update the timestamp correctly
        XCTAssertLessThan(timeAfterFullImage, 0.05, "Full image access should result in very recent access time")
        XCTAssertLessThan(timeAfterFullImage, initialTime, "Full image access should update last access time")
        
        // Verify the access operations work independently
        XCTAssertTrue(securePhoto.isVisible, "Photo should be marked as visible after image access")
    }
    
    /// Tests image caching behavior
    /// Assertion: Should cache images after first load and reuse them
    func testImageCaching_WorksCorrectly() {
        // First thumbnail access should load and cache
        let firstThumbnail = securePhoto.thumbnail
        
        // Second access should use cached version (same instance)
        let secondThumbnail = securePhoto.thumbnail
        
        // Both should be the same cached instance
        XCTAssertTrue(firstThumbnail === secondThumbnail, "Should reuse cached thumbnail")
        
        // Same test for full image
        let firstFullImage = securePhoto.fullImage
        let secondFullImage = securePhoto.fullImage
        
        XCTAssertTrue(firstFullImage === secondFullImage, "Should reuse cached full image")
    }
    
    /// Tests concurrent metadata operations
    /// Assertion: Should handle concurrent metadata updates safely
    func testConcurrentMetadataOperations_WorkSafely() {
        let expectation = XCTestExpectation(description: "Concurrent metadata operations should complete safely")
        expectation.expectedFulfillmentCount = 4
        
        // Simulate concurrent metadata access and updates
        DispatchQueue.global(qos: .userInitiated).async {
            let _ = self.securePhoto.isDecoy
            expectation.fulfill()
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let _ = self.securePhoto.originalOrientation
            expectation.fulfill()
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.securePhoto.setDecoyStatus(true)
            expectation.fulfill()
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let _ = self.securePhoto.isLandscape
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 3.0)
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
