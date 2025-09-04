//
//  TestUtils.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/4/25.
//


import XCTest

func XCTAssertFalseAsync(
    _ expression: @autoclosure () async throws -> Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async rethrows {
    let value = try await expression()
    XCTAssertFalse(value, message(), file: file, line: line)
}

func XCTAssertTrueAsync(
    _ expression: @autoclosure () async throws -> Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async rethrows {
    let value = try await expression()
    XCTAssertTrue(value, message(), file: file, line: line)
}
