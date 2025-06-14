//
//  LocationManagerTests.swift
//  SnapSafeTests
//
//  Created by Bill Booth on 5/25/25.
//

import Combine
import CoreLocation
@testable import SnapSafe
import XCTest

class LocationManagerTests: XCTestCase {
    private var locationManager: LocationManager!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        locationManager = LocationManager()
        cancellables = Set<AnyCancellable>()

        // Reset UserDefaults for testing
        UserDefaults.standard.removeObject(forKey: "shouldIncludeLocationData")
    }

    override func tearDown() {
        // Clean up UserDefaults
        UserDefaults.standard.removeObject(forKey: "shouldIncludeLocationData")

        cancellables?.removeAll()
        cancellables = nil
        locationManager = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    /// Tests that LocationManager initializes with correct default values
    /// Assertion: Should have proper initial state for authorization, location, and user preferences
    func testInit_SetsCorrectDefaults() {
        // Reset defaults and create new instance to test initialization
        UserDefaults.standard.removeObject(forKey: "shouldIncludeLocationData")
        let newLocationManager = LocationManager()

        XCTAssertEqual(newLocationManager.authorizationStatus, CLLocationManager().authorizationStatus,
                       "Authorization status should match system default")
        XCTAssertNil(newLocationManager.lastLocation, "Last location should be nil initially")
        XCTAssertFalse(newLocationManager.shouldIncludeLocationData,
                       "Should not include location data by default")
    }

    /// Tests that LocationManager loads saved user preferences from UserDefaults
    /// Assertion: Should restore shouldIncludeLocationData from saved preferences
    func testInit_LoadsSavedPreferences() {
        // Save preference and create new instance
        UserDefaults.standard.set(true, forKey: "shouldIncludeLocationData")
        let newLocationManager = LocationManager()

        XCTAssertTrue(newLocationManager.shouldIncludeLocationData,
                      "Should load saved preference for location data inclusion")
    }

    // MARK: - Location Data Preference Tests

    /// Tests that setIncludeLocationData() updates both the property and UserDefaults
    /// Assertion: Should persist preference and update published property synchronously
    func testSetIncludeLocationData_UpdatesPropertyAndUserDefaults() {
        let expectation = XCTestExpectation(description: "shouldIncludeLocationData should update")

        // Monitor property changes
        locationManager.$shouldIncludeLocationData
            .dropFirst() // Skip initial value
            .sink { includeData in
                XCTAssertTrue(includeData, "shouldIncludeLocationData should be updated to true")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        locationManager.setIncludeLocationData(true)

        // Assert UserDefaults is updated
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "shouldIncludeLocationData"),
                      "UserDefaults should be updated")

        wait(for: [expectation], timeout: 1.0)
    }

    /// Tests that setIncludeLocationData(false) properly disables location inclusion
    /// Assertion: Should set preference to false and persist in UserDefaults
    func testSetIncludeLocationData_DisablesLocationInclusion() {
        // First enable, then disable
        locationManager.setIncludeLocationData(true)
        locationManager.setIncludeLocationData(false)

        XCTAssertFalse(locationManager.shouldIncludeLocationData,
                       "shouldIncludeLocationData should be false")
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "shouldIncludeLocationData"),
                       "UserDefaults should reflect disabled preference")
    }

    // MARK: - Authorization Status Tests

    /// Tests that getAuthorizationStatusString() returns correct string representations
    /// Assertion: Should provide user-friendly strings for all authorization status cases
    func testGetAuthorizationStatusString_ReturnsCorrectStrings() {
        let testCases: [(CLAuthorizationStatus, String)] = [
            (.notDetermined, "Not Determined"),
            (.restricted, "Restricted"),
            (.denied, "Denied"),
            (.authorizedWhenInUse, "Authorized"),
            (.authorizedAlways, "Authorized"),
        ]

        for (status, expectedString) in testCases {
            locationManager.authorizationStatus = status
            let statusString = locationManager.getAuthorizationStatusString()
            XCTAssertEqual(statusString, expectedString,
                           "Status \(status) should return '\(expectedString)'")
        }
    }

    // MARK: - Location Metadata Tests

    /// Tests that getCurrentLocationMetadata() returns nil when location data is disabled
    /// Assertion: Should not provide metadata when user has disabled location inclusion
    func testGetCurrentLocationMetadata_ReturnsNilWhenDisabled() {
        locationManager.setIncludeLocationData(false)
        locationManager.authorizationStatus = .authorizedWhenInUse
        locationManager.lastLocation = createTestLocation()

        let metadata = locationManager.getCurrentLocationMetadata()

        XCTAssertNil(metadata, "Should return nil when location data inclusion is disabled")
    }

    /// Tests that getCurrentLocationMetadata() returns nil when not authorized
    /// Assertion: Should not provide metadata without proper authorization
    func testGetCurrentLocationMetadata_ReturnsNilWhenNotAuthorized() {
        locationManager.setIncludeLocationData(true)
        locationManager.authorizationStatus = .denied
        locationManager.lastLocation = createTestLocation()

        let metadata = locationManager.getCurrentLocationMetadata()

        XCTAssertNil(metadata, "Should return nil when location access is not authorized")
    }

    /// Tests that getCurrentLocationMetadata() returns nil when no location is available
    /// Assertion: Should not provide metadata when lastLocation is nil
    func testGetCurrentLocationMetadata_ReturnsNilWhenNoLocation() {
        locationManager.setIncludeLocationData(true)
        locationManager.authorizationStatus = .authorizedWhenInUse
        locationManager.lastLocation = nil

        let metadata = locationManager.getCurrentLocationMetadata()

        XCTAssertNil(metadata, "Should return nil when no location is available")
    }

    /// Tests that getCurrentLocationMetadata() returns proper GPS metadata when conditions are met
    /// Assertion: Should create valid GPS metadata dictionary with latitude, longitude, and timestamp
    func testGetCurrentLocationMetadata_ReturnsValidGPSMetadata() {
        locationManager.setIncludeLocationData(true)
        locationManager.authorizationStatus = .authorizedWhenInUse

        let testLocation = createTestLocation(
            latitude: 37.7749, // San Francisco
            longitude: -122.4194,
            altitude: 100.0
        )
        locationManager.lastLocation = testLocation

        let metadata = locationManager.getCurrentLocationMetadata()

        XCTAssertNotNil(metadata, "Should return metadata when conditions are met")

        guard let gpsDict = metadata?[String(kCGImagePropertyGPSDictionary)] as? [String: Any] else {
            XCTFail("Should contain GPS dictionary")
            return
        }

        // Test latitude
        XCTAssertEqual(gpsDict[String(kCGImagePropertyGPSLatitudeRef)] as? String, "N",
                       "Latitude reference should be North for positive latitude")
        XCTAssertEqual(gpsDict[String(kCGImagePropertyGPSLatitude)] as? Double, 37.7749,
                       "Latitude should match test location")

        // Test longitude
        XCTAssertEqual(gpsDict[String(kCGImagePropertyGPSLongitudeRef)] as? String, "W",
                       "Longitude reference should be West for negative longitude")
        XCTAssertEqual(gpsDict[String(kCGImagePropertyGPSLongitude)] as? Double, 122.4194,
                       "Longitude should be absolute value")

        // Test altitude
        XCTAssertEqual(gpsDict[String(kCGImagePropertyGPSAltitudeRef)] as? Int, 0,
                       "Altitude reference should be 0 for above sea level")
        XCTAssertEqual(gpsDict[String(kCGImagePropertyGPSAltitude)] as? Double, 100.0,
                       "Altitude should match test location")

        // Test timestamp
        XCTAssertNotNil(gpsDict[String(kCGImagePropertyGPSDateStamp)],
                        "Should include GPS timestamp")
    }

    /// Tests that getCurrentLocationMetadata() handles negative coordinates correctly
    /// Assertion: Should set proper hemisphere references for Southern/Western coordinates
    func testGetCurrentLocationMetadata_HandlesNegativeCoordinates() {
        locationManager.setIncludeLocationData(true)
        locationManager.authorizationStatus = .authorizedWhenInUse

        let testLocation = createTestLocation(
            latitude: -33.8688, // Sydney (Southern Hemisphere)
            longitude: 151.2093, // Sydney (Eastern Hemisphere)
            altitude: -10.0 // Below sea level
        )
        locationManager.lastLocation = testLocation

        let metadata = locationManager.getCurrentLocationMetadata()

        guard let gpsDict = metadata?[String(kCGImagePropertyGPSDictionary)] as? [String: Any] else {
            XCTFail("Should contain GPS dictionary")
            return
        }

        // Test negative latitude (Southern Hemisphere)
        XCTAssertEqual(gpsDict[String(kCGImagePropertyGPSLatitudeRef)] as? String, "S",
                       "Latitude reference should be South for negative latitude")
        XCTAssertEqual(gpsDict[String(kCGImagePropertyGPSLatitude)] as? Double, 33.8688,
                       "Latitude should be absolute value")

        // Test positive longitude (Eastern Hemisphere)
        XCTAssertEqual(gpsDict[String(kCGImagePropertyGPSLongitudeRef)] as? String, "E",
                       "Longitude reference should be East for positive longitude")
        XCTAssertEqual(gpsDict[String(kCGImagePropertyGPSLongitude)] as? Double, 151.2093,
                       "Longitude should match test location")

        // Test negative altitude (below sea level)
        XCTAssertEqual(gpsDict[String(kCGImagePropertyGPSAltitudeRef)] as? Int, 1,
                       "Altitude reference should be 1 for below sea level")
        XCTAssertEqual(gpsDict[String(kCGImagePropertyGPSAltitude)] as? Double, 10.0,
                       "Altitude should be absolute value")
    }

    /// Tests that getCurrentLocationMetadata() handles location with poor vertical accuracy
    /// Assertion: Should exclude altitude data when vertical accuracy is poor
    func testGetCurrentLocationMetadata_HandlesPoorVerticalAccuracy() {
        locationManager.setIncludeLocationData(true)
        locationManager.authorizationStatus = .authorizedWhenInUse

        let testLocation = createTestLocation(
            latitude: 40.7128,
            longitude: -74.0060,
            altitude: 50.0,
            verticalAccuracy: -1.0 // Negative indicates invalid reading
        )
        locationManager.lastLocation = testLocation

        let metadata = locationManager.getCurrentLocationMetadata()

        guard let gpsDict = metadata?[String(kCGImagePropertyGPSDictionary)] as? [String: Any] else {
            XCTFail("Should contain GPS dictionary")
            return
        }

        // Should not include altitude data when vertical accuracy is poor
        XCTAssertNil(gpsDict[String(kCGImagePropertyGPSAltitudeRef)],
                     "Should not include altitude reference when vertical accuracy is poor")
        XCTAssertNil(gpsDict[String(kCGImagePropertyGPSAltitude)],
                     "Should not include altitude when vertical accuracy is poor")

        // Should still include latitude and longitude
        XCTAssertNotNil(gpsDict[String(kCGImagePropertyGPSLatitude)],
                        "Should still include latitude")
        XCTAssertNotNil(gpsDict[String(kCGImagePropertyGPSLongitude)],
                        "Should still include longitude")
    }

    // MARK: - Published Properties Tests

    /// Tests that authorizationStatus property publishes changes correctly
    /// Assertion: Property changes should be observable by subscribers
    func testAuthorizationStatus_PublishesChanges() {
        let expectation = XCTestExpectation(description: "authorizationStatus should publish changes")

        locationManager.$authorizationStatus
            .dropFirst() // Skip initial value
            .sink { status in
                XCTAssertEqual(status, .authorizedWhenInUse, "Should receive updated authorization status")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        locationManager.authorizationStatus = .authorizedWhenInUse

        wait(for: [expectation], timeout: 1.0)
    }

    /// Tests that lastLocation property publishes changes correctly
    /// Assertion: Location updates should be observable by subscribers
//    func testLastLocation_PublishesChanges() {
//        let expectation = XCTestExpectation(description: "lastLocation should publish changes")
//
//        locationManager.$lastLocation
//            .dropFirst() // Skip initial nil value
//            .sink { location in
//                XCTAssertNotNil(location, "Should receive updated location")
//                XCTAssertEqual(location?.coordinate.latitude!, 37.7749, accuracy: 0.0001)
//                expectation.fulfill()
//            }
//            .store(in: &cancellables)
//
//        locationManager.lastLocation = createTestLocation()
//
//        wait(for: [expectation], timeout: 1.0)
//    }

    /// Tests that shouldIncludeLocationData property publishes changes correctly
    /// Assertion: User preference changes should be observable by subscribers
    func testShouldIncludeLocationData_PublishesChanges() {
        let expectation = XCTestExpectation(description: "shouldIncludeLocationData should publish changes")

        locationManager.$shouldIncludeLocationData
            .dropFirst() // Skip initial value
            .sink { shouldInclude in
                XCTAssertTrue(shouldInclude, "Should receive updated preference")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        locationManager.shouldIncludeLocationData = true

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Integration Tests

    /// Tests the complete flow of enabling location data and getting metadata
    /// Assertion: Should properly handle the full workflow from permission to metadata generation
    func testLocationDataFlow_CompleteWorkflow() {
        // Start with disabled location data
        XCTAssertFalse(locationManager.shouldIncludeLocationData,
                       "Should start with location data disabled")

        // Enable location data
        locationManager.setIncludeLocationData(true)
        XCTAssertTrue(locationManager.shouldIncludeLocationData,
                      "Should enable location data")

        // Set authorization as if user granted permission
        locationManager.authorizationStatus = .authorizedWhenInUse

        // Simulate location update
        locationManager.lastLocation = createTestLocation()

        // Get metadata
        let metadata = locationManager.getCurrentLocationMetadata()
        XCTAssertNotNil(metadata, "Should generate metadata with all conditions met")

        // Disable location data
        locationManager.setIncludeLocationData(false)

        // Metadata should now be nil
        let metadataAfterDisable = locationManager.getCurrentLocationMetadata()
        XCTAssertNil(metadataAfterDisable, "Should not generate metadata when disabled")
    }

    // MARK: - Helper Methods

    /// Creates a test CLLocation with specified coordinates
    private func createTestLocation(
        latitude: Double = 37.7749,
        longitude: Double = -122.4194,
        altitude: Double = 100.0,
        horizontalAccuracy: Double = 5.0,
        verticalAccuracy: Double = 5.0
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            timestamp: Date()
        )
    }
}
