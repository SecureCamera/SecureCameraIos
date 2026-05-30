//
//  FakeEncryptionScheme.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/7/25.
//

import Foundation
@testable import SnapSafe

final class FakeEncryptionScheme: EncryptionScheme {
    var encryptToFileCalled = false
    var encryptWithKeyDataCalled = false
    var decryptFileCalled = false
    var evictKeyCalled = false
    var decryptResult: Data = Data()
    
    func encryptToFile(plain: Data, targetFile: URL) async throws {
        encryptToFileCalled = true
        // Write the plain data to the file for testing
        try plain.write(to: targetFile)
    }
    
    func encryptToFile(plain: Data, keyBytes: Data, targetFile: URL) async throws {
        encryptWithKeyDataCalled = true
        // Write the plain data to the file for testing
        try plain.write(to: targetFile)
    }
    
    func encrypt(plain: Data, keyBytes: Data) async throws -> Data {
        return plain // Return plain data for testing
    }
    
    func encryptWithKeyAlias(plain: Data, keyAlias: String) async throws -> Data {
        return plain // Return plain data for testing
    }
    
    func decryptWithKeyAlias(encrypted: Data, keyAlias: String) async throws -> Data {
        return encrypted // Return encrypted data for testing
    }
    
    func decryptFile(_ encryptedFile: URL) async throws -> Data {
        decryptFileCalled = true
        return decryptResult
    }
    
    func deriveAndCacheKey(plainPin: String, hashedPin: HashedPin) async throws {
        // No-op for testing
    }
    
    func getDerivedKey() async throws -> Data {
        return Data(count: 32) // Return dummy key
    }
    
    func deriveKey(plainPin: String, hashedPin: HashedPin) async throws -> Data {
        return Data(count: 32) // Return dummy key
    }
    
    func evictKey() {
        evictKeyCalled = true
    }
    
    func createKey(plainPin: String, hashedPin: HashedPin) async throws {
        // No-op for testing
    }
    
    func securityFailureReset() async {
        // No-op for testing
    }
    
    func activatePoisonPill(oldPin: HashedPin?) {
        // No-op for testing
    }
}
