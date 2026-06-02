//
//  OrientationRotationTests.swift
//  SnapSafeTests
//

import XCTest
import SwiftUI
import UIKit
@testable import SnapSafe

final class OrientationRotationTests: XCTestCase {

    // MARK: - Utils.getRotationAngle(for:)

    func test_rotationAngle_portrait_isZero() {
        XCTAssertEqual(Utils.getRotationAngle(for: .portrait), Angle(degrees: 0))
    }

    func test_rotationAngle_landscapeLeft_is90() {
        XCTAssertEqual(Utils.getRotationAngle(for: .landscapeLeft), Angle(degrees: 90))
    }

    func test_rotationAngle_landscapeRight_isMinus90() {
        XCTAssertEqual(Utils.getRotationAngle(for: .landscapeRight), Angle(degrees: -90))
    }

    func test_rotationAngle_portraitUpsideDown_is180() {
        XCTAssertEqual(Utils.getRotationAngle(for: .portraitUpsideDown), Angle(degrees: 180))
    }

    func test_rotationAngle_faceUp_defaultsToZero() {
        XCTAssertEqual(Utils.getRotationAngle(for: .faceUp), Angle(degrees: 0))
    }

    // MARK: - OrientationObserver.resolve(incoming:last:)

    func test_resolve_validOrientation_returnsIncoming() {
        XCTAssertEqual(
            OrientationObserver.resolve(incoming: .landscapeLeft, last: .portrait),
            .landscapeLeft
        )
    }

    func test_resolve_faceUp_keepsLast() {
        XCTAssertEqual(
            OrientationObserver.resolve(incoming: .faceUp, last: .landscapeRight),
            .landscapeRight
        )
    }

    func test_resolve_unknown_keepsLast() {
        XCTAssertEqual(
            OrientationObserver.resolve(incoming: .unknown, last: .portrait),
            .portrait
        )
    }
}
