//
//  LocationRepositoryTests.swift
//  SnapSafeTests
//
//  Maps CLAccuracyAuthorization — the user's iOS-level Precise/Approximate
//  choice — to the read-only string shown in the Settings location section.
//

import CoreLocation
import XCTest

@testable import SnapSafe

final class LocationRepositoryTests: XCTestCase {

    func test_fullAccuracy_mapsToPrecise() {
        XCTAssertEqual(LocationRepository.accuracyDisplayString(for: .fullAccuracy), "Precise")
    }

    func test_reducedAccuracy_mapsToApproximate() {
        XCTAssertEqual(LocationRepository.accuracyDisplayString(for: .reducedAccuracy), "Approximate")
    }
}
