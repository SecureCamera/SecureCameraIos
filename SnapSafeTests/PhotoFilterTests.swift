//
//  PhotoFilterTests.swift
//  SnapSafeTests
//
//  Created by Bill Booth on 5/26/25.
//

@testable import SnapSafe
import XCTest

class PhotoFilterTests: XCTestCase {
    func testPhotoFilterCases() {
        // Test all filter cases exist
        let allCases = PhotoFilter.allCases
        XCTAssertEqual(allCases.count, 4)
        XCTAssertTrue(allCases.contains(.all))
        XCTAssertTrue(allCases.contains(.imported))
        XCTAssertTrue(allCases.contains(.edited))
        XCTAssertTrue(allCases.contains(.withLocation))
    }

    func testPhotoFilterRawValues() {
        // Test raw string values
        XCTAssertEqual(PhotoFilter.all.rawValue, "All Photos")
        XCTAssertEqual(PhotoFilter.imported.rawValue, "Imported Photos")
        XCTAssertEqual(PhotoFilter.edited.rawValue, "Edited Photos")
        XCTAssertEqual(PhotoFilter.withLocation.rawValue, "Photos with Location")
    }

    func testPhotoFilterSystemImages() {
        // Test system image names
        XCTAssertEqual(PhotoFilter.all.systemImage, "photo.stack")
        XCTAssertEqual(PhotoFilter.imported.systemImage, "square.and.arrow.down")
        XCTAssertEqual(PhotoFilter.edited.systemImage, "pencil.circle")
        XCTAssertEqual(PhotoFilter.withLocation.systemImage, "location.circle")
    }
}
