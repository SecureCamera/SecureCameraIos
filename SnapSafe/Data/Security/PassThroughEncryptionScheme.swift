//
//  PassThroughEncryptionScheme.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/2/25.
//

import Foundation

final class PassThroughEncryptionScheme: EncryptionScheme {
    private var cachedKey: Data?
    
    func encryptToFile(plain: Data, targetFile: URL) async throws {
        try plain.write(to: targetFile)
    }
    
    func encryptToFile(plain: Data, keyBytes: Data, targetFile: URL) async throws {
        try plain.write(to: targetFile)
    }
    
    func encrypt(plain: Data, keyBytes: Data) async throws -> Data {
        return plain
    }
    
    func encryptWithKeyAlias(plain: Data, keyAlias: String) async throws -> Data {
        return plain
    }
    
    func decryptWithKeyAlias(encrypted: Data, keyAlias: String) async throws -> Data {
        return encrypted
    }
    
    func decryptFile(_ encryptedFile: URL) async throws -> Data {
        return try Data(contentsOf: encryptedFile)
    }
    
    func deriveAndCacheKey(plainPin: String, hashedPin: HashedPin) async throws {
        cachedKey = plainPin.data(using: .utf8)
    }
    
    func getDerivedKey() async throws -> Data {
        guard let cachedKey else {
            throw NSError(domain: "PassThroughEncryptionScheme", code: 1, userInfo: [NSLocalizedDescriptionKey: "No key cached"])
        }
        return cachedKey
    }
    
    func deriveKey(plainPin: String, hashedPin: HashedPin) async throws -> Data {
        return plainPin.data(using: .utf8) ?? Data()
    }
    
    func evictKey() {
        cachedKey = nil
    }
    
    func createKey(plainPin: String, hashedPin: HashedPin) async throws {
        cachedKey = plainPin.data(using: .utf8)
    }
    
    func securityFailureReset() async throws {
        cachedKey = nil
    }
    
    func activatePoisonPill(oldPin: HashedPin?) {
        cachedKey = nil
    }
}
