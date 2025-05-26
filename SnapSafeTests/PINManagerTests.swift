//
//  PINManagerTests.swift
//  SnapSafeTests
//
//  Created by Claude on 5/25/25.
//

import XCTest
import Combine
@testable import SnapSafe

/// Comprehensive test suite for PINManager
/// 
/// This test suite demonstrates various iOS testing patterns:
/// - Unit testing with XCTest
/// - Testing published properties with Combine
/// - Testing UserDefaults interactions
/// - Async testing with expectations
/// - Mock data and test isolation
class PINManagerTests: XCTestCase {
    
    // MARK: - Test Properties
    
    /// Reference to the PINManager instance under test
    var pinManager: PINManager!
    
    /// Test UserDefaults to isolate tests from real app data
    var testUserDefaults: UserDefaults!
    
    /// Combine subscriptions for testing published properties
    var cancellables: Set<AnyCancellable> = []
    
    // MARK: - Test Lifecycle
    
    /// Set up method called before each test method
    /// This ensures each test starts with a clean state
    override func setUp() {
        super.setUp()
        
        // Create a test-specific UserDefaults suite to avoid affecting real app data
        let suiteName = "PINManagerTests-\(UUID().uuidString)"
        testUserDefaults = UserDefaults(suiteName: suiteName)!
        
        // Clear any existing data in test defaults
        testUserDefaults.removePersistentDomain(forName: suiteName)
        
        // Note: We can't easily inject UserDefaults into PINManager due to singleton pattern
        // In a production app, we would refactor PINManager to accept UserDefaults as dependency
        pinManager = PINManager.shared
        
        // Clear any existing PIN state for testing and wait for async completion
        clearPINAndWait()
        
        // Reset requirePINOnResume to default value and wait for async completion
        resetRequirePINOnResumeAndWait()
        
        // Clear subscriptions
        cancellables.removeAll()
        
        print("Test setup completed - clean state established")
    }
    
    /// Helper method to clear PIN and wait for async update to complete
    private func clearPINAndWait() {
        let expectation = expectation(description: "PIN should be cleared")
        
        // If PIN is already not set, we're done
        if !pinManager.isPINSet {
            expectation.fulfill()
        } else {
            // Subscribe to changes and wait for isPINSet to become false
            pinManager.$isPINSet
                .dropFirst()
                .sink { isPINSet in
                    if !isPINSet {
                        expectation.fulfill()
                    }
                }
                .store(in: &cancellables)
        }
        
        // Clear the PIN
        pinManager.clearPIN()
        
        // Wait for async update
        wait(for: [expectation], timeout: 1.0)
        
        // Clear subscriptions after setup
        cancellables.removeAll()
    }
    
    /// Helper method to reset requirePINOnResume to default and wait for async update
    private func resetRequirePINOnResumeAndWait() {
        let expectation = expectation(description: "requirePINOnResume should be reset to true")
        
        // If already true, we're done
        if pinManager.requirePINOnResume {
            expectation.fulfill()
        } else {
            // Subscribe to changes and wait for requirePINOnResume to become true
            pinManager.$requirePINOnResume
                .dropFirst()
                .sink { requirePIN in
                    if requirePIN {
                        expectation.fulfill()
                    }
                }
                .store(in: &cancellables)
        }
        
        // Reset to default value
        pinManager.setRequirePINOnResume(true)
        
        // Wait for async update
        wait(for: [expectation], timeout: 1.0)
        
        // Clear subscriptions after setup
        cancellables.removeAll()
    }
    
    /// Tear down method called after each test method
    override func tearDown() {
        // Clean up subscriptions
        cancellables.removeAll()
        
        // Clear PIN state using our helper method to ensure async completion
        clearPINAndWait()
        
        // Reset requirePINOnResume to default value
        resetRequirePINOnResumeAndWait()
        
        // Clear any UserDefaults keys that might have been set
        UserDefaults.standard.removeObject(forKey: "snapSafe.userPIN")
        UserDefaults.standard.removeObject(forKey: "snapSafe.isPINSet")
        UserDefaults.standard.removeObject(forKey: "snapSafe.requirePINOnResume")
        
        pinManager = nil
        testUserDefaults = nil
        
        super.tearDown()
        print("Test teardown completed")
    }
    
    // MARK: - PIN Setting Tests
    
    /// Test that setting a PIN updates the isPINSet property
    func testSetPIN_UpdatesIsPINSetProperty() {
        // Given: Initial state should be false
        XCTAssertFalse(pinManager.isPINSet, "PIN should not be set initially")
        
        // Create expectation for async update
        let expectation = expectation(description: "isPINSet should be updated")
        
        // Subscribe to changes
        pinManager.$isPINSet
            .dropFirst() // Skip initial false value
            .sink { isPINSet in
                if isPINSet {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When: Setting a PIN
        let testPIN = "1234"
        pinManager.setPIN(testPIN)
        
        // Then: Wait for async update and verify
        waitForExpectations(timeout: 1.0) { error in
            XCTAssertNil(error, "Should not timeout waiting for isPINSet update")
        }
        
        XCTAssertTrue(pinManager.isPINSet, "PIN should be marked as set after setPIN is called")
    }
    
    /// Test PIN setting with various valid PIN formats
    func testSetPIN_WithVariousPINFormats() {
        let testPINs = ["1234", "0000", "9876", "1111"]
        
        for testPIN in testPINs {
            // When: Setting each PIN
            pinManager.setPIN(testPIN)
            
            // Wait for async update
            waitForPINSetUpdate(expectedValue: true)
            
            // Then: Should be marked as set and verifiable
            XCTAssertTrue(pinManager.isPINSet, "PIN \(testPIN) should be marked as set")
            XCTAssertTrue(pinManager.verifyPIN(testPIN), "PIN \(testPIN) should verify correctly")
            
            // Clean up for next iteration
            pinManager.clearPIN()
            waitForPINSetUpdate(expectedValue: false)
        }
    }
    
    /// Test that setting a PIN publishes changes to observers
    func testSetPIN_PublishesChangesToObservers() {
        // Given: Expectation for published property change
        let expectation = expectation(description: "isPINSet should be published")
        
        var receivedValues: [Bool] = []
        
        // Subscribe to isPINSet changes
        pinManager.$isPINSet
            .sink { isPINSet in
                receivedValues.append(isPINSet)
                if isPINSet {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When: Setting a PIN
        pinManager.setPIN("1234")
        
        // Then: Should receive published change
        waitForExpectations(timeout: 1.0) { error in
            XCTAssertNil(error, "Should not timeout waiting for published change")
        }
        
        XCTAssertTrue(receivedValues.contains(true), "Should have received isPINSet = true")
    }
    
    // MARK: - PIN Verification Tests
    
    /// Test PIN verification with correct PIN
    func testVerifyPIN_WithCorrectPIN_ReturnsTrue() {
        // Given: A PIN is set
        let testPIN = "1234"
        pinManager.setPIN(testPIN)
        
        // When: Verifying with correct PIN
        let result = pinManager.verifyPIN(testPIN)
        
        // Then: Should return true
        XCTAssertTrue(result, "Should return true when verifying correct PIN")
    }
    
    /// Test PIN verification with incorrect PIN
    func testVerifyPIN_WithIncorrectPIN_ReturnsFalse() {
        // Given: A PIN is set
        pinManager.setPIN("1234")
        
        // When: Verifying with incorrect PIN
        let result = pinManager.verifyPIN("5678")
        
        // Then: Should return false
        XCTAssertFalse(result, "Should return false when verifying incorrect PIN")
    }
    
    /// Test PIN verification when no PIN is set
    func testVerifyPIN_WhenNoPINSet_ReturnsFalse() {
        // Given: No PIN is set (initial state)
        XCTAssertFalse(pinManager.isPINSet, "No PIN should be set initially")
        
        // When: Attempting to verify any PIN
        let result = pinManager.verifyPIN("1234")
        
        // Then: Should return false
        XCTAssertFalse(result, "Should return false when no PIN is set")
    }
    
    /// Test PIN verification with edge cases
    func testVerifyPIN_EdgeCases() {
        // Test empty PIN
        pinManager.setPIN("")
        XCTAssertTrue(pinManager.verifyPIN(""), "Empty PIN should verify correctly")
        XCTAssertFalse(pinManager.verifyPIN("1234"), "Non-empty PIN should not match empty stored PIN")
        
        // Test PIN with spaces
        pinManager.setPIN(" 123 ")
        XCTAssertTrue(pinManager.verifyPIN(" 123 "), "PIN with spaces should verify correctly")
        XCTAssertFalse(pinManager.verifyPIN("123"), "PIN without spaces should not match PIN with spaces")
    }
    
    // MARK: - PIN Clearing Tests
    
    /// Test that clearing PIN resets the state
    func testClearPIN_ResetsState() {
        // Given: A PIN is set
        pinManager.setPIN("1234")
        waitForPINSetUpdate(expectedValue: true)
        XCTAssertTrue(pinManager.isPINSet, "PIN should be set initially")
        
        // When: Clearing the PIN
        pinManager.clearPIN()
        waitForPINSetUpdate(expectedValue: false)
        
        // Then: State should be reset
        XCTAssertFalse(pinManager.isPINSet, "PIN should not be set after clearing")
        XCTAssertFalse(pinManager.verifyPIN("1234"), "Old PIN should not verify after clearing")
    }
    
    /// Test that clearing PIN publishes changes
    func testClearPIN_PublishesChanges() {
        // Given: A PIN is set
        pinManager.setPIN("1234")
        waitForPINSetUpdate(expectedValue: true)
        
        let expectation = expectation(description: "isPINSet should be published as false")
        var finalValue: Bool?
        
        // Subscribe to changes AFTER the PIN is set, so dropFirst skips the current true value
        pinManager.$isPINSet
            .dropFirst() // Skip the current true value
            .sink { isPINSet in
                finalValue = isPINSet
                if !isPINSet { // Only fulfill when we get false
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When: Clearing the PIN
        pinManager.clearPIN()
        
        // Then: Should publish false
        waitForExpectations(timeout: 1.0) { error in
            XCTAssertNil(error, "Should not timeout waiting for published change")
        }
        
        XCTAssertEqual(finalValue, false, "Should have published isPINSet = false")
    }
    
    // MARK: - PIN Resume Requirement Tests
    
    /// Test setting requirePINOnResume flag
    func testSetRequirePINOnResume_UpdatesProperty() {
        // Given: Initial state (should be true by default)
        XCTAssertTrue(pinManager.requirePINOnResume, "Should require PIN on resume by default")
        
        // When: Setting to false
        pinManager.setRequirePINOnResume(false)
        waitForRequirePINOnResumeUpdate(expectedValue: false)
        
        // Then: Should be updated
        XCTAssertFalse(pinManager.requirePINOnResume, "Should not require PIN on resume after setting to false")
        
        // When: Setting back to true
        pinManager.setRequirePINOnResume(true)
        waitForRequirePINOnResumeUpdate(expectedValue: true)
        
        // Then: Should be updated again
        XCTAssertTrue(pinManager.requirePINOnResume, "Should require PIN on resume after setting to true")
    }
    
    /// Test that requirePINOnResume publishes changes
    func testSetRequirePINOnResume_PublishesChanges() {
        // Given: Ensure we start with a known stable state (true)
        XCTAssertTrue(pinManager.requirePINOnResume, "Should start with requirePINOnResume = true")
        
        let expectation = expectation(description: "requirePINOnResume should be published")
        var receivedValue: Bool?
        
        // Subscribe to requirePINOnResume changes AFTER confirming stable state
        pinManager.$requirePINOnResume
            .dropFirst() // Skip the current true value
            .sink { requirePIN in
                receivedValue = requirePIN
                if !requirePIN { // Only fulfill when we get false
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When: Changing the setting from true to false
        pinManager.setRequirePINOnResume(false)
        
        // Then: Should receive published change
        waitForExpectations(timeout: 1.0) { error in
            XCTAssertNil(error, "Should not timeout waiting for published change")
        }
        
        XCTAssertEqual(receivedValue, false, "Should have received requirePINOnResume = false")
    }
    
    // MARK: - Last Active Time Tests
    
    /// Test updating last active time
    func testUpdateLastActiveTime_UpdatesProperty() {
        // Given: Initial last active time
        let initialTime = pinManager.lastActiveTime
        
        // Wait a small amount to ensure time difference
        let expectation = expectation(description: "Wait for time to pass")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 0.1)
        
        // When: Updating last active time
        pinManager.updateLastActiveTime()
        
        // Then: Should be updated to a more recent time
        XCTAssertGreaterThan(pinManager.lastActiveTime, initialTime, "Last active time should be updated to a more recent time")
    }
    
    // MARK: - Integration Tests
    
    /// Test complete PIN lifecycle: set → verify → clear → verify
    func testCompletePINLifecycle() {
        let testPIN = "1234"
        
        // Initially no PIN
        XCTAssertFalse(pinManager.isPINSet)
        XCTAssertFalse(pinManager.verifyPIN(testPIN))
        
        // Set PIN
        pinManager.setPIN(testPIN)
        waitForPINSetUpdate(expectedValue: true)
        XCTAssertTrue(pinManager.isPINSet)
        XCTAssertTrue(pinManager.verifyPIN(testPIN))
        XCTAssertFalse(pinManager.verifyPIN("9999"))
        
        // Clear PIN
        pinManager.clearPIN()
        waitForPINSetUpdate(expectedValue: false)
        XCTAssertFalse(pinManager.isPINSet)
        XCTAssertFalse(pinManager.verifyPIN(testPIN))
    }
    
    /// Test multiple PIN changes
    func testMultiplePINChanges() {
        let pins = ["1111", "2222", "3333"]
        
        for (index, pin) in pins.enumerated() {
            // Set new PIN
            pinManager.setPIN(pin)
            waitForPINSetUpdate(expectedValue: true)
            
            // Verify current PIN works
            XCTAssertTrue(pinManager.verifyPIN(pin), "PIN \(pin) should verify correctly")
            
            // Verify previous PINs don't work
            for previousIndex in 0..<index {
                let previousPIN = pins[previousIndex]
                XCTAssertFalse(pinManager.verifyPIN(previousPIN), "Previous PIN \(previousPIN) should not verify after setting new PIN \(pin)")
            }
        }
    }
    
    // MARK: - Performance Tests
    
    /// Test PIN verification performance
    func testPINVerificationPerformance() {
        // Given: A PIN is set
        pinManager.setPIN("1234")
        waitForPINSetUpdate(expectedValue: true)
        
        // Measure performance of PIN verification
        measure {
            for _ in 0..<1000 {
                _ = pinManager.verifyPIN("1234")
            }
        }
    }
    
    // MARK: - UserDefaults Extension Tests
    
    /// Test UserDefaults extension for bool with default value
    func testUserDefaultsBoolExtension() {
        let testKey = "testBoolKey"
        
        // Test default value when key doesn't exist
        XCTAssertFalse(testUserDefaults.bool(forKey: testKey, defaultValue: false))
        XCTAssertTrue(testUserDefaults.bool(forKey: testKey, defaultValue: true))
        
        // Test actual value when key exists
        testUserDefaults.set(true, forKey: testKey)
        XCTAssertTrue(testUserDefaults.bool(forKey: testKey, defaultValue: false))
        
        testUserDefaults.set(false, forKey: testKey)
        XCTAssertFalse(testUserDefaults.bool(forKey: testKey, defaultValue: true))
    }
}

// MARK: - Test Helper Extensions

extension PINManagerTests {
    
    /// Helper method to wait for PIN set status changes
    /// This handles the async nature of isPINSet updates
    func waitForPINSetUpdate(expectedValue: Bool, timeout: TimeInterval = 1.0) {
        let expectation = expectation(description: "Wait for isPINSet = \(expectedValue)")
        
        pinManager.$isPINSet
            .first { $0 == expectedValue }
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        waitForExpectations(timeout: timeout) { error in
            if let error = error {
                XCTFail("Timeout waiting for isPINSet = \(expectedValue): \(error)")
            }
        }
    }
    
    /// Helper method to wait for requirePINOnResume status changes
    /// This handles the async nature of requirePINOnResume updates
    func waitForRequirePINOnResumeUpdate(expectedValue: Bool, timeout: TimeInterval = 1.0) {
        let expectation = expectation(description: "Wait for requirePINOnResume = \(expectedValue)")
        
        pinManager.$requirePINOnResume
            .first { $0 == expectedValue }
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        waitForExpectations(timeout: timeout) { error in
            if let error = error {
                XCTFail("Timeout waiting for requirePINOnResume = \(expectedValue): \(error)")
            }
        }
    }
    
    /// Helper method to wait for published property changes
    /// This is useful for testing @Published properties that update asynchronously
    func waitForPublishedChange<T: Equatable>(
        on publisher: Published<T>.Publisher,
        expectedValue: T,
        timeout: TimeInterval = 1.0,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let expectation = expectation(description: "Wait for published value change")
        
        publisher
            .first { $0 == expectedValue }
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        waitForExpectations(timeout: timeout) { error in
            if let error = error {
                XCTFail("Timeout waiting for published value \(expectedValue): \(error)", file: file, line: line)
            }
        }
    }
}
