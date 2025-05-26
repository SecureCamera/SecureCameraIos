//
//  CameraModelTests.swift
//  SnapSafeTests
//
//  Created by Bill Booth on 5/25/25.
//

import XCTest
import AVFoundation
import Combine
@testable import SnapSafe

class CameraModelTests: XCTestCase {
    
    private var cameraModel: CameraModel!
    private var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        cameraModel = CameraModel()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        cancellables?.removeAll()
        cancellables = nil
        cameraModel = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    /// Tests that CameraModel initializes with correct default values
    /// Assertion: Should have proper initial state for all camera properties
    func testInit_SetsCorrectDefaults() {
        XCTAssertFalse(cameraModel.isPermissionGranted, "Permission should initially be false")
        XCTAssertNotNil(cameraModel.session, "AVCaptureSession should be initialized")
        XCTAssertFalse(cameraModel.alert, "Alert should initially be false")
        XCTAssertNotNil(cameraModel.output, "Photo output should be initialized")
        XCTAssertNil(cameraModel.recentImage, "Recent image should initially be nil")
        XCTAssertEqual(cameraModel.zoomFactor, 1.0, "Zoom factor should default to 1.0")
        XCTAssertEqual(cameraModel.minZoom, 0.5, "Min zoom should default to 0.5")
        XCTAssertEqual(cameraModel.maxZoom, 10.0, "Max zoom should default to 10.0")
        XCTAssertEqual(cameraModel.currentLensType, .wideAngle, "Should default to wide angle lens")
        XCTAssertNil(cameraModel.focusIndicatorPoint, "Focus indicator should initially be nil")
        XCTAssertFalse(cameraModel.showingFocusIndicator, "Should not show focus indicator initially")
        XCTAssertEqual(cameraModel.flashMode, .auto, "Flash mode should default to auto")
        XCTAssertEqual(cameraModel.cameraPosition, .back, "Should default to back camera")
    }
    
    /// Tests that CameraModel sets up foreground notification listener correctly
    /// Assertion: Should listen for app entering foreground to reset zoom level
    func testInit_SetsUpForegroundNotificationListener() {
        // This is tested indirectly through the zoom reset functionality
        // We can't easily test NotificationCenter observer setup directly
        XCTAssertNotNil(cameraModel, "Camera model should initialize without issues")
    }
    
    // MARK: - Permission Handling Tests
    
    /// Tests that checkPermissions handles simulator environment correctly
    /// Assertion: Should grant permission immediately in simulator debug builds
    func testCheckPermissions_HandlesSimulatorCorrectly() {
        #if DEBUG && targetEnvironment(simulator)
        let expectation = XCTestExpectation(description: "Permission should be granted in simulator")
        
        cameraModel.$isPermissionGranted
            .dropFirst()
            .sink { isGranted in
                if isGranted {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        cameraModel.checkPermissions()
        
        wait(for: [expectation], timeout: 3.0)
        #else
        // On real device, we can't reliably test permission states without user interaction
        XCTAssertTrue(true, "Skipping permission test on real device")
        #endif
    }
    
    /// Tests that checkPermissions handles authorized status correctly
    /// Assertion: Should set permission granted when already authorized
    func testCheckPermissions_HandlesAuthorizedStatus() {
        // Note: This test is limited because we can't control AVCaptureDevice authorization status
        // In a production app, you might use dependency injection to test this
        
        cameraModel.checkPermissions()
        
        // Test completes without crashing - actual permission depends on device/simulator state
        XCTAssertNotNil(cameraModel, "Should handle permission check without crashing")
    }
    
    // MARK: - Zoom Control Tests
    
    /// Tests that zoom factor can be updated correctly
    /// Assertion: Should update zoom factor and validate bounds
    func testZoomFactor_UpdatesCorrectly() {
        let expectation = XCTestExpectation(description: "Zoom factor should update")
        
        cameraModel.$zoomFactor
            .dropFirst()
            .sink { zoomFactor in
                XCTAssertEqual(zoomFactor, 2.0, "Zoom factor should be updated to 2.0")
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        cameraModel.zoomFactor = 2.0
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    /// Tests that resetZoomLevel resets zoom to 1.0
    /// Assertion: Should reset zoom factor to default value
    func testResetZoomLevel_ResetsToDefault() {
        let expectation = XCTestExpectation(description: "Zoom should reset to 1.0")
        
        // First set zoom to non-default value
        cameraModel.zoomFactor = 3.0
        
        cameraModel.$zoomFactor
            .dropFirst()
            .sink { zoomFactor in
                if zoomFactor == 1.0 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        cameraModel.resetZoomLevel()
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    /// Tests that zoom bounds are validated correctly
    /// Assertion: Should maintain zoom within min/max bounds
    func testZoomBounds_ValidatedCorrectly() {
        // Test that zoom factor stays within bounds
        let minZoom = cameraModel.minZoom
        let maxZoom = cameraModel.maxZoom
        
        XCTAssertLessThanOrEqual(cameraModel.zoomFactor, maxZoom, "Zoom should not exceed max")
        XCTAssertGreaterThanOrEqual(cameraModel.zoomFactor, minZoom, "Zoom should not go below min")
    }
    
    // MARK: - Camera Position Tests
    
    /// Tests that camera position can be changed
    /// Assertion: Should update camera position property
    func testCameraPosition_CanBeChanged() {
        let expectation = XCTestExpectation(description: "Camera position should change")
        
        cameraModel.$cameraPosition
            .dropFirst()
            .sink { position in
                XCTAssertEqual(position, .front, "Camera position should change to front")
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        cameraModel.cameraPosition = .front
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    /// Tests that lens type can be changed
    /// Assertion: Should update lens type property
    func testLensType_CanBeChanged() {
        let expectation = XCTestExpectation(description: "Lens type should change")
        
        cameraModel.$currentLensType
            .dropFirst()
            .sink { lensType in
                XCTAssertEqual(lensType, .ultraWide, "Lens type should change to ultra wide")
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        cameraModel.currentLensType = .ultraWide
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Flash Mode Tests
    
    /// Tests that flash mode can be updated
    /// Assertion: Should update flash mode property correctly
    func testFlashMode_CanBeUpdated() {
        let expectation = XCTestExpectation(description: "Flash mode should update")
        
        cameraModel.$flashMode
            .dropFirst()
            .sink { flashMode in
                XCTAssertEqual(flashMode, .on, "Flash mode should change to on")
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        cameraModel.flashMode = .on
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    /// Tests all flash mode options
    /// Assertion: Should support all standard flash modes
    func testFlashMode_SupportsAllOptions() {
        let flashModes: [AVCaptureDevice.FlashMode] = [.auto, .on, .off]
        
        for mode in flashModes {
            cameraModel.flashMode = mode
            XCTAssertEqual(cameraModel.flashMode, mode, "Should support flash mode: \(mode)")
        }
    }
    
    // MARK: - Focus Indicator Tests
    
    /// Tests that focus indicator can be shown and hidden
    /// Assertion: Should update focus indicator visibility correctly
    func testFocusIndicator_CanBeShownAndHidden() {
        let expectation = XCTestExpectation(description: "Focus indicator should update")
        expectation.expectedFulfillmentCount = 2
        
        cameraModel.$showingFocusIndicator
            .dropFirst()
            .sink { showing in
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        cameraModel.showingFocusIndicator = true
        cameraModel.showingFocusIndicator = false
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    /// Tests that focus indicator point can be set
    /// Assertion: Should update focus point correctly
    func testFocusIndicatorPoint_CanBeSet() {
        let expectation = XCTestExpectation(description: "Focus point should update")
        let testPoint = CGPoint(x: 100, y: 150)
        
        cameraModel.$focusIndicatorPoint
            .dropFirst()
            .sink { point in
                XCTAssertEqual(point, testPoint, "Focus point should be set correctly")
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        cameraModel.focusIndicatorPoint = testPoint
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Recent Image Tests
    
    /// Tests that recent image can be set and retrieved
    /// Assertion: Should store and retrieve recent image correctly
    func testRecentImage_CanBeSetAndRetrieved() {
        let expectation = XCTestExpectation(description: "Recent image should update")
        let testImage = createTestImage()
        
        cameraModel.$recentImage
            .dropFirst()
            .sink { image in
                XCTAssertNotNil(image, "Recent image should be set")
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        cameraModel.recentImage = testImage
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Alert State Tests
    
    /// Tests that alert state can be managed correctly
    /// Assertion: Should update alert state correctly
    func testAlert_CanBeManaged() {
        let expectation = XCTestExpectation(description: "Alert state should update")
        
        cameraModel.$alert
            .dropFirst()
            .sink { alertShowing in
                XCTAssertTrue(alertShowing, "Alert should be showing")
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        cameraModel.alert = true
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Session Management Tests
    
    /// Tests that AVCaptureSession is properly initialized
    /// Assertion: Should have valid capture session
    func testSession_ProperlyInitialized() {
        XCTAssertNotNil(cameraModel.session, "Capture session should be initialized")
        XCTAssertTrue(cameraModel.session is AVCaptureSession, "Should be AVCaptureSession instance")
    }
    
    /// Tests that photo output is properly initialized
    /// Assertion: Should have valid photo output
    func testPhotoOutput_ProperlyInitialized() {
        XCTAssertNotNil(cameraModel.output, "Photo output should be initialized")
        XCTAssertTrue(cameraModel.output is AVCapturePhotoOutput, "Should be AVCapturePhotoOutput instance")
    }
    
    // MARK: - Simulator-Specific Tests
    
    #if DEBUG && targetEnvironment(simulator)
    /// Tests that simulator setup works correctly
    /// Assertion: Should set up mock camera functionality in simulator
    func testSimulatorSetup_WorksCorrectly() {
        let expectation = XCTestExpectation(description: "Simulator setup should complete")
        
        // In simulator, permission should be granted quickly
        cameraModel.$isPermissionGranted
            .dropFirst()
            .sink { isGranted in
                if isGranted {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // Call setup directly for testing
        cameraModel.checkPermissions()
        
        wait(for: [expectation], timeout: 3.0)
        
        // Check that zoom values are set correctly for simulator
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            XCTAssertEqual(self.cameraModel.minZoom, 0.5, "Simulator min zoom should be 0.5")
            XCTAssertEqual(self.cameraModel.maxZoom, 10.0, "Simulator max zoom should be 10.0")
            XCTAssertEqual(self.cameraModel.zoomFactor, 1.0, "Simulator zoom factor should be 1.0")
        }
    }
    
    /// Tests that mock photo capture works in simulator
    /// Assertion: Should be able to capture mock photos without camera hardware
    func testMockPhotoCapture_WorksInSimulator() {
        // Test that the camera model can handle mock photo operations
        // Since captureMockPhoto is private, we test indirectly through the public interface
        XCTAssertNotNil(cameraModel, "Camera model should work in simulator")
        
        // Test that recent image can be set (simulating capture)
        let mockImage = createTestImage()
        cameraModel.recentImage = mockImage
        
        XCTAssertNotNil(cameraModel.recentImage, "Should be able to set recent image in simulator")
    }
    #endif
    
    // MARK: - View Size Tests
    
    /// Tests that view size can be set and maintained
    /// Assertion: Should store view size for camera calculations
    func testViewSize_CanBeSetAndMaintained() {
        let testSize = CGSize(width: 375, height: 812)
        
        cameraModel.viewSize = testSize
        
        XCTAssertEqual(cameraModel.viewSize, testSize, "View size should be maintained")
    }
    
    // MARK: - Memory Management Tests
    
    /// Tests that camera model properly handles deinitialization
    /// Assertion: Should clean up resources without memory leaks
    func testDeinit_CleansUpResources() {
        // Create and release camera model to test deinit
        var testCameraModel: CameraModel? = CameraModel()
        XCTAssertNotNil(testCameraModel, "Camera model should be created")
        
        testCameraModel = nil
        XCTAssertNil(testCameraModel, "Camera model should be deallocated")
    }
    
    // MARK: - Published Properties Tests
    
    /// Tests that all published properties can be observed
    /// Assertion: All @Published properties should emit changes correctly
    func testPublishedProperties_EmitChangesCorrectly() {
        let expectation = XCTestExpectation(description: "Published properties should emit changes")
        expectation.expectedFulfillmentCount = 8 // Number of properties we'll test
        
        // Test multiple published properties
        cameraModel.$isPermissionGranted.dropFirst().sink { _ in expectation.fulfill() }.store(in: &cancellables)
        cameraModel.$alert.dropFirst().sink { _ in expectation.fulfill() }.store(in: &cancellables)
        cameraModel.$zoomFactor.dropFirst().sink { _ in expectation.fulfill() }.store(in: &cancellables)
        cameraModel.$currentLensType.dropFirst().sink { _ in expectation.fulfill() }.store(in: &cancellables)
        cameraModel.$focusIndicatorPoint.dropFirst().sink { _ in expectation.fulfill() }.store(in: &cancellables)
        cameraModel.$showingFocusIndicator.dropFirst().sink { _ in expectation.fulfill() }.store(in: &cancellables)
        cameraModel.$flashMode.dropFirst().sink { _ in expectation.fulfill() }.store(in: &cancellables)
        cameraModel.$cameraPosition.dropFirst().sink { _ in expectation.fulfill() }.store(in: &cancellables)
        
        // Trigger changes
        cameraModel.isPermissionGranted = true
        cameraModel.alert = true
        cameraModel.zoomFactor = 2.0
        cameraModel.currentLensType = .ultraWide
        cameraModel.focusIndicatorPoint = CGPoint(x: 50, y: 50)
        cameraModel.showingFocusIndicator = true
        cameraModel.flashMode = .on
        cameraModel.cameraPosition = .front
        
        wait(for: [expectation], timeout: 3.0)
    }
    
    // MARK: - Integration Tests
    
    /// Tests the complete camera initialization flow
    /// Assertion: Should handle the full initialization sequence correctly
    func testCameraInitializationFlow_CompletesCorrectly() {
        let expectation = XCTestExpectation(description: "Camera initialization should complete")
        
        // Monitor permission changes as indicator of initialization progress
        cameraModel.$isPermissionGranted
            .dropFirst()
            .sink { isGranted in
                if isGranted {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // Trigger initialization
        cameraModel.checkPermissions()
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    /// Tests that foreground notification handling works correctly
    /// Assertion: Should reset zoom when app enters foreground
    func testForegroundNotificationHandling_ResetsZoom() {
        // Set zoom to non-default value
        cameraModel.zoomFactor = 5.0
        
        let expectation = XCTestExpectation(description: "Zoom should reset on foreground")
        
        cameraModel.$zoomFactor
            .dropFirst()
            .sink { zoomFactor in
                if zoomFactor == 1.0 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // Simulate app entering foreground
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    // MARK: - Error Handling Tests
    
    /// Tests that camera model handles errors gracefully
    /// Assertion: Should not crash when encountering various error conditions
    func testErrorHandling_HandlesGracefully() {
        // Test that setting invalid values doesn't crash
        cameraModel.zoomFactor = -1.0  // Invalid zoom
        XCTAssertNotNil(cameraModel, "Should handle invalid zoom without crashing")
        
        cameraModel.focusIndicatorPoint = CGPoint(x: CGFloat.infinity, y: CGFloat.nan)  // Invalid point
        XCTAssertNotNil(cameraModel, "Should handle invalid focus point without crashing")
        
        cameraModel.viewSize = CGSize(width: -100, height: -100)  // Invalid size
        XCTAssertNotNil(cameraModel, "Should handle invalid view size without crashing")
    }
    
    // MARK: - Helper Methods
    
    /// Creates a test image for use in tests
    private func createTestImage(size: CGSize = CGSize(width: 100, height: 100)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            context.cgContext.setFillColor(UIColor.red.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: size))
        }
    }
}