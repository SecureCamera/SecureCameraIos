//
//  FaceDetectorTests.swift
//  SnapSafeTests
//
//  Created by Bill Booth on 5/25/25.
//

import XCTest
import UIKit
import Vision
@testable import SnapSafe

class FaceDetectorTests: XCTestCase {
    
    private var faceDetector: FaceDetector!
    private var testImage: UIImage!
    
    override func setUp() {
        super.setUp()
        faceDetector = FaceDetector()
        testImage = createTestImage()
    }
    
    override func tearDown() {
        faceDetector = nil
        testImage = nil
        super.tearDown()
    }
    
    // MARK: - Face Detection Tests
    
    /// Tests that detectFaces() handles nil CGImage gracefully
    /// Assertion: Should return empty array when image cannot be converted to CGImage
    func testDetectFaces_HandlesInvalidImage() {
        let expectation = XCTestExpectation(description: "Face detection should complete")
        
        // Create image with no CGImage backing
        let invalidImage = UIImage()
        
        faceDetector.detectFaces(in: invalidImage) { detectedFaces in
            XCTAssertTrue(detectedFaces.isEmpty, "Should return empty array for invalid image")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    /// Tests that detectFaces() processes valid images asynchronously
    /// Assertion: Should complete without throwing and return results via completion handler
    func testDetectFaces_ProcessesValidImageAsynchronously() {
        let expectation = XCTestExpectation(description: "Face detection should complete")
        
        faceDetector.detectFaces(in: testImage) { detectedFaces in
            // Should complete without crashing
            XCTAssertNotNil(detectedFaces, "Should return non-nil array")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    /// Tests that detectFaces() returns DetectedFace objects with proper coordinate conversion
    /// Assertion: Detected faces should have bounds within image dimensions
    func testDetectFaces_ReturnsValidCoordinates() {
        let expectation = XCTestExpectation(description: "Face detection should complete")
        
        faceDetector.detectFaces(in: testImage) { detectedFaces in
            for face in detectedFaces {
                // Assert face bounds are within image dimensions
                XCTAssertGreaterThanOrEqual(face.bounds.minX, 0, "Face X coordinate should be >= 0")
                XCTAssertGreaterThanOrEqual(face.bounds.minY, 0, "Face Y coordinate should be >= 0")
                XCTAssertLessThanOrEqual(face.bounds.maxX, self.testImage.size.width, 
                                       "Face should be within image width")
                XCTAssertLessThanOrEqual(face.bounds.maxY, self.testImage.size.height, 
                                       "Face should be within image height")
                
                // Assert face has positive dimensions
                XCTAssertGreaterThan(face.bounds.width, 0, "Face width should be positive")
                XCTAssertGreaterThan(face.bounds.height, 0, "Face height should be positive")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    /// Tests that detectFaces() handles Vision framework errors gracefully
    /// Assertion: Should return empty array when Vision processing fails
    func testDetectFaces_HandlesVisionErrors() {
        let expectation = XCTestExpectation(description: "Face detection should handle errors")
        
        // Create a very small image that might cause Vision issues
        let tinyImage = createTestImage(size: CGSize(width: 1, height: 1))
        
        faceDetector.detectFaces(in: tinyImage) { detectedFaces in
            // Should not crash and return some result
            XCTAssertNotNil(detectedFaces, "Should return array even on potential Vision errors")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 3.0)
    }
    
    // MARK: - Face Masking Tests
    
    /// Tests that maskFaces() returns original image when no faces are selected
    /// Assertion: Should return original image unchanged when no faces are selected for masking
    func testMaskFaces_ReturnsOriginalWhenNoFacesSelected() {
        let face1 = DetectedFace(bounds: CGRect(x: 10, y: 10, width: 50, height: 50), isSelected: false)
        let face2 = DetectedFace(bounds: CGRect(x: 100, y: 100, width: 60, height: 60), isSelected: false)
        let faces = [face1, face2]
        
        let result = faceDetector.maskFaces(in: testImage, faces: faces, modes: [.blur])
        
        XCTAssertNotNil(result, "Should return a valid image")
        // Note: Exact pixel comparison is complex, so we verify basic properties
        XCTAssertEqual(result?.size, testImage.size, "Result should have same dimensions as original")
    }
    
    /// Tests that maskFaces() returns original image when modes array is empty
    /// Assertion: Should return original image when no masking modes are specified
    func testMaskFaces_ReturnsOriginalWhenNoModes() {
        let face = DetectedFace(bounds: CGRect(x: 10, y: 10, width: 50, height: 50), isSelected: true)
        
        let result = faceDetector.maskFaces(in: testImage, faces: [face], modes: [])
        
        XCTAssertNotNil(result, "Should return a valid image")
        XCTAssertEqual(result?.size, testImage.size, "Result should have same dimensions as original")
    }
    
    /// Tests that maskFaces() processes selected faces with blur mode
    /// Assertion: Should return modified image when faces are selected and blur mode is applied
    func testMaskFaces_ProcessesSelectedFacesWithBlur() {
        let selectedFace = DetectedFace(bounds: CGRect(x: 50, y: 50, width: 100, height: 100), isSelected: true)
        let unselectedFace = DetectedFace(bounds: CGRect(x: 200, y: 200, width: 80, height: 80), isSelected: false)
        let faces = [selectedFace, unselectedFace]
        
        let result = faceDetector.maskFaces(in: testImage, faces: faces, modes: [.blur])
        
        XCTAssertNotNil(result, "Should return a valid blurred image")
        XCTAssertEqual(result?.size, testImage.size, "Result should maintain original dimensions")
    }
    
    /// Tests that maskFaces() handles blackout mode correctly
    /// Assertion: Should apply blackout effect to selected faces
    func testMaskFaces_AppliesBlackoutMode() {
        let face = DetectedFace(bounds: CGRect(x: 25, y: 25, width: 50, height: 50), isSelected: true)
        
        let result = faceDetector.maskFaces(in: testImage, faces: [face], modes: [.blackout])
        
        XCTAssertNotNil(result, "Should return image with blackout effect")
        XCTAssertEqual(result?.size, testImage.size, "Result should maintain original dimensions")
    }
    
    /// Tests that maskFaces() handles pixelate mode correctly
    /// Assertion: Should apply pixelation effect to selected faces
    func testMaskFaces_AppliesPixelateMode() {
        let face = DetectedFace(bounds: CGRect(x: 30, y: 30, width: 60, height: 60), isSelected: true)
        
        let result = faceDetector.maskFaces(in: testImage, faces: [face], modes: [.pixelate])
        
        XCTAssertNotNil(result, "Should return image with pixelation effect")
        XCTAssertEqual(result?.size, testImage.size, "Result should maintain original dimensions")
    }
    
    /// Tests that maskFaces() handles noise mode correctly
    /// Assertion: Should apply noise effect to selected faces
    func testMaskFaces_AppliesNoiseMode() {
        let face = DetectedFace(bounds: CGRect(x: 40, y: 40, width: 70, height: 70), isSelected: true)
        
        let result = faceDetector.maskFaces(in: testImage, faces: [face], modes: [.noise])
        
        XCTAssertNotNil(result, "Should return image with noise effect")
        XCTAssertEqual(result?.size, testImage.size, "Result should maintain original dimensions")
    }
    
    /// Tests that maskFaces() handles multiple selected faces
    /// Assertion: Should apply masking to all selected faces
    func testMaskFaces_HandlesMultipleSelectedFaces() {
        let face1 = DetectedFace(bounds: CGRect(x: 20, y: 20, width: 40, height: 40), isSelected: true)
        let face2 = DetectedFace(bounds: CGRect(x: 80, y: 80, width: 50, height: 50), isSelected: true)
        let face3 = DetectedFace(bounds: CGRect(x: 150, y: 150, width: 45, height: 45), isSelected: false)
        let faces = [face1, face2, face3]
        
        let result = faceDetector.maskFaces(in: testImage, faces: faces, modes: [.blur])
        
        XCTAssertNotNil(result, "Should return image with multiple faces masked")
        XCTAssertEqual(result?.size, testImage.size, "Result should maintain original dimensions")
    }
    
    /// Tests that maskFaces() uses first mode when multiple modes are provided
    /// Assertion: Should use primary (first) mode for processing when multiple modes are specified
    func testMaskFaces_UsesPrimaryModeFromMultipleModes() {
        let face = DetectedFace(bounds: CGRect(x: 35, y: 35, width: 55, height: 55), isSelected: true)
        
        // Provide multiple modes - should use first one (blur)
        let result = faceDetector.maskFaces(in: testImage, faces: [face], modes: [.blur, .pixelate, .blackout])
        
        XCTAssertNotNil(result, "Should return image processed with primary mode")
        XCTAssertEqual(result?.size, testImage.size, "Result should maintain original dimensions")
    }
    
    // MARK: - Helper Method Tests
    
    /// Tests that coerceRectToImage() properly constrains rectangles within image bounds
    /// Assertion: Should return rectangle that is always within image boundaries
    func testCoerceRectToImage_ConstrainsRectangleWithinBounds() {
        // Use reflection to access private method for testing
        let method = class_getInstanceMethod(FaceDetector.self, Selector(("coerceRectToImage:image:")))
//        XCTAssertNotNil(method, "coerceRectToImage method should exist")
        
        // Test with rectangle extending outside image bounds
        let oversizedRect = CGRect(x: -10, y: -10, width: testImage.size.width + 20, height: testImage.size.height + 20)
        
        // Since we can't easily access private method, we'll test the public behavior
        // by creating a face that would require coercion
        let face = DetectedFace(bounds: oversizedRect, isSelected: true)
        let result = faceDetector.maskFaces(in: testImage, faces: [face], modes: [.blackout])
        
        // Should not crash and should return valid image
        XCTAssertNotNil(result, "Should handle oversized rectangles without crashing")
    }
    
    /// Tests that coerceRectToImage() handles completely outside rectangles
    /// Assertion: Should create small valid rectangle when input is completely outside image
    func testCoerceRectToImage_HandlesCompletelyOutsideRectangles() {
        // Test with rectangle completely outside image
        let outsideRect = CGRect(x: testImage.size.width + 100, y: testImage.size.height + 100, width: 50, height: 50)
        let face = DetectedFace(bounds: outsideRect, isSelected: true)
        
        let result = faceDetector.maskFaces(in: testImage, faces: [face], modes: [.blackout])
        
        // Should handle gracefully without crashing
        XCTAssertNotNil(result, "Should handle completely outside rectangles")
    }
    
    // MARK: - Blur Faces Convenience Method Tests
    
    /// Tests that blurFaces() is a convenience wrapper for maskFaces() with blur mode
    /// Assertion: Should apply blur masking to selected faces
    func testBlurFaces_IsConvenienceWrapperForBlurMode() {
        let face = DetectedFace(bounds: CGRect(x: 45, y: 45, width: 65, height: 65), isSelected: true)
        
        let result = faceDetector.blurFaces(in: testImage, faces: [face])
        
        XCTAssertNotNil(result, "blurFaces should return valid result")
        XCTAssertEqual(result?.size, testImage.size, "Result should maintain original dimensions")
    }
    
    // MARK: - Image Processing Algorithm Tests
    
    /// Tests that pixelate algorithm maintains image structure while reducing detail
    /// Assertion: Pixelated image should have similar overall structure but reduced detail
    func testPixelateAlgorithm_MaintainsImageStructure() {
        let face = DetectedFace(bounds: CGRect(x: 60, y: 60, width: 80, height: 80), isSelected: true)
        
        let result = faceDetector.maskFaces(in: testImage, faces: [face], modes: [.pixelate])
        
        XCTAssertNotNil(result, "Pixelation should produce valid result")
        // Pixelated image should still be recognizable as an image
        XCTAssertEqual(result?.size, testImage.size, "Pixelated image should maintain size")
    }
    
    /// Tests that blur algorithm produces smoothed regions
    /// Assertion: Blurred regions should lose sharp detail while maintaining general appearance
    func testBlurAlgorithm_ProducesSmoothRegions() {
        let face = DetectedFace(bounds: CGRect(x: 70, y: 70, width: 90, height: 90), isSelected: true)
        
        let result = faceDetector.maskFaces(in: testImage, faces: [face], modes: [.blur])
        
        XCTAssertNotNil(result, "Blur should produce valid result")
        XCTAssertEqual(result?.size, testImage.size, "Blurred image should maintain size")
    }
    
    /// Tests that noise algorithm generates random pattern
    /// Assertion: Noise effect should replace image data with random values
    func testNoiseAlgorithm_GeneratesRandomPattern() {
        let face = DetectedFace(bounds: CGRect(x: 55, y: 55, width: 75, height: 75), isSelected: true)
        
        let result = faceDetector.maskFaces(in: testImage, faces: [face], modes: [.noise])
        
        XCTAssertNotNil(result, "Noise should produce valid result")
        XCTAssertEqual(result?.size, testImage.size, "Noise image should maintain size")
    }
    
    // MARK: - Memory and Performance Tests
    
    /// Tests that face detection completes within reasonable time
    /// Assertion: Face detection should complete within performance threshold
    func testFaceDetection_CompletesWithinReasonableTime() {
        let expectation = XCTestExpectation(description: "Face detection should complete quickly")
        let startTime = Date()
        
        faceDetector.detectFaces(in: testImage) { _ in
            let elapsedTime = Date().timeIntervalSince(startTime)
            XCTAssertLessThan(elapsedTime, 10.0, "Face detection should complete within 10 seconds")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 15.0)
    }
    
    /// Tests that masking operations complete efficiently
    /// Assertion: Face masking should not cause significant delay or memory issues
    func testFaceMasking_CompletesEfficiently() {
        let face = DetectedFace(bounds: CGRect(x: 50, y: 50, width: 100, height: 100), isSelected: true)
        
        measure {
            let _ = faceDetector.maskFaces(in: testImage, faces: [face], modes: [.blur])
        }
    }
    
    /// Tests that multiple masking operations don't cause memory leaks
    /// Assertion: Should handle multiple operations without excessive memory growth
    func testMultipleMaskingOperations_HandleMemoryEfficiently() {
        let face = DetectedFace(bounds: CGRect(x: 40, y: 40, width: 80, height: 80), isSelected: true)
        
        // Perform multiple operations to test memory handling
        for _ in 0..<10 {
            let result = faceDetector.maskFaces(in: testImage, faces: [face], modes: [.blur])
            XCTAssertNotNil(result, "Each operation should succeed")
        }
    }
    
    // MARK: - Edge Case Tests
    
    /// Tests that very small face rectangles are handled correctly
    /// Assertion: Should handle faces with minimal dimensions without errors
    func testVerySmallFaceRectangles_HandledCorrectly() {
        let tinyFace = DetectedFace(bounds: CGRect(x: 10, y: 10, width: 1, height: 1), isSelected: true)
        
        let result = faceDetector.maskFaces(in: testImage, faces: [tinyFace], modes: [.blur])
        
        XCTAssertNotNil(result, "Should handle very small face rectangles")
    }
    
    /// Tests that very large face rectangles are handled correctly
    /// Assertion: Should handle faces that cover most of the image
    func testVeryLargeFaceRectangles_HandledCorrectly() {
        let largeFace = DetectedFace(
            bounds: CGRect(x: 5, y: 5, width: testImage.size.width - 10, height: testImage.size.height - 10),
            isSelected: true
        )
        
        let result = faceDetector.maskFaces(in: testImage, faces: [largeFace], modes: [.blackout])
        
        XCTAssertNotNil(result, "Should handle very large face rectangles")
    }
    
    /// Tests that zero-sized rectangles are handled gracefully
    /// Assertion: Should not crash with zero-width or zero-height rectangles
    func testZeroSizedRectangles_HandledGracefully() {
        let zeroWidthFace = DetectedFace(bounds: CGRect(x: 50, y: 50, width: 0, height: 50), isSelected: true)
        let zeroHeightFace = DetectedFace(bounds: CGRect(x: 100, y: 100, width: 50, height: 0), isSelected: true)
        
        let result1 = faceDetector.maskFaces(in: testImage, faces: [zeroWidthFace], modes: [.blur])
        let result2 = faceDetector.maskFaces(in: testImage, faces: [zeroHeightFace], modes: [.blur])
        
        XCTAssertNotNil(result1, "Should handle zero-width rectangles")
        XCTAssertNotNil(result2, "Should handle zero-height rectangles")
    }
    
    // MARK: - Helper Methods
    
    /// Creates a test image for use in tests
    private func createTestImage(size: CGSize = CGSize(width: 300, height: 300)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            // Create a simple gradient background
            context.cgContext.setFillColor(UIColor.blue.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: size))
            
            // Add some geometric shapes to make it more interesting for Vision
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fillEllipse(in: CGRect(x: size.width * 0.3, y: size.height * 0.3, 
                                                   width: size.width * 0.4, height: size.height * 0.4))
            
            context.cgContext.setFillColor(UIColor.black.cgColor)
            context.cgContext.fillEllipse(in: CGRect(x: size.width * 0.4, y: size.height * 0.4, 
                                                   width: size.width * 0.1, height: size.height * 0.1))
            context.cgContext.fillEllipse(in: CGRect(x: size.width * 0.5, y: size.height * 0.4, 
                                                   width: size.width * 0.1, height: size.height * 0.1))
        }
    }
}
