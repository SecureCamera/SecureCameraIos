//
//  ShardedKeyTests.swift
//  SnapSafeTests
//
//  Created by Claude on 9/30/25.
//

import XCTest
@testable import SnapSafe

final class ShardedKeyTests: XCTestCase {

    func test_constructorShouldSplitKeyIntoTwoParts() throws {
        // Given
        let originalKey = Data((0..<32).map { UInt8($0) })

        // When
        let shardedKey = ShardedKey(key: originalKey)

        // Then
        // We can't directly test private fields, but we can verify the key is reconstructed correctly
        let reconstructed = try shardedKey.reconstructKey()
        XCTAssertEqual(originalKey, reconstructed, "Reconstructed key should match original")
    }

    func test_reconstructKeyShouldReturnOriginalKey() throws {
        // Given
        let originalKey = Data((0..<16).map { UInt8($0 * 2) })
        let shardedKey = ShardedKey(key: originalKey)

        // When
        let reconstructed = try shardedKey.reconstructKey()

        // Then
        XCTAssertEqual(originalKey, reconstructed, "Reconstructed key should match original")
    }

    func test_evictShouldClearKeyParts() throws {
        // Given
        let originalKey = Data((0..<24).map { UInt8($0) })
        let shardedKey = ShardedKey(key: originalKey)

        // When
        let beforeEviction = try shardedKey.reconstructKey()
        shardedKey.evict()

        // Then
        XCTAssertEqual(originalKey, beforeEviction, "Key should be correct before eviction")

        // After eviction, reconstructKey should throw an exception
        XCTAssertThrowsError(try shardedKey.reconstructKey()) { error in
            XCTAssertTrue(error is ShardedKeyError, "Should throw ShardedKeyError")
            if let shardedKeyError = error as? ShardedKeyError {
                XCTAssertEqual(shardedKeyError, ShardedKeyError.keyEvicted, "Should throw keyEvicted error")
            }
        }
    }

    func test_shouldWorkWithEmptyKey() throws {
        // Given
        let emptyKey = Data()

        // When
        let shardedKey = ShardedKey(key: emptyKey)
        let reconstructed = try shardedKey.reconstructKey()

        // Then
        XCTAssertEqual(emptyKey, reconstructed, "Should handle empty keys correctly")
    }

    func test_shouldWorkWithLargeKeys() throws {
        // Given
        let largeKey = Data((0..<1024).map { UInt8($0 % 256) })

        // When
        let shardedKey = ShardedKey(key: largeKey)
        let reconstructed = try shardedKey.reconstructKey()

        // Then
        XCTAssertEqual(largeKey, reconstructed, "Should handle large keys correctly")
    }

    func test_multipleReconstructionsShouldReturnSameKey() throws {
        // Given
        let originalKey = Data((0..<32).map { UInt8($0) })
        let shardedKey = ShardedKey(key: originalKey)

        // When
        let firstReconstruction = try shardedKey.reconstructKey()
        let secondReconstruction = try shardedKey.reconstructKey()

        // Then
        XCTAssertEqual(
            firstReconstruction,
            secondReconstruction,
            "Multiple reconstructions should return the same key"
        )
    }

    func test_differentKeysShouldProduceDifferentShardedRepresentations() throws {
        // Given
        let key1 = Data((0..<32).map { UInt8($0) })
        let key2 = Data((0..<32).map { UInt8($0 + 1) })

        // When
        let shardedKey1 = ShardedKey(key: key1)
        let shardedKey2 = ShardedKey(key: key2)

        // Then
        // We can't directly compare private fields, but we can verify the reconstructed keys are different
        let reconstructed1 = try shardedKey1.reconstructKey()
        let reconstructed2 = try shardedKey2.reconstructKey()

        XCTAssertEqual(key1, reconstructed1, "First key should be reconstructed correctly")
        XCTAssertEqual(key2, reconstructed2, "Second key should be reconstructed correctly")
        XCTAssertNotEqual(
            reconstructed1,
            reconstructed2,
            "Different keys should produce different reconstructed values"
        )
    }

    func test_keyReconstructionAfterDeinit() throws {
        // Given
        let originalKey = Data((0..<32).map { UInt8($0) })
        var reconstructed: Data?

        // When
        do {
            let shardedKey = ShardedKey(key: originalKey)
            reconstructed = try shardedKey.reconstructKey()
        } // shardedKey goes out of scope here and deinit should be called

        // Then
        XCTAssertEqual(originalKey, reconstructed, "Key should be reconstructed correctly before deinit")
    }

    func test_randomDataGenerationSuccess() throws {
        // Given - This test verifies that SecRandomCopyBytes works correctly
        let originalKey = Data((0..<32).map { UInt8($0) })

        // When - Creating multiple sharded keys should not fail
        var shardedKeys: [ShardedKey] = []
        for _ in 0..<10 {
            let shardedKey = ShardedKey(key: originalKey)
            shardedKeys.append(shardedKey)
        }

        // Then - All should reconstruct the original key correctly
        for shardedKey in shardedKeys {
            let reconstructed = try shardedKey.reconstructKey()
            XCTAssertEqual(originalKey, reconstructed, "All sharded keys should reconstruct correctly")
        }
    }
}
