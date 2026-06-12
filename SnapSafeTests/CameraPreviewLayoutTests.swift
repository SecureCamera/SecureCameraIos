//
//  CameraPreviewLayoutTests.swift
//  SnapSafeTests
//

import CoreGraphics
import XCTest

@testable import SnapSafe

final class CameraPreviewLayoutTests: XCTestCase {

    func test_aspectRatio_1080p_isNineSixteenths() {
        XCTAssertEqual(
            CameraPreviewLayout.portraitAspectRatio(formatWidth: 1920, formatHeight: 1080),
            0.5625,
            accuracy: 1e-9
        )
    }

    func test_aspectRatio_fourByThree_format() {
        XCTAssertEqual(
            CameraPreviewLayout.portraitAspectRatio(formatWidth: 4032, formatHeight: 3024),
            0.75,
            accuracy: 1e-9
        )
    }

    func test_aspectRatio_invalidDimensions_fallsBackToNineSixteenths() {
        XCTAssertEqual(
            CameraPreviewLayout.portraitAspectRatio(formatWidth: 0, formatHeight: 0),
            9.0 / 16.0,
            accuracy: 1e-9
        )
    }

    func test_containerSize_fillsWidth_whenHeightFits() {
        let size = CameraPreviewLayout.containerSize(
            for: CGSize(width: 393, height: 852),
            aspectRatio: 0.5625
        )
        XCTAssertEqual(size.width, 393, accuracy: 1e-9)
        XCTAssertEqual(size.height, 393 / 0.5625, accuracy: 1e-6)
    }

    func test_containerSize_limitsByHeight_whenTooTall() {
        let size = CameraPreviewLayout.containerSize(
            for: CGSize(width: 393, height: 500),
            aspectRatio: 0.5625
        )
        XCTAssertEqual(size.height, 500, accuracy: 1e-9)
        XCTAssertEqual(size.width, 500 * 0.5625, accuracy: 1e-9)
    }

    // MARK: - largestDimensions(matchingAspectOf:)

    func test_largestDimensions_prefersAspectMatch_overLargerArea() {
        // 1920×1080 (16:9) reference: the 4:3 full-sensor entry is bigger by
        // area but must lose to the largest 16:9 entry.
        let best = CameraPreviewLayout.largestDimensions(
            matchingAspectOfWidth: 1920,
            height: 1080,
            in: [(1920, 1080), (4032, 3024), (4032, 2268)]
        )
        XCTAssertEqual(best?.width, 4032)
        XCTAssertEqual(best?.height, 2268)
    }

    func test_largestDimensions_fallsBackToLargestOverall_whenNoAspectMatch() {
        let best = CameraPreviewLayout.largestDimensions(
            matchingAspectOfWidth: 1920,
            height: 1080,
            in: [(3024, 3024), (4032, 3024)]
        )
        XCTAssertEqual(best?.width, 4032)
        XCTAssertEqual(best?.height, 3024)
    }

    func test_largestDimensions_emptyCandidates_returnsNil() {
        XCTAssertNil(CameraPreviewLayout.largestDimensions(
            matchingAspectOfWidth: 1920,
            height: 1080,
            in: []
        ))
    }
}
