//
//  SnapSafeScreenshotTests.swift
//  SnapSafeUITests
//
//  Created by Claude on 10/13/25.
//

import XCTest

final class SnapSafeScreenshotTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()

        // Launch arguments to configure the app for UI testing
        app.launchArguments += ["-UITesting"]

        // Set language and locale for consistent screenshots
        app.launchArguments += ["-AppleLanguages", "(en)"]
        app.launchArguments += ["-AppleLocale", "en_US"]
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Screenshot Tests

    @MainActor
    func testGenerateScreenshots() throws {
        setupSnapshot(app)
        app.launch()

        // Wait for app to appear
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should launch")

        // Just take a simple screenshot of whatever screen appears
        snapshot("01-Launch-Screen")

        // This is a simplified version - we'll expand it once it works
        XCTAssertTrue(app.descendants(matching: .any).count > 0, "App should display content")
    }

    // MARK: - Individual Screen Tests
    // These can be run separately to test specific screens

    // Disabled - requires implementing -ResetOnboarding launch argument
    // @MainActor
    // func testWelcomeScreenOnly() throws {
    //     // Useful for testing just the onboarding/welcome screen
    //     setupSnapshot(app)
    //     app.launchArguments += ["-ResetOnboarding"]  // Custom launch arg to reset state
    //     app.launch()
    //     sleep(2)
    //
    //     snapshot("Welcome-Screen")
    //
    //     XCTAssertTrue(app.descendants(matching: .any).count > 0, "App should display content")
    // }

    @MainActor
    func testCameraScreenOnly() throws {
        // Useful for testing just the camera screen
        setupSnapshot(app)
        app.launch()

        // Wait for app to appear
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should launch")

        snapshot("Camera-Screen")

        // Verify app has content
        XCTAssertTrue(app.descendants(matching: .any).count > 0, "App should display content")
    }

}
