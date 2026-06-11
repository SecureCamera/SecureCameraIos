//
//  TestUtils.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/4/25.
//


import XCTest
import SnapSafe
import Combine

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

final class TestClock: Clock {
    private var _fixed: Date
    private var _monotonic: TimeInterval

    init(_ start: Date = Date(timeIntervalSince1970: 1)) {
        self._fixed = start
        self._monotonic = 0
    }

    var fixed: Date {
        get { _fixed }
        set {
            _monotonic += newValue.timeIntervalSince(_fixed)
            _fixed = newValue
        }
    }

    var now: Date { _fixed }
    var monotonicNow: TimeInterval { _monotonic }

    func advance(by seconds: TimeInterval) {
        _fixed.addTimeInterval(seconds)
        _monotonic += seconds
    }

    func advanceWallOnly(by seconds: TimeInterval) {
        _fixed.addTimeInterval(seconds)
    }

    func advanceMonotonicOnly(by seconds: TimeInterval) {
        _monotonic += seconds
    }
}

extension Publisher where Failure == Never {
    func firstValue(timeout: TimeInterval = 1.0) -> Output {
        let exp = XCTestExpectation(description: "Await first publisher value")
        var result: Output!
        let cancellable = self.first().sink { value in
            result = value
            exp.fulfill()
        }
        let waiter = XCTWaiter()
        _ = waiter.wait(for: [exp], timeout: timeout)
        _ = cancellable // keep alive
        return result
    }
}

// MARK: - UserDefaults Testing Helpers

extension UserDefaults {
    /// Creates an in-memory UserDefaults instance for testing
    /// Each call creates a fresh, isolated instance with no persistent storage
    static func inMemoryForTesting() -> UserDefaults {
        // Create a unique suite name using a UUID to ensure isolation
        let suiteName = "test-suite-\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        
        // Clear any existing data (shouldn't be any, but just to be safe)
        userDefaults.removePersistentDomain(forName: suiteName)
        
        return userDefaults
    }
}
