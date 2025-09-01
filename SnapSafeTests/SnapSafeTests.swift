//
//  SnapSafeTests.swift
//  SnapSafeTests
//
//  Created by Bill Booth on 5/2/25.
//

@testable import SnapSafe
import XCTest

/// Basic test class to verify test target is working
class SnapSafeTests: XCTestCase {
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        XCTAssertTrue(true, "Basic test should pass")
    }

    func testThumbnailAspectRatioPreservation() throws {
        // Test that thumbnails preserve aspect ratio for various image dimensions
        let testCases = [
            (width: 800, height: 600), // 4:3 landscape
            (width: 600, height: 800), // 3:4 portrait  
            (width: 1000, height: 1000), // 1:1 square
            (width: 1920, height: 1080), // 16:9 widescreen
            (width: 300, height: 1200), // 1:4 tall portrait
        ]
        
        for testCase in testCases {
            // Create a test UIImage with specific dimensions
            let testImage = createTestImage(width: testCase.width, height: testCase.height)
            let originalAspectRatio = Double(testCase.width) / Double(testCase.height)
            
            // Create metadata for the photo
            let metadata = PhotoMetadata(
                creationDate: Date(),
                location: nil,
                cameraModel: "Test Camera",
                isDecoy: false,
                faces: []
            )
            
            // Create SecurePhoto with test data
            let imageData = testImage.jpegData(compressionQuality: 1.0) ?? Data()
            let securePhoto = SecurePhoto(id: "test-\(testCase.width)x\(testCase.height)", rawPhotoData: imageData, metadata: metadata)
            
            // Get the thumbnail
            let thumbnail = securePhoto.thumbnail
            let thumbnailAspectRatio = Double(thumbnail.size.width) / Double(thumbnail.size.height)
            
            // Verify the aspect ratio is preserved (within a small tolerance for floating point comparison)
            let tolerance = 0.01
            XCTAssertEqual(thumbnailAspectRatio, originalAspectRatio, accuracy: tolerance, 
                          "Thumbnail aspect ratio \(thumbnailAspectRatio) should match original \(originalAspectRatio) for \(testCase.width)x\(testCase.height) image")
            
            // Verify thumbnail is properly scaled (should fit within 200x200)
            XCTAssertLessThanOrEqual(thumbnail.size.width, 200, "Thumbnail width should not exceed 200px for \(testCase.width)x\(testCase.height) image")
            XCTAssertLessThanOrEqual(thumbnail.size.height, 200, "Thumbnail height should not exceed 200px for \(testCase.width)x\(testCase.height) image")
            
            // At least one dimension should be at or near the maximum (200px)
            let maxDimension = max(thumbnail.size.width, thumbnail.size.height)
            XCTAssertGreaterThanOrEqual(maxDimension, 199, "At least one thumbnail dimension should be near maximum (200px) for \(testCase.width)x\(testCase.height) image")
        }
    }
    
    private func createTestImage(width: Int, height: Int) -> UIImage {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            // Fill with blue color to make it a visible test image
            UIColor.blue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            // Add a white border to make aspect ratio distortion more obvious
            UIColor.white.setStroke()
            context.stroke(CGRect(x: 5, y: 5, width: size.width - 10, height: size.height - 10), width: 10)
        }
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        measure {
            // Put the code you want to measure the time of here.
            let _ = Array(0 ... 1000).map { $0 * 2 }
        }
    }
}
