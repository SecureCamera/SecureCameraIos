//
//  SnapSafeTests.swift
//  SnapSafeTests
//
//  Created by Bill Booth on 5/2/25.
//

@testable import SnapSafe
import XCTest

/// Basic test class to verify test target is working
class SnapSafeTests: XCTestCase {
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        XCTAssertTrue(true, "Basic test should pass")
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        measure {
            // Put the code you want to measure the time of here.
            let _ = Array(0 ... 1000).map { $0 * 2 }
        }
    }
}
