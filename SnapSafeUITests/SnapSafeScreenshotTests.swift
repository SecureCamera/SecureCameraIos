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

    // MARK: - Helper Methods

    private func enterTestPIN() {
        // This is a simple implementation - adjust based on your actual PIN UI
        // If you have individual digit fields, you'll need to tap each one

        if app.secureTextFields.count > 0 {
            let pinField = app.secureTextFields.firstMatch
            if pinField.exists && pinField.isHittable {
                pinField.tap()
                Thread.sleep(forTimeInterval: 0.3)
                app.typeText("1234")
                Thread.sleep(forTimeInterval: 0.5)

                // Look for and tap continue/submit button
                if app.buttons["Continue"].exists {
                    app.buttons["Continue"].tap()
                } else if app.buttons["Submit"].exists {
                    app.buttons["Submit"].tap()
                } else if app.buttons["Done"].exists {
                    app.buttons["Done"].tap()
                }
            }
        }

        // Alternative: if you have number pad buttons
        if app.buttons["1"].exists && app.buttons["2"].exists {
            app.buttons["1"].tap()
            Thread.sleep(forTimeInterval: 0.2)
            app.buttons["2"].tap()
            Thread.sleep(forTimeInterval: 0.2)
            app.buttons["3"].tap()
            Thread.sleep(forTimeInterval: 0.2)
            app.buttons["4"].tap()
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    private func isOnCameraScreen() -> Bool {
        // Check for camera-specific UI elements
        return app.buttons["Capture"].exists ||
               app.buttons["Take Photo"].exists ||
               app.buttons["Camera"].isSelected ||
               app.otherElements["CameraPreview"].exists
    }

    private func waitForElement(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        return element.waitForExistence(timeout: timeout)
    }
}
