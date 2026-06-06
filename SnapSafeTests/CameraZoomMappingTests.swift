//
//  CameraZoomMappingTests.swift
//  SnapSafeTests
//
//  Mapping between user-facing ("display") zoom factors and the virtual
//  device's videoZoomFactor space. On a virtual device (dual-wide/triple
//  camera), videoZoomFactor 1.0 is the ultra-wide lens at full FOV; the wide
//  lens engages at the first switch-over factor (typically 2.0), which is what
//  users see as "1.0x".
//

import Foundation
import XCTest

@testable import SnapSafe

final class CameraZoomMappingTests: XCTestCase {

    // MARK: - Dual-wide camera (ultra-wide + wide, switch-over at 2.0)

    func test_dualWideCamera_displayRangeCoversUltraWide() {
        let mapping = CameraZoomMapping(switchOverFactors: [2.0], maxDeviceZoom: 16.0)

        XCTAssertEqual(mapping.minDisplayZoom, 0.5)
        XCTAssertEqual(mapping.maxDisplayZoom, 8.0) // 16.0 device / 2.0, under the 10x cap
    }

    func test_dualWideCamera_displayOneIsTheWideLensSwitchOver() {
        let mapping = CameraZoomMapping(switchOverFactors: [2.0], maxDeviceZoom: 16.0)

        XCTAssertEqual(mapping.deviceZoom(forDisplayZoom: 1.0), 2.0)
        XCTAssertEqual(mapping.deviceZoom(forDisplayZoom: 0.5), 1.0)
        XCTAssertEqual(mapping.deviceZoom(forDisplayZoom: 2.0), 4.0)
    }

    func test_dualWideCamera_deviceZoomRoundTripsToDisplayZoom() {
        let mapping = CameraZoomMapping(switchOverFactors: [2.0], maxDeviceZoom: 16.0)

        XCTAssertEqual(mapping.displayZoom(forDeviceZoom: 2.0), 1.0, accuracy: 1e-9)
        XCTAssertEqual(mapping.displayZoom(forDeviceZoom: 1.0), 0.5, accuracy: 1e-9)
        XCTAssertEqual(mapping.displayZoom(forDeviceZoom: 6.0), 3.0, accuracy: 1e-9)
    }

    // MARK: - Triple camera (ultra-wide + wide + telephoto)

    func test_tripleCamera_wideLensIsTheFirstSwitchOver() {
        let mapping = CameraZoomMapping(switchOverFactors: [2.0, 6.0], maxDeviceZoom: 123.0)

        XCTAssertEqual(mapping.deviceZoom(forDisplayZoom: 1.0), 2.0)
        // Telephoto engages at device 6.0 == display 3.0; the mapping is linear across it.
        XCTAssertEqual(mapping.deviceZoom(forDisplayZoom: 3.0), 6.0)
    }

    func test_tripleCamera_displayZoomIsCappedAtTenX() {
        let mapping = CameraZoomMapping(switchOverFactors: [2.0, 6.0], maxDeviceZoom: 123.0)

        XCTAssertEqual(mapping.maxDisplayZoom, 10.0)
        XCTAssertEqual(mapping.deviceZoom(forDisplayZoom: 10.0), 20.0)
    }

    // MARK: - Wide-only device (no ultra-wide: front camera, older hardware)

    func test_wideOnlyDevice_usesIdentityMapping() {
        let mapping = CameraZoomMapping(switchOverFactors: [], maxDeviceZoom: 6.0)

        XCTAssertEqual(mapping.minDisplayZoom, 1.0)
        XCTAssertEqual(mapping.maxDisplayZoom, 6.0)
        XCTAssertEqual(mapping.deviceZoom(forDisplayZoom: 2.0), 2.0)
        XCTAssertEqual(mapping.displayZoom(forDeviceZoom: 3.0), 3.0, accuracy: 1e-9)
    }

    // MARK: - Clamping

    func test_deviceZoom_clampsDisplayZoomToValidRange() {
        let mapping = CameraZoomMapping(switchOverFactors: [2.0], maxDeviceZoom: 16.0)

        XCTAssertEqual(mapping.deviceZoom(forDisplayZoom: 0.3), 1.0)   // below ultra-wide floor
        XCTAssertEqual(mapping.deviceZoom(forDisplayZoom: 50.0), 16.0) // above device max
    }

    func test_clampedDisplayZoom_clampsToDisplayRange() {
        let mapping = CameraZoomMapping(switchOverFactors: [2.0], maxDeviceZoom: 16.0)

        XCTAssertEqual(mapping.clampedDisplayZoom(0.3), 0.5)
        XCTAssertEqual(mapping.clampedDisplayZoom(50.0), 8.0)
        XCTAssertEqual(mapping.clampedDisplayZoom(1.7), 1.7)
    }

    // MARK: - Defensive handling of degenerate values

    func test_invalidSwitchOverFactors_fallBackToIdentityMapping() {
        // A zero/negative switch-over must never produce divide-by-zero or an
        // inverted range.
        let zero = CameraZoomMapping(switchOverFactors: [0.0], maxDeviceZoom: 8.0)
        XCTAssertEqual(zero.minDisplayZoom, 1.0)
        XCTAssertEqual(zero.deviceZoom(forDisplayZoom: 2.0), 2.0)

        let negative = CameraZoomMapping(switchOverFactors: [-2.0], maxDeviceZoom: 8.0)
        XCTAssertEqual(negative.minDisplayZoom, 1.0)
    }
}
