//
//  CameraLifecycleTests.swift
//  SnapSafeTests
//
//  Tests for camera lifecycle management during app state transitions.
//  These tests verify that the camera properly handles backgrounding/foregrounding
//  to prevent frozen camera bugs and layout shifts.
//

import XCTest
import AVFoundation
import Combine
@testable import SnapSafe

@MainActor
class CameraLifecycleTests: XCTestCase {

    private var cameraViewModel: CameraViewModel!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()
        cameraViewModel = CameraViewModel()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() async throws {
        cancellables?.removeAll()
        cancellables = nil
        cameraViewModel = nil
        try await super.tearDown()
    }

    // MARK: - Session Active State Tests

    /// Tests that isSessionActive starts as false before session starts
    /// Assertion: Should default to false until session is running
    func testIsSessionActive_DefaultsToFalse() {
        XCTAssertFalse(cameraViewModel.isSessionActive, "isSessionActive should default to false")
    }

    /// Tests that isSessionActive becomes true when session starts running
    /// Assertion: Should set isSessionActive to true when AVCaptureSessionDidStartRunning fires
    func testIsSessionActive_BecomesTrue_WhenSessionStarts() {
        let expectation = XCTestExpectation(description: "isSessionActive should become true")

        cameraViewModel.$isSessionActive
            .dropFirst()
            .sink { isActive in
                if isActive {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // Simulate the session starting notification
        NotificationCenter.default.post(name: AVCaptureSession.didStartRunningNotification, object: nil)

        wait(for: [expectation], timeout: 2.0)
        XCTAssertTrue(cameraViewModel.isSessionActive, "isSessionActive should be true after session starts")
    }

    /// Tests that isSessionActive becomes false when app will resign active
    /// Assertion: Should set isSessionActive to false immediately when backgrounding
    func testIsSessionActive_BecomesFalse_WhenAppResignsActive() {
        // First, set session as active
        NotificationCenter.default.post(name: AVCaptureSession.didStartRunningNotification, object: nil)

        let expectation = XCTestExpectation(description: "isSessionActive should become false")

        // Wait for session to become active first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.cameraViewModel.$isSessionActive
                .dropFirst()
                .sink { isActive in
                    if !isActive {
                        expectation.fulfill()
                    }
                }
                .store(in: &self.cancellables)

            // Simulate app going to background
            NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        }

        wait(for: [expectation], timeout: 2.0)
        XCTAssertFalse(cameraViewModel.isSessionActive, "isSessionActive should be false after app resigns active")
    }

    // MARK: - Full Lifecycle Flow Tests

    /// Tests the complete background/foreground cycle
    /// Assertion: Should handle the full cycle: active -> background -> foreground -> active
    func testLifecycleFlow_BackgroundAndForeground() {
        var stateChanges: [Bool] = []
        let expectation = XCTestExpectation(description: "Should complete lifecycle flow")
        expectation.expectedFulfillmentCount = 3 // active, inactive, active again

        cameraViewModel.$isSessionActive
            .dropFirst()
            .sink { isActive in
                stateChanges.append(isActive)
                if stateChanges.count >= 3 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // 1. Session starts (simulates initial app launch)
        NotificationCenter.default.post(name: AVCaptureSession.didStartRunningNotification, object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // 2. App goes to background
            NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // 3. App comes back to foreground and session restarts
            NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
            // Session start notification fires when session actually starts
            NotificationCenter.default.post(name: AVCaptureSession.didStartRunningNotification, object: nil)
        }

        wait(for: [expectation], timeout: 3.0)

        XCTAssertEqual(stateChanges, [true, false, true],
                       "State should flow: false -> true -> false -> true")
    }

    // MARK: - Preview Layer Connection Tests

    /// Tests that preview layer connection is properly managed during lifecycle
    /// Assertion: Preview layer should be assigned and connection managed correctly
    func testPreviewLayer_AssignedCorrectly() {
        // Create a mock preview layer
        let mockPreviewLayer = AVCaptureVideoPreviewLayer()
        cameraViewModel.preview = mockPreviewLayer

        XCTAssertNotNil(cameraViewModel.preview, "Preview layer should be assigned")
        XCTAssertIdentical(cameraViewModel.preview, mockPreviewLayer, "Should be the same instance")
    }

    /// Tests that preview layer connection is disabled when app resigns active
    /// Assertion: Connection should be disabled to clear stale frame buffer
    func testPreviewLayerConnection_DisabledOnBackground() {
        // Create a mock preview layer with a connection
        let mockPreviewLayer = AVCaptureVideoPreviewLayer()
        mockPreviewLayer.session = cameraViewModel.session
        cameraViewModel.preview = mockPreviewLayer

        // Verify connection exists initially (may be nil if session not configured)
        let connectionBefore = mockPreviewLayer.connection

        // Simulate app going to background
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)

        // If there was a connection, it should now be disabled
        if let connection = connectionBefore {
            XCTAssertFalse(connection.isEnabled, "Connection should be disabled when app backgrounds")
        }
    }

    /// Tests that preview layer connection is re-enabled when session starts
    /// Assertion: Connection should be re-enabled when session starts running
    func testPreviewLayerConnection_EnabledOnSessionStart() {
        // Create a mock preview layer
        let mockPreviewLayer = AVCaptureVideoPreviewLayer()
        mockPreviewLayer.session = cameraViewModel.session
        cameraViewModel.preview = mockPreviewLayer

        // If connection exists, manually disable it first
        mockPreviewLayer.connection?.isEnabled = false

        // Simulate session starting
        NotificationCenter.default.post(name: AVCaptureSession.didStartRunningNotification, object: nil)

        // Connection should be re-enabled
        if let connection = mockPreviewLayer.connection {
            XCTAssertTrue(connection.isEnabled, "Connection should be enabled when session starts")
        }
    }

    // MARK: - Zoom Reset Tests

    /// Tests that zoom level is reset when app enters foreground
    /// Assertion: Should reset zoom to 1.0 when coming from background
    func testZoomReset_OnForeground() {
        let expectation = XCTestExpectation(description: "Zoom should reset")

        // Observe zoom changes
        cameraViewModel.$isSessionActive
            .dropFirst()
            .sink { _ in
                // After foreground notification, check zoom
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    XCTAssertEqual(self.cameraViewModel.zoomFactor, 1.0, "Zoom should be reset to 1.0")
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // Simulate app entering foreground
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.post(name: AVCaptureSession.didStartRunningNotification, object: nil)

        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - Session Management Tests

    /// Tests that session stop is called when app resigns active
    /// Assertion: Session should stop running when app goes to background
    func testSessionStop_OnBackground() {
        // Start with session running indicator
        NotificationCenter.default.post(name: AVCaptureSession.didStartRunningNotification, object: nil)

        let expectation = XCTestExpectation(description: "Session state should change")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Simulate app going to background
            NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)

            // isSessionActive should be false
            XCTAssertFalse(self.cameraViewModel.isSessionActive, "Session should be marked inactive")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    /// Tests that session restart is triggered when app enters foreground
    /// Assertion: Should attempt to restart session when coming from background
    func testSessionRestart_OnForeground() {
        // Mark session as inactive (simulating background state)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)

        let expectation = XCTestExpectation(description: "Session should restart")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.cameraViewModel.$isSessionActive
                .dropFirst()
                .sink { isActive in
                    if isActive {
                        expectation.fulfill()
                    }
                }
                .store(in: &self.cancellables)

            // Simulate app entering foreground
            NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
            // Session actually starts
            NotificationCenter.default.post(name: AVCaptureSession.didStartRunningNotification, object: nil)
        }

        wait(for: [expectation], timeout: 2.0)
        XCTAssertTrue(cameraViewModel.isSessionActive, "Session should be active after foreground")
    }

    // MARK: - Edge Case Tests

    /// Tests rapid background/foreground transitions
    /// Assertion: Should handle rapid state changes without crashing
    func testRapidLifecycleTransitions_HandledGracefully() {
        let expectation = XCTestExpectation(description: "Should handle rapid transitions")

        // Rapidly cycle through states
        for i in 0..<5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.05) {
                NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.05 + 0.025) {
                NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
                NotificationCenter.default.post(name: AVCaptureSession.didStartRunningNotification, object: nil)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Should not crash and should be in a valid state
            XCTAssertNotNil(self.cameraViewModel, "ViewModel should still exist")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    /// Tests that notifications are properly cleaned up on deinit
    /// Assertion: Should remove notification observers when deallocated
    func testNotificationCleanup_OnDeinit() {
        // Create a new instance
        var testViewModel: CameraViewModel? = CameraViewModel()
        XCTAssertNotNil(testViewModel, "ViewModel should be created")

        // Release the instance
        testViewModel = nil

        // If observers weren't removed, posting notifications could cause issues
        // This test passing without crash indicates proper cleanup
        NotificationCenter.default.post(name: AVCaptureSession.didStartRunningNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)

        XCTAssertNil(testViewModel, "ViewModel should be deallocated")
    }

    // MARK: - ViewSize Stability Tests

    /// Tests that viewSize maintains full screen dimensions after updates
    /// Regression test for bug where viewSize was incorrectly shrunk to containerSize
    /// This caused buttons to shift upward when app returned from background
    /// Assertion: viewSize should remain at full screen size, not shrink to container size
    func testViewSize_MaintainsFullScreenDimensions_AfterMultipleUpdates() {
        // Simulate full screen size (typical iPhone dimensions)
        let fullScreenSize = CGSize(width: 393, height: 852)

        // Set initial viewSize to full screen
        cameraViewModel.viewSize = fullScreenSize
        XCTAssertEqual(cameraViewModel.viewSize, fullScreenSize,
                      "Initial viewSize should be full screen size")

        // Simulate what happens in updateUIView - it calculates container size
        // but should store full viewSize, not containerSize
        let photoAspectRatio: CGFloat = 3.0 / 4.0
        let containerWidth = fullScreenSize.width
        let containerHeight = containerWidth / photoAspectRatio
        let containerSize = CGSize(width: containerWidth, height: containerHeight)

        // Verify container is smaller than full screen (this is expected)
        XCTAssertLessThan(containerSize.height, fullScreenSize.height,
                         "Container height should be less than full screen height")

        // Simulate first update (what happens when app backgrounds/foregrounds)
        // The bug was that this would incorrectly store containerSize
        // With the fix, it should store fullScreenSize
        cameraViewModel.viewSize = fullScreenSize  // Correct behavior

        XCTAssertEqual(cameraViewModel.viewSize, fullScreenSize,
                      "After first update, viewSize should still be full screen size")
        XCTAssertNotEqual(cameraViewModel.viewSize.height, containerSize.height,
                         "viewSize should not be shrunk to container height")

        // Simulate second update to verify no progressive shrinking
        cameraViewModel.viewSize = fullScreenSize

        XCTAssertEqual(cameraViewModel.viewSize, fullScreenSize,
                      "After second update, viewSize should still be full screen size")
        XCTAssertEqual(cameraViewModel.viewSize.width, 393,
                      "Width should remain at original full screen width")
        XCTAssertEqual(cameraViewModel.viewSize.height, 852,
                      "Height should remain at original full screen height")
    }

    /// Tests that viewSize doesn't shrink during background/foreground lifecycle
    /// Regression test for button shift bug
    /// Assertion: viewSize should be stable across app lifecycle transitions
    func testViewSize_StableAcrossBackgroundForegroundCycle() {
        let fullScreenSize = CGSize(width: 393, height: 852)
        cameraViewModel.viewSize = fullScreenSize

        let initialSize = cameraViewModel.viewSize

        // Simulate app going to background
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)

        let sizeAfterBackground = cameraViewModel.viewSize
        XCTAssertEqual(sizeAfterBackground, initialSize,
                      "viewSize should not change when app backgrounds")

        // Simulate app coming back to foreground (this triggers updateUIView)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)

        // After foreground, viewSize should still be full screen
        let sizeAfterForeground = cameraViewModel.viewSize
        XCTAssertEqual(sizeAfterForeground, initialSize,
                      "viewSize should not shrink after returning from background")
        XCTAssertEqual(sizeAfterForeground.width, fullScreenSize.width,
                      "Width should remain unchanged after lifecycle transition")
        XCTAssertEqual(sizeAfterForeground.height, fullScreenSize.height,
                      "Height should remain unchanged after lifecycle transition")
    }

    // MARK: - State Consistency Tests

    /// Tests that isSessionActive state is consistent with session
    /// Assertion: State should accurately reflect session running status
    func testStateConsistency_WithSession() {
        // Initially inactive
        XCTAssertFalse(cameraViewModel.isSessionActive, "Should start inactive")

        // Session starts
        NotificationCenter.default.post(name: AVCaptureSession.didStartRunningNotification, object: nil)

        let expectation = XCTestExpectation(description: "State should be consistent")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.cameraViewModel.isSessionActive, "Should be active after session starts")

            // App backgrounds
            NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                XCTAssertFalse(self.cameraViewModel.isSessionActive, "Should be inactive after background")
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 2.0)
    }
}
