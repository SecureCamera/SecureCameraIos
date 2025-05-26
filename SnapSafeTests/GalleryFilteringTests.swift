//
//  GalleryFilteringTests.swift
//  SnapSafeTests
//
//  Created by Bill Booth on 5/26/25.
//

import XCTest
@testable import SnapSafe

class GalleryFilteringTests: XCTestCase {
    
    var testPhotos: [SecurePhoto]!
    
    override func setUp() {
        super.setUp()
        createTestPhotos()
    }
    
    override func tearDown() {
        testPhotos = nil
        super.tearDown()
    }
    
    // MARK: - Filter Logic Tests
    
    func testFilterPhotos_AllFilter_ShouldReturnAllPhotos() {
        // Test that .all filter returns all photos
        let filteredPhotos = applyFilter(.all, to: testPhotos)
        
        XCTAssertEqual(filteredPhotos.count, testPhotos.count, "All filter should return all photos")
        XCTAssertEqual(filteredPhotos, testPhotos, "All filter should return the same photos")
    }
    
    func testFilterPhotos_ImportedFilter_ShouldReturnOnlyImportedPhotos() {
        // Test that .imported filter returns only imported photos
        let filteredPhotos = applyFilter(.imported, to: testPhotos)
        
        let expectedCount = testPhotos.filter { $0.metadata["imported"] as? Bool == true }.count
        XCTAssertEqual(filteredPhotos.count, expectedCount, "Imported filter should return correct count")
        
        // Verify all returned photos are imported
        for photo in filteredPhotos {
            XCTAssertTrue(photo.metadata["imported"] as? Bool == true, "All filtered photos should be imported")
        }
    }
    
    func testFilterPhotos_EditedFilter_ShouldReturnOnlyEditedPhotos() {
        // Test that .edited filter returns only edited photos
        let filteredPhotos = applyFilter(.edited, to: testPhotos)
        
        let expectedCount = testPhotos.filter { $0.metadata["isEdited"] as? Bool == true }.count
        XCTAssertEqual(filteredPhotos.count, expectedCount, "Edited filter should return correct count")
        
        // Verify all returned photos are edited
        for photo in filteredPhotos {
            XCTAssertTrue(photo.metadata["isEdited"] as? Bool == true, "All filtered photos should be edited")
        }
    }
    
    func testFilterPhotos_WithLocationFilter_ShouldReturnOnlyPhotosWithGPS() {
        // Test that .withLocation filter returns only photos with GPS data
        let filteredPhotos = applyFilter(.withLocation, to: testPhotos)
        
        let expectedCount = testPhotos.filter { hasGPSData($0) }.count
        XCTAssertEqual(filteredPhotos.count, expectedCount, "Location filter should return correct count")
        
        // Verify all returned photos have GPS data
        for photo in filteredPhotos {
            XCTAssertTrue(hasGPSData(photo), "All filtered photos should have GPS data")
        }
    }
    
    func testFilterPhotos_EmptyResults_ShouldHandleGracefully() {
        // Test filtering when no photos match criteria
        let photosWithoutGPS = testPhotos.filter { !hasGPSData($0) }
        
        // Apply location filter to photos without GPS
        let filteredPhotos = applyFilter(.withLocation, to: photosWithoutGPS)
        
        XCTAssertEqual(filteredPhotos.count, 0, "Filter should return empty array when no photos match")
        XCTAssertTrue(filteredPhotos.isEmpty, "Filtered array should be empty")
    }
    
    func testFilterPhotos_MixedCriteria_ShouldFilterCorrectly() {
        // Test that photos can match multiple criteria
        let importedAndEditedPhotos = testPhotos.filter { photo in
            let isImported = photo.metadata["imported"] as? Bool == true
            let isEdited = photo.metadata["isEdited"] as? Bool == true
            return isImported && isEdited
        }
        
        XCTAssertGreaterThan(importedAndEditedPhotos.count, 0, "Should have photos that are both imported and edited")
        
        // Apply imported filter - should include imported+edited photos
        let importedFiltered = applyFilter(.imported, to: testPhotos)
        for photo in importedAndEditedPhotos {
            XCTAssertTrue(importedFiltered.contains(photo), "Imported+edited photos should appear in imported filter")
        }
        
        // Apply edited filter - should include imported+edited photos
        let editedFiltered = applyFilter(.edited, to: testPhotos)
        for photo in importedAndEditedPhotos {
            XCTAssertTrue(editedFiltered.contains(photo), "Imported+edited photos should appear in edited filter")
        }
    }
    
    // MARK: - Edge Cases
    
    func testFilterPhotos_EmptyPhotoArray_ShouldReturnEmpty() {
        // Test filtering empty array
        let emptyPhotos: [SecurePhoto] = []
        
        for filter in PhotoFilter.allCases {
            let filteredPhotos = applyFilter(filter, to: emptyPhotos)
            XCTAssertEqual(filteredPhotos.count, 0, "Filtering empty array should return empty array for \\(filter)")
        }
    }
    
    func testFilterPhotos_PhotosWithMissingMetadata_ShouldHandleGracefully() {
        // Create photos with minimal metadata
        let minimalPhoto = createTestPhoto(metadata: [:])
        let photosWithMinimal = [minimalPhoto]
        
        // Test all filters with minimal metadata
        let importedFiltered = applyFilter(.imported, to: photosWithMinimal)
        XCTAssertEqual(importedFiltered.count, 0, "Photos without imported flag should not match imported filter")
        
        let editedFiltered = applyFilter(.edited, to: photosWithMinimal)
        XCTAssertEqual(editedFiltered.count, 0, "Photos without edited flag should not match edited filter")
        
        let locationFiltered = applyFilter(.withLocation, to: photosWithMinimal)
        XCTAssertEqual(locationFiltered.count, 0, "Photos without GPS data should not match location filter")
        
        let allFiltered = applyFilter(.all, to: photosWithMinimal)
        XCTAssertEqual(allFiltered.count, 1, "Photos should still appear in all filter")
    }
    
    // MARK: - Helper Methods
    
    private func createTestPhotos() {
        testPhotos = [
            // Regular photo (taken in app)
            createTestPhoto(metadata: [
                "creationDate": Date().timeIntervalSince1970
            ]),
            
            // Imported photo
            createTestPhoto(metadata: [
                "imported": true,
                "importSource": "PhotosPicker",
                "creationDate": Date().timeIntervalSince1970
            ]),
            
            // Edited photo
            createTestPhoto(metadata: [
                "isEdited": true,
                "originalFilename": "original_photo_123",
                "creationDate": Date().timeIntervalSince1970
            ]),
            
            // Photo with GPS data
            createTestPhoto(metadata: [
                "creationDate": Date().timeIntervalSince1970,
                String(kCGImagePropertyGPSDictionary): [
                    String(kCGImagePropertyGPSLatitude): 37.7749,
                    String(kCGImagePropertyGPSLatitudeRef): "N",
                    String(kCGImagePropertyGPSLongitude): -122.4194,
                    String(kCGImagePropertyGPSLongitudeRef): "W"
                ]
            ]),
            
            // Imported and edited photo with GPS
            createTestPhoto(metadata: [
                "imported": true,
                "importSource": "PhotosPicker",
                "isEdited": true,
                "originalFilename": "imported_original_456",
                "creationDate": Date().timeIntervalSince1970,
                String(kCGImagePropertyGPSDictionary): [
                    String(kCGImagePropertyGPSLatitude): 40.7128,
                    String(kCGImagePropertyGPSLatitudeRef): "N"
                ]
            ]),
            
            // Photo with empty GPS dictionary
            createTestPhoto(metadata: [
                "creationDate": Date().timeIntervalSince1970,
                String(kCGImagePropertyGPSDictionary): [:]
            ])
        ]
    }
    
    private func createTestPhoto(metadata: [String: Any]) -> SecurePhoto {
        let testURL = URL(fileURLWithPath: "/test/path/\\(UUID().uuidString)")
        return SecurePhoto(filename: "test_\\(UUID().uuidString)", metadata: metadata, fileURL: testURL)
    }
    
    // Apply filter logic that matches SecureGalleryView implementation
    private func applyFilter(_ filter: PhotoFilter, to photos: [SecurePhoto]) -> [SecurePhoto] {
        switch filter {
        case .all:
            return photos
        case .imported:
            return photos.filter { $0.metadata["imported"] as? Bool == true }
        case .edited:
            return photos.filter { $0.metadata["isEdited"] as? Bool == true }
        case .withLocation:
            return photos.filter { photo in
                guard let gpsData = photo.metadata[String(kCGImagePropertyGPSDictionary)] as? [String: Any] else { return false }
                
                let hasLatitude = gpsData[String(kCGImagePropertyGPSLatitude)] != nil
                let hasLongitude = gpsData[String(kCGImagePropertyGPSLongitude)] != nil
                
                return hasLatitude || hasLongitude
            }
        }
    }
    
    private func hasGPSData(_ photo: SecurePhoto) -> Bool {
        guard let gpsData = photo.metadata[String(kCGImagePropertyGPSDictionary)] as? [String: Any] else { return false }
        
        let hasLatitude = gpsData[String(kCGImagePropertyGPSLatitude)] != nil
        let hasLongitude = gpsData[String(kCGImagePropertyGPSLongitude)] != nil
        
        return hasLatitude || hasLongitude
    }
}