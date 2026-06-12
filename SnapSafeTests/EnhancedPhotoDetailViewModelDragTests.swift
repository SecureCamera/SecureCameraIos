//
//  EnhancedPhotoDetailViewModelDragTests.swift
//  SnapSafeTests
//
//  The dismiss drag is a per-gesture state machine: direction is latched on
//  the FIRST movement (vertical → dismissing, horizontal → rejected) and never
//  re-evaluated mid-gesture, and while dismissing the offset follows the
//  finger on BOTH axes. The old per-update direction check made the image
//  freeze ("catch") whenever cumulative translation turned horizontal.
//

import XCTest

@testable import SnapSafe

@MainActor
final class EnhancedPhotoDetailViewModelDragTests: XCTestCase {

    private func makeViewModel() -> EnhancedPhotoDetailViewModel {
        EnhancedPhotoDetailViewModel(allMedia: [], initialIndex: 0)
    }

    // MARK: - Latching

    func test_verticalFirstMovement_latchesDismissing_andTracksFinger() {
        let vm = makeViewModel()

        vm.handleDragChanged(translation: CGSize(width: 5, height: 30), geometryHeight: 800)

        XCTAssertEqual(vm.dragMode, .dismissing)
        XCTAssertTrue(vm.isDismissDragging)
        XCTAssertEqual(vm.dragOffset, CGSize(width: 5, height: 30))
    }

    func test_horizontalFirstMovement_latchesRejected_andNeverMoves() {
        let vm = makeViewModel()

        vm.handleDragChanged(translation: CGSize(width: 40, height: 5), geometryHeight: 800)

        XCTAssertEqual(vm.dragMode, .rejected)
        XCTAssertEqual(vm.dragOffset, .zero)

        // A later vertical-dominant update must NOT re-engage mid-gesture.
        vm.handleDragChanged(translation: CGSize(width: 40, height: 200), geometryHeight: 800)

        XCTAssertEqual(vm.dragMode, .rejected)
        XCTAssertEqual(vm.dragOffset, .zero)
        XCTAssertEqual(vm.dismissProgress, 0)
    }

    func test_dismissingKeepsTrackingBothAxes_whenHorizontalDominates() {
        let vm = makeViewModel()

        vm.handleDragChanged(translation: CGSize(width: 0, height: 30), geometryHeight: 800)
        // The old implementation froze here (|width| > |height|).
        vm.handleDragChanged(translation: CGSize(width: 120, height: 40), geometryHeight: 800)

        XCTAssertEqual(vm.dragMode, .dismissing)
        XCTAssertEqual(vm.dragOffset, CGSize(width: 120, height: 40))
    }

    // MARK: - Progress

    func test_dismissProgress_scalesWithDownwardTravel_andClamps() {
        let vm = makeViewModel()

        vm.handleDragChanged(translation: CGSize(width: 0, height: 160), geometryHeight: 800)
        // 160 / (800 * 0.4) = 0.5
        XCTAssertEqual(vm.dismissProgress, 0.5, accuracy: 1e-9)

        vm.handleDragChanged(translation: CGSize(width: 0, height: 1000), geometryHeight: 800)
        XCTAssertEqual(vm.dismissProgress, 1.0)
    }

    func test_upwardDrag_clampsProgressToZero() {
        let vm = makeViewModel()

        vm.handleDragChanged(translation: CGSize(width: 0, height: -50), geometryHeight: 800)

        XCTAssertEqual(vm.dragMode, .dismissing)
        XCTAssertEqual(vm.dismissProgress, 0)
        // The image still follows the finger upward.
        XCTAssertEqual(vm.dragOffset, CGSize(width: 0, height: -50))
    }

    // MARK: - Gesture end

    func test_dragEnd_belowThreshold_springsBack_andResetsLatch() {
        let vm = makeViewModel()
        vm.handleDragChanged(translation: CGSize(width: 10, height: 100), geometryHeight: 800)

        vm.handleDragEnded(
            translation: CGSize(width: 10, height: 100),
            verticalVelocity: 0,
            geometryHeight: 800
        ) { XCTFail("must not dismiss below threshold") }

        XCTAssertEqual(vm.dragMode, .undecided)
        XCTAssertFalse(vm.isDismissDragging)
        XCTAssertEqual(vm.dragOffset, .zero)
        XCTAssertEqual(vm.dismissProgress, 0)
    }

    func test_dragEnd_pastThreshold_callsDismiss() async {
        let vm = makeViewModel()
        let dismissed = expectation(description: "dismiss called")
        vm.handleDragChanged(translation: CGSize(width: 0, height: 300), geometryHeight: 800)

        // 300 > 800 * 0.25
        vm.handleDragEnded(
            translation: CGSize(width: 0, height: 300),
            verticalVelocity: 0,
            geometryHeight: 800
        ) { dismissed.fulfill() }

        // The dismiss fires from a Task after a 100ms sleep; the async
        // fulfillment API services main-actor jobs while waiting.
        await fulfillment(of: [dismissed], timeout: 2.0)
        XCTAssertEqual(vm.dragMode, .undecided)
    }

    func test_dragEnd_afterRejectedGesture_resetsLatchForNextGesture() {
        let vm = makeViewModel()
        vm.handleDragChanged(translation: CGSize(width: 40, height: 5), geometryHeight: 800)
        XCTAssertEqual(vm.dragMode, .rejected)

        vm.handleDragEnded(
            translation: CGSize(width: 40, height: 5),
            verticalVelocity: 0,
            geometryHeight: 800
        ) { XCTFail("rejected gesture must not dismiss") }
        XCTAssertEqual(vm.dragMode, .undecided)

        // Next gesture can latch fresh.
        vm.handleDragChanged(translation: CGSize(width: 0, height: 30), geometryHeight: 800)
        XCTAssertEqual(vm.dragMode, .dismissing)
    }

    // MARK: - Chrome

    func test_overlayOpacity_isZero_whileDismissDragging() {
        let vm = makeViewModel()
        vm.handleDragChanged(translation: CGSize(width: 0, height: 10), geometryHeight: 800)

        XCTAssertEqual(vm.overlayOpacity, 0)
    }
}
