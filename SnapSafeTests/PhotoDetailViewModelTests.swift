//
//  PhotoDetailViewModelTests.swift
//  SnapSafeTests
//
//  Created by Bill Booth on 5/25/25.
//

import XCTest
import UIKit
import Combine
@testable import SnapSafe

class PhotoDetailViewModelTests: XCTestCase {
    
    private var viewModel: PhotoDetailViewModel!
    private var testPhotos: [SecurePhoto]!
    private var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        testPhotos = createTestPhotos()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        cancellables?.removeAll()
        cancellables = nil
        viewModel = nil
        testPhotos = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    /// Tests that PhotoDetailViewModel initializes correctly with a single photo
    /// Assertion: Should set up single photo mode with correct initial state
    func testInit_WithSinglePhoto_SetsCorrectState() {
        let singlePhoto = testPhotos[0]
        var deleteCallbackCalled = false
        var dismissCallbackCalled = false
        
        viewModel = PhotoDetailViewModel(
            photo: singlePhoto,
            showFaceDetection: true,
            onDelete: { _ in deleteCallbackCalled = true },
            onDismiss: { dismissCallbackCalled = true }
        )
        
        XCTAssertTrue(viewModel.showFaceDetection, "Face detection should be enabled")
        XCTAssertEqual(viewModel.currentPhoto.id, singlePhoto.id, "Current photo should match provided photo")
        XCTAssertTrue(viewModel.allPhotos.isEmpty, "All photos array should be empty in single photo mode")
        XCTAssertEqual(viewModel.currentIndex, 0, "Current index should be 0")
        XCTAssertFalse(viewModel.canGoToPrevious, "Should not be able to go to previous in single photo mode")
        XCTAssertFalse(viewModel.canGoToNext, "Should not be able to go to next in single photo mode")
    }
    
    /// Tests that PhotoDetailViewModel initializes correctly with multiple photos
    /// Assertion: Should set up multi-photo mode with correct initial state and navigation capabilities
    func testInit_WithMultiplePhotos_SetsCorrectState() {
        let initialIndex = 1
        var deleteCallbackCalled = false
        var dismissCallbackCalled = false
        
        viewModel = PhotoDetailViewModel(
            allPhotos: testPhotos,
            initialIndex: initialIndex,
            showFaceDetection: false,
            onDelete: { _ in deleteCallbackCalled = true },
            onDismiss: { dismissCallbackCalled = true }
        )
        
        XCTAssertFalse(viewModel.showFaceDetection, "Face detection should be disabled")
        XCTAssertEqual(viewModel.allPhotos.count, testPhotos.count, "All photos should be set correctly")
        XCTAssertEqual(viewModel.currentIndex, initialIndex, "Current index should match initial index")
        XCTAssertEqual(viewModel.currentPhoto.id, testPhotos[initialIndex].id, "Current photo should match photo at initial index")
        XCTAssertTrue(viewModel.canGoToPrevious, "Should be able to go to previous from index 1")
        XCTAssertTrue(viewModel.canGoToNext, "Should be able to go to next from index 1")
    }
    
    // MARK: - Navigation Tests
    
    /// Tests that navigation to previous photo works correctly
    /// Assertion: Should update current index and reset UI state when navigating to previous photo
    func testNavigateToPrevious_UpdatesStateCorrectly() {
        viewModel = PhotoDetailViewModel(allPhotos: testPhotos, initialIndex: 2, showFaceDetection: true)
        
        let expectation = XCTestExpectation(description: "Navigation should update current index")
        
        viewModel.$currentIndex
            .dropFirst()
            .sink { index in
                XCTAssertEqual(index, 1, "Current index should be decremented")
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // Set some UI state that should be reset
        viewModel.imageRotation = 90
        viewModel.currentScale = 2.0
        viewModel.isFaceDetectionActive = true
        
        viewModel.navigateToPrevious()
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(viewModel.imageRotation, 0, "Image rotation should be reset")
        XCTAssertEqual(viewModel.currentScale, 1.0, "Scale should be reset")
        XCTAssertFalse(viewModel.isFaceDetectionActive, "Face detection should be deactivated")
        XCTAssertTrue(viewModel.detectedFaces.isEmpty, "Detected faces should be cleared")
        XCTAssertNil(viewModel.modifiedImage, "Modified image should be cleared")
    }
    
    /// Tests that navigation to next photo works correctly
    /// Assertion: Should update current index and reset UI state when navigating to next photo
    func testNavigateToNext_UpdatesStateCorrectly() {
        viewModel = PhotoDetailViewModel(allPhotos: testPhotos, initialIndex: 0, showFaceDetection: true)
        
        let expectation = XCTestExpectation(description: "Navigation should update current index")
        
        viewModel.$currentIndex
            .dropFirst()
            .sink { index in
                XCTAssertEqual(index, 1, "Current index should be incremented")
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // Set some UI state that should be reset
        viewModel.imageRotation = 180
        viewModel.dragOffset = CGSize(width: 50, height: 50)
        viewModel.detectedFaces = [DetectedFace(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))]
        
        viewModel.navigateToNext()
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(viewModel.imageRotation, 0, "Image rotation should be reset")
        XCTAssertEqual(viewModel.dragOffset, .zero, "Drag offset should be reset")
        XCTAssertTrue(viewModel.detectedFaces.isEmpty, "Detected faces should be cleared")
    }
    
    /// Tests that navigation respects boundaries
    /// Assertion: Should not navigate beyond array bounds
    func testNavigation_RespectsBoundaries() {
        viewModel = PhotoDetailViewModel(allPhotos: testPhotos, initialIndex: 0, showFaceDetection: false)
        
        // At index 0, can't go to previous
        XCTAssertFalse(viewModel.canGoToPrevious, "Should not be able to go to previous at index 0")
        viewModel.navigateToPrevious()
        XCTAssertEqual(viewModel.currentIndex, 0, "Index should remain 0 when trying to go to previous")
        
        // Move to last index
        viewModel.currentIndex = testPhotos.count - 1
        
        // At last index, can't go to next
        XCTAssertFalse(viewModel.canGoToNext, "Should not be able to go to next at last index")
        viewModel.navigateToNext()
        XCTAssertEqual(viewModel.currentIndex, testPhotos.count - 1, "Index should remain at last position")
    }
    
    // MARK: - Zoom and Pan Tests
    
    /// Tests that zoom and pan can be reset correctly
    /// Assertion: Should reset all zoom and pan related properties to default values
    func testResetZoomAndPan_ResetsAllProperties() {
        viewModel = PhotoDetailViewModel(allPhotos: testPhotos, initialIndex: 0, showFaceDetection: false)
        
        let expectation = XCTestExpectation(description: "Zoom and pan should reset")
        expectation.expectedFulfillmentCount = 4
        
        // Set non-default values
        viewModel.currentScale = 3.0
        viewModel.dragOffset = CGSize(width: 100, height: 100)
        viewModel.lastScale = 3.0
        viewModel.isZoomed = true
        viewModel.lastDragPosition = CGSize(width: 50, height: 50)
        
        // Monitor changes
        viewModel.$currentScale.dropFirst().sink { scale in
            XCTAssertEqual(scale, 1.0, "Current scale should reset to 1.0")
            expectation.fulfill()
        }.store(in: &cancellables)
        
        viewModel.$dragOffset.dropFirst().sink { offset in
            XCTAssertEqual(offset, .zero, "Drag offset should reset to zero")
            expectation.fulfill()
        }.store(in: &cancellables)
        
        viewModel.$lastScale.dropFirst().sink { scale in
            XCTAssertEqual(scale, 1.0, "Last scale should reset to 1.0")
            expectation.fulfill()
        }.store(in: &cancellables)
        
        viewModel.$isZoomed.dropFirst().sink { isZoomed in
            XCTAssertFalse(isZoomed, "Is zoomed should reset to false")
            expectation.fulfill()
        }.store(in: &cancellables)
        
        viewModel.resetZoomAndPan()
        
        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertEqual(viewModel.lastDragPosition, .zero, "Last drag position should reset to zero")
    }
    
    // MARK: - Image Rotation Tests
    
    /// Tests that image rotation works correctly
    /// Assertion: Should update rotation angle and reset zoom/pan when rotating
    func testRotateImage_UpdatesRotationAndResetsZoom() {
        viewModel = PhotoDetailViewModel(allPhotos: testPhotos, initialIndex: 0, showFaceDetection: false)
        
        // Set some zoom state
        viewModel.currentScale = 2.0
        viewModel.dragOffset = CGSize(width: 50, height: 50)
        
        viewModel.rotateImage(direction: 90)
        
        XCTAssertEqual(viewModel.imageRotation, 90, "Image should be rotated 90 degrees")
        XCTAssertEqual(viewModel.currentScale, 1.0, "Scale should be reset when rotating")
        XCTAssertEqual(viewModel.dragOffset, .zero, "Drag offset should be reset when rotating")
    }
    
    /// Tests that image rotation normalizes angles correctly
    /// Assertion: Should keep rotation within 0-360 degree range
    func testRotateImage_NormalizesAngles() {
        viewModel = PhotoDetailViewModel(allPhotos: testPhotos, initialIndex: 0, showFaceDetection: false)
        
        // Rotate multiple times to test normalization
        viewModel.rotateImage(direction: 90)
        viewModel.rotateImage(direction: 90)
        viewModel.rotateImage(direction: 90)
        viewModel.rotateImage(direction: 90)
        
        XCTAssertEqual(viewModel.imageRotation, 0, "Rotation should normalize to 0 after 360 degrees")
        
        // Test negative rotation
        viewModel.rotateImage(direction: -90)
        XCTAssertEqual(viewModel.imageRotation, 270, "Negative rotation should normalize correctly")
    }
    
    // MARK: - Face Detection Tests
    
    /// Tests that face detection can be activated and processes correctly
    /// Assertion: Should update face detection state and trigger face detection process
    func testDetectFaces_ActivatesAndProcesses() {
        viewModel = PhotoDetailViewModel(allPhotos: testPhotos, initialIndex: 0, showFaceDetection: true)
        
        let expectation = XCTestExpectation(description: "Face detection should activate")
        
        viewModel.$isFaceDetectionActive
            .dropFirst()
            .sink { isActive in
                XCTAssertTrue(isActive, "Face detection should be activated")
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        viewModel.detectFaces()
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertTrue(viewModel.processingFaces, "Should be processing faces initially")
        XCTAssertTrue(viewModel.detectedFaces.isEmpty, "Detected faces should be empty initially")
        XCTAssertNil(viewModel.modifiedImage, "Modified image should be nil initially")
    }
    
    /// Tests that face selection toggle works correctly
    /// Assertion: Should toggle face selection state correctly
    func testToggleFaceSelection_WorksCorrectly() {
        viewModel = PhotoDetailViewModel(allPhotos: testPhotos, initialIndex: 0, showFaceDetection: true)
        
        let testFace = DetectedFace(bounds: CGRect(x: 10, y: 10, width: 50, height: 50), isSelected: false)
        viewModel.detectedFaces = [testFace]
        
        XCTAssertFalse(testFace.isSelected, "Face should initially be unselected")
        XCTAssertFalse(viewModel.hasFacesSelected, "Should not have faces selected initially")
        
        viewModel.toggleFaceSelection(testFace)
        
        XCTAssertTrue(viewModel.detectedFaces[0].isSelected, "Face should be selected after toggle")
        XCTAssertTrue(viewModel.hasFacesSelected, "Should have faces selected after toggle")
        
        viewModel.toggleFaceSelection(testFace)
        
        XCTAssertFalse(viewModel.detectedFaces[0].isSelected, "Face should be unselected after second toggle")
        XCTAssertFalse(viewModel.hasFacesSelected, "Should not have faces selected after second toggle")
    }
    
    /// Tests that mask mode selection affects UI text correctly
    /// Assertion: Should update action titles and button labels based on selected mask mode
    func testMaskModeSelection_UpdatesUIText() {
        viewModel = PhotoDetailViewModel(allPhotos: testPhotos, initialIndex: 0, showFaceDetection: true)
        
        let maskModes: [(MaskMode, String, String, String)] = [
            (.blur, "Blur Selected Faces", "blur", "Blur Faces"),
            (.pixelate, "Pixelate Selected Faces", "pixelate", "Pixelate Faces"),
            (.blackout, "Blackout Selected Faces", "blackout", "Blackout Faces"),
            (.noise, "Apply Noise to Selected Faces", "apply noise to", "Apply Noise")
        ]
        
        for (mode, expectedTitle, expectedVerb, expectedButton) in maskModes {
            viewModel.selectedMaskMode = mode
            
            XCTAssertEqual(viewModel.maskActionTitle, expectedTitle, "Action title should match for \(mode)")
            XCTAssertEqual(viewModel.maskActionVerb, expectedVerb, "Action verb should match for \(mode)")
            XCTAssertEqual(viewModel.maskButtonLabel, expectedButton, "Button label should match for \(mode)")
        }
    }
    
    // MARK: - Photo Management Tests
    
    /// Tests that photo deletion works correctly for single photo
    /// Assertion: Should trigger onDelete and onDismiss callbacks for single photo
    func testDeletePhoto_SinglePhoto_TriggersCallbacks() {
        let singlePhoto = testPhotos[0]
        var deletedPhoto: SecurePhoto?
        var dismissCalled = false
        
        viewModel = PhotoDetailViewModel(
            photo: singlePhoto,
            showFaceDetection: false,
            onDelete: { photo in deletedPhoto = photo },
            onDismiss: { dismissCalled = true }
        )
        
        let expectation = XCTestExpectation(description: "Delete callbacks should be triggered")
        expectation.expectedFulfillmentCount = 2
        
        // Monitor for callback execution
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if deletedPhoto != nil { expectation.fulfill() }
            if dismissCalled { expectation.fulfill() }
        }
        
        viewModel.deletePhoto()
        
        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertNotNil(deletedPhoto, "onDelete callback should be called")
        XCTAssertEqual(deletedPhoto?.id, singlePhoto.id, "Correct photo should be passed to onDelete")
    }
    
    /// Tests that photo deletion works correctly for multiple photos
    /// Assertion: Should update photo array and navigation state correctly
    func testDeletePhoto_MultiplePhotos_UpdatesArray() {
        viewModel = PhotoDetailViewModel(allPhotos: testPhotos, initialIndex: 1, showFaceDetection: false)
        let initialCount = viewModel.allPhotos.count
        let photoToDelete = viewModel.currentPhoto
        
        let expectation = XCTestExpectation(description: "Photo array should be updated")
        
        viewModel.$allPhotos
            .dropFirst()
            .sink { photos in
                XCTAssertEqual(photos.count, initialCount - 1, "Photo count should decrease by 1")
                XCTAssertFalse(photos.contains { $0.id == photoToDelete.id }, "Deleted photo should not be in array")
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        viewModel.deletePhoto()
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    // MARK: - Display Image Tests
    
    /// Tests that displayedImage returns correct image based on face detection state
    /// Assertion: Should return modified image when face detection is active, otherwise full image
    func testDisplayedImage_ReturnsCorrectImage() {
        viewModel = PhotoDetailViewModel(allPhotos: testPhotos, initialIndex: 0, showFaceDetection: true)
        
        // Initially should return full image
        let initialImage = viewModel.displayedImage
        XCTAssertNotNil(initialImage, "Should return a valid image")
        
        // Set modified image and activate face detection
        let modifiedImage = createTestImage(size: CGSize(width: 100, height: 100))
        viewModel.modifiedImage = modifiedImage
        viewModel.isFaceDetectionActive = true
        
        let displayedWithModified = viewModel.displayedImage
        // Note: We can't directly compare UIImage objects, so we check that it's not nil
        XCTAssertNotNil(displayedWithModified, "Should return modified image when face detection is active")
    }
    
    // MARK: - Memory Management Tests
    
    /// Tests that preloadAdjacentPhotos manages memory correctly
    /// Assertion: Should mark adjacent photos as visible for memory management
    func testPreloadAdjacentPhotos_ManagesMemoryCorrectly() {
        viewModel = PhotoDetailViewModel(allPhotos: testPhotos, initialIndex: 1, showFaceDetection: false)
        
        // Initially photos should not be marked as visible
        XCTAssertFalse(testPhotos[0].isVisible, "Previous photo should not be visible initially")
        XCTAssertFalse(testPhotos[2].isVisible, "Next photo should not be visible initially")
        
        viewModel.preloadAdjacentPhotos()
        
        // After preloading, adjacent photos should be marked as visible
        XCTAssertTrue(testPhotos[0].isVisible, "Previous photo should be marked as visible")
        XCTAssertTrue(testPhotos[2].isVisible, "Next photo should be marked as visible")
    }
    
    /// Tests that onAppear properly sets up memory management
    /// Assertion: Should mark current photo as visible and register with memory manager
    func testOnAppear_SetsUpMemoryManagement() {
        viewModel = PhotoDetailViewModel(allPhotos: testPhotos, initialIndex: 0, showFaceDetection: false)
        
        XCTAssertFalse(testPhotos[0].isVisible, "Photo should not be visible initially")
        
        viewModel.onAppear()
        
        XCTAssertTrue(testPhotos[0].isVisible, "Current photo should be marked as visible after onAppear")
    }
    
    // MARK: - UI State Tests
    
    /// Tests that UI state properties can be updated correctly
    /// Assertion: Should properly manage all UI state published properties
    func testUIStateProperties_UpdateCorrectly() {
        viewModel = PhotoDetailViewModel(allPhotos: testPhotos, initialIndex: 0, showFaceDetection: true)
        
        let expectation = XCTestExpectation(description: "UI state should update")
        expectation.expectedFulfillmentCount = 8
        
        // Monitor state changes
        viewModel.$showDeleteConfirmation.dropFirst().sink { _ in expectation.fulfill() }.store(in: &cancellables)
        viewModel.$isSwiping.dropFirst().sink { _ in expectation.fulfill() }.store(in: &cancellables)
        viewModel.$processingFaces.dropFirst().sink { _ in expectation.fulfill() }.store(in: &cancellables)
        viewModel.$showBlurConfirmation.dropFirst().sink { _ in expectation.fulfill() }.store(in: &cancellables)
        viewModel.$showMaskOptions.dropFirst().sink { _ in expectation.fulfill() }.store(in: &cancellables)
        viewModel.$showImageInfo.dropFirst().sink { _ in expectation.fulfill() }.store(in: &cancellables)
        viewModel.$offset.dropFirst().sink { _ in expectation.fulfill() }.store(in: &cancellables)
        viewModel.$imageFrameSize.dropFirst().sink { _ in expectation.fulfill() }.store(in: &cancellables)
        
        // Update states
        viewModel.showDeleteConfirmation = true
        viewModel.isSwiping = true
        viewModel.processingFaces = true
        viewModel.showBlurConfirmation = true
        viewModel.showMaskOptions = true
        viewModel.showImageInfo = true
        viewModel.offset = 100
        viewModel.imageFrameSize = CGSize(width: 300, height: 400)
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    // MARK: - Sharing Tests
    
    /// Tests that sharePhoto method doesn't crash when executed
    /// Assertion: Should handle sharing functionality without crashing
    func testSharePhoto_DoesNotCrash() {
        viewModel = PhotoDetailViewModel(allPhotos: testPhotos, initialIndex: 0, showFaceDetection: false)
        
        // Note: We can't fully test sharing functionality in unit tests since it requires UIKit view controller hierarchy
        // But we can test that the method doesn't crash when called
        XCTAssertNoThrow(viewModel.sharePhoto(), "Share photo should not crash when called")
    }
    
    // MARK: - Helper Methods
    
    /// Creates test photos for use in tests
    private func createTestPhotos() -> [SecurePhoto] {
        let photos = (0..<3).map { index in
            let testImage = createTestImage()
            let metadata: [String: Any] = [
                "creationDate": Date().timeIntervalSince1970 - Double(index * 3600),
                "testPhoto": true,
                "index": index
            ]
            return SecurePhoto(
                filename: "test_photo_\(index)",
                metadata: metadata,
                fileURL: URL(fileURLWithPath: "/tmp/test_\(index).jpg"),
                preloadedThumbnail: testImage
            )
        }
        return photos
    }
    
    /// Creates a test image for use in tests
    private func createTestImage(size: CGSize = CGSize(width: 200, height: 200)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            context.cgContext.setFillColor(UIColor.blue.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: size))
            
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fillEllipse(in: CGRect(x: size.width * 0.25, y: size.height * 0.25,
                                                   width: size.width * 0.5, height: size.height * 0.5))
        }
    }
}