//
//  SnapSafeUITestsLaunchTests.swift
//  SnapSafeUITests
//
//  Created by Bill Booth on 10/12/25.
//

import XCTest

final class SnapSafeUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    nonisolated(unsafe) private static var savedAppearance: XCUIDevice.Appearance = .light

    override class func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            savedAppearance = XCUIDevice.shared.appearance
        }
    }

    override class func tearDown() {
        MainActor.assumeIsolated {
            XCUIDevice.shared.appearance = savedAppearance
        }
        super.tearDown()
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
