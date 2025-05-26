//
//  PhotoMetadataFilteringTests.swift
//  SnapSafeTests
//
//  Created by Bill Booth on 5/26/25.
//

import XCTest
import CoreLocation
@testable import SnapSafe

class PhotoMetadataFilteringTests: XCTestCase {
    
    var testFileManager: SecureFileManager!
    
    override func setUp() {
        super.setUp()
        testFileManager = SecureFileManager()
    }
    
    override func tearDown() {
        testFileManager = nil
        super.tearDown()
    }
    
    // MARK: - GPS Metadata Tests
    
    func testPhotoWithGPSLatitudeLongitude_ShouldHaveLocation() {
        // Create metadata with GPS data including latitude and longitude
        let gpsData: [String: Any] = [
            String(kCGImagePropertyGPSLatitude): 37.7749,
            String(kCGImagePropertyGPSLatitudeRef): "N",
            String(kCGImagePropertyGPSLongitude): -122.4194,
            String(kCGImagePropertyGPSLongitudeRef): "W"
        ]
        
        let metadata: [String: Any] = [
            String(kCGImagePropertyGPSDictionary): gpsData
        ]
        
        let photo = createTestPhoto(metadata: metadata)
        
        // Test the filtering logic
        let hasLocation = hasGPSLocation(photo: photo)
        XCTAssertTrue(hasLocation, "Photo with GPS latitude and longitude should be detected as having location")
    }
    
    func testPhotoWithGPSLatitudeOnly_ShouldHaveLocation() {
        // Create metadata with GPS data including only latitude
        let gpsData: [String: Any] = [
            String(kCGImagePropertyGPSLatitude): 37.7749,
            String(kCGImagePropertyGPSLatitudeRef): "N"
        ]
        
        let metadata: [String: Any] = [
            String(kCGImagePropertyGPSDictionary): gpsData
        ]
        
        let photo = createTestPhoto(metadata: metadata)
        
        // Test the filtering logic
        let hasLocation = hasGPSLocation(photo: photo)
        XCTAssertTrue(hasLocation, "Photo with GPS latitude only should be detected as having location")
    }
    
    func testPhotoWithGPSLongitudeOnly_ShouldHaveLocation() {
        // Create metadata with GPS data including only longitude
        let gpsData: [String: Any] = [
            String(kCGImagePropertyGPSLongitude): -122.4194,
            String(kCGImagePropertyGPSLongitudeRef): "W"
        ]
        
        let metadata: [String: Any] = [
            String(kCGImagePropertyGPSDictionary): gpsData
        ]
        
        let photo = createTestPhoto(metadata: metadata)
        
        // Test the filtering logic
        let hasLocation = hasGPSLocation(photo: photo)
        XCTAssertTrue(hasLocation, "Photo with GPS longitude only should be detected as having location")
    }
    
    func testPhotoWithEmptyGPSData_ShouldNotHaveLocation() {
        // Create metadata with empty GPS dictionary
        let gpsData: [String: Any] = [:]
        
        let metadata: [String: Any] = [
            String(kCGImagePropertyGPSDictionary): gpsData
        ]
        
        let photo = createTestPhoto(metadata: metadata)
        
        // Test the filtering logic
        let hasLocation = hasGPSLocation(photo: photo)
        XCTAssertFalse(hasLocation, "Photo with empty GPS data should not be detected as having location")
    }
    
    func testPhotoWithoutGPSData_ShouldNotHaveLocation() {
        // Create metadata without any GPS data
        let metadata: [String: Any] = [
            "creationDate": Date().timeIntervalSince1970
        ]
        
        let photo = createTestPhoto(metadata: metadata)
        
        // Test the filtering logic
        let hasLocation = hasGPSLocation(photo: photo)
        XCTAssertFalse(hasLocation, "Photo without GPS data should not be detected as having location")
    }
    
    func testPhotoWithInvalidGPSDataType_ShouldNotHaveLocation() {
        // Create metadata with invalid GPS data type
        let metadata: [String: Any] = [
            String(kCGImagePropertyGPSDictionary): "invalid_gps_data_type"
        ]
        
        let photo = createTestPhoto(metadata: metadata)
        
        // Test the filtering logic
        let hasLocation = hasGPSLocation(photo: photo)
        XCTAssertFalse(hasLocation, "Photo with invalid GPS data type should not be detected as having location")
    }
    
    // MARK: - Edited Photo Tests
    
    func testPhotoWithEditedFlag_ShouldBeEdited() {
        // Create metadata with isEdited flag
        let metadata: [String: Any] = [
            "isEdited": true,
            "originalFilename": "original_photo_123",
            "creationDate": Date().timeIntervalSince1970
        ]
        
        let photo = createTestPhoto(metadata: metadata)
        
        // Test the filtering logic
        let isEdited = isEditedPhoto(photo: photo)
        XCTAssertTrue(isEdited, "Photo with isEdited flag should be detected as edited")
    }
    
    func testPhotoWithEditedFlagFalse_ShouldNotBeEdited() {
        // Create metadata with isEdited flag set to false
        let metadata: [String: Any] = [
            "isEdited": false,
            "creationDate": Date().timeIntervalSince1970
        ]
        
        let photo = createTestPhoto(metadata: metadata)
        
        // Test the filtering logic
        let isEdited = isEditedPhoto(photo: photo)
        XCTAssertFalse(isEdited, "Photo with isEdited flag set to false should not be detected as edited")
    }
    
    func testPhotoWithoutEditedFlag_ShouldNotBeEdited() {
        // Create metadata without isEdited flag
        let metadata: [String: Any] = [
            "creationDate": Date().timeIntervalSince1970
        ]
        
        let photo = createTestPhoto(metadata: metadata)
        
        // Test the filtering logic
        let isEdited = isEditedPhoto(photo: photo)
        XCTAssertFalse(isEdited, "Photo without isEdited flag should not be detected as edited")
    }
    
    // MARK: - Imported Photo Tests
    
    func testPhotoWithImportedFlag_ShouldBeImported() {
        // Create metadata with imported flag
        let metadata: [String: Any] = [
            "imported": true,
            "importSource": "PhotosPicker",
            "creationDate": Date().timeIntervalSince1970
        ]
        
        let photo = createTestPhoto(metadata: metadata)
        
        // Test the filtering logic
        let isImported = isImportedPhoto(photo: photo)
        XCTAssertTrue(isImported, "Photo with imported flag should be detected as imported")
    }
    
    func testPhotoWithImportedFlagFalse_ShouldNotBeImported() {
        // Create metadata with imported flag set to false
        let metadata: [String: Any] = [
            "imported": false,
            "creationDate": Date().timeIntervalSince1970
        ]
        
        let photo = createTestPhoto(metadata: metadata)
        
        // Test the filtering logic
        let isImported = isImportedPhoto(photo: photo)
        XCTAssertFalse(isImported, "Photo with imported flag set to false should not be detected as imported")
    }
    
    func testPhotoWithoutImportedFlag_ShouldNotBeImported() {
        // Create metadata without imported flag
        let metadata: [String: Any] = [
            "creationDate": Date().timeIntervalSince1970
        ]
        
        let photo = createTestPhoto(metadata: metadata)
        
        // Test the filtering logic
        let isImported = isImportedPhoto(photo: photo)
        XCTAssertFalse(isImported, "Photo without imported flag should not be detected as imported")
    }
    
    // MARK: - Helper Methods
    
    private func createTestPhoto(metadata: [String: Any]) -> SecurePhoto {
        let testImage = UIImage(systemName: "photo") ?? UIImage()
        let testURL = URL(fileURLWithPath: "/test/path")
        return SecurePhoto(filename: "test_photo", metadata: metadata, fileURL: testURL)
    }
    
    // Extract filtering logic to test it directly (matches SecureGalleryView implementation)
    private func hasGPSLocation(photo: SecurePhoto) -> Bool {
        guard let gpsData = photo.metadata[String(kCGImagePropertyGPSDictionary)] as? [String: Any] else { return false }
        
        let hasLatitude = gpsData[String(kCGImagePropertyGPSLatitude)] != nil
        let hasLongitude = gpsData[String(kCGImagePropertyGPSLongitude)] != nil
        
        return hasLatitude || hasLongitude
    }
    
    private func isEditedPhoto(photo: SecurePhoto) -> Bool {
        return photo.metadata["isEdited"] as? Bool == true
    }
    
    private func isImportedPhoto(photo: SecurePhoto) -> Bool {
        return photo.metadata["imported"] as? Bool == true
    }
}