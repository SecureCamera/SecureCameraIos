//
//  ShardedKey.swift
//  SnapSafe
//
//  Created by Claude on 9/30/25.
//

import Foundation
import Security

/// Errors that can occur when working with ShardedKey
enum ShardedKeyError: Error, Equatable {
    case keyEvicted
}

/// A security-focused key storage class that splits a key into XOR'd parts
/// to prevent the original key from existing in memory in its complete form.
final class ShardedKey {
    private var part1: Data
    private var part2: Data
    private let keySize: Int
    private var isEvicted: Bool = false
    
    /// Initialize with a key to be sharded
    /// - Parameter key: The original key to split and protect
    init(key: Data) {
        self.keySize = key.count
        
        // Randomly size the storage array so it is not the exact length of an AES key
        let part1Size = keySize + Int.random(in: 3...155)
        self.part1 = Data(count: part1Size)
        
        // Fill part1 with cryptographically secure random data
        let result1 = self.part1.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, part1Size, bytes.baseAddress!)
        }
        guard result1 == errSecSuccess else {
            fatalError("Failed to generate secure random data for part1")
        }
        
        // Best effort to ensure the two key parts don't live next to each other in memory.
        // Simple spacer allocation between the two parts to encourage different memory locations
        let spacer = Data(count: Int.random(in: 512...1024))
        _ = spacer // Prevent optimization
        
        // Randomly size the storage array so it is not the exact length of an AES key
        let part2Size = keySize + Int.random(in: 5...111)
        self.part2 = Data(count: part2Size)
        
        // Fill part2 with random data first
        let result2 = self.part2.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, part2Size, bytes.baseAddress!)
        }
        guard result2 == errSecSuccess else {
            fatalError("Failed to generate secure random data for part2")
        }
        
        // Now fill the data part with our XOR'd key
        for i in 0..<key.count {
            part2[i] = key[i] ^ part1[i]
        }
    }
    
    /// Reconstructs the original key from its XOR-split parts.
    /// - Returns: The reconstructed original key
    /// - Throws: ShardedKeyError.keyEvicted if the key has been evicted
    func reconstructKey() throws -> Data {
        guard isEvicted != true else {
            throw ShardedKeyError.keyEvicted
        }

        var originalKey = Data(count: keySize)
        for i in 0..<keySize {
            originalKey[i] = part1[i] ^ part2[i]
        }
        return originalKey
    }
    
    /// Securely evicts the key parts from memory by zeroing them
    func evict() {
        // Zero the memory before releasing
        part1.withUnsafeMutableBytes { bytes in
            memset(bytes.baseAddress!, 0, bytes.count)
        }
        part2.withUnsafeMutableBytes { bytes in
            memset(bytes.baseAddress!, 0, bytes.count)
        }
        
        // Reassign to empty data to ensure references are cleared
        part1 = Data()
        part2 = Data()
        
        isEvicted = true
    }
    
    deinit {
        // Ensure keys are evicted when object is deallocated
        evict()
    }
}
