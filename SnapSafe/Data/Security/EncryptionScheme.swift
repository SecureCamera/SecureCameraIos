//
//  EncryptionScheme.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/2/25.
//

import Foundation
import Mockable

/// Encryption schemes used to encrypt and decrypt files.
/// You can provide concrete implementations, e.g. Software / Hardware.
@Mockable
public protocol EncryptionScheme {
    // MARK: - Encrypt to file (derived key in cache)
    /// Encrypts plaintext data and writes it to a file using the pre-derived key in cache.
    func encryptToFile(plain: Data, targetFile: URL) async throws

    // MARK: - Encrypt to file (explicit key)
    /// Encrypts plaintext using the provided key and writes the result to `targetFile`.
    func encryptToFile(plain: Data, keyBytes: Data, targetFile: URL) async throws

    // MARK: - Encrypt / Decrypt with explicit key or key alias
    /// Encrypts plaintext using the provided key bytes and returns the ciphertext.
    func encrypt(plain: Data, keyBytes: Data) async throws -> Data

    /// Encrypts plaintext using the provided key alias and returns the ciphertext.
    func encryptWithKeyAlias(plain: Data, keyAlias: String) async throws -> Data

    /// Decrypts ciphertext using the provided key alias and returns the plaintext bytes.
    func decryptWithKeyAlias(encrypted: Data, keyAlias: String) async throws -> Data

    // MARK: - File decryption (derived key in cache)
    /// Decrypts an encrypted file and returns the plaintext using the pre-derived key in memory.
    func decryptFile(_ encryptedFile: URL) async throws -> Data

    // MARK: - Key derivation & cache
    /// Derives an encryption key from the provided PIN, then caches it for later use.
    func deriveAndCacheKey(plainPin: String, hashedPin: HashedPin) async throws

    /// Returns the currently derived encryption key, or throws if none is cached.
    func getDerivedKey() async throws -> Data

    /// Derives (but does not necessarily cache) a key from the provided PIN.
    func deriveKey(plainPin: String, hashedPin: HashedPin) async throws -> Data

    /// Evicts any cached/derived key from memory.
    func evictKey()

    // MARK: - First-time key creation & resets
    /// First-time key creation bootstrap.
    func createKey(plainPin: String, hashedPin: HashedPin) async throws

    /// Wipes sensitive state (keys, caches, metadata) after a security failure.
    func securityFailureReset() async

    // MARK: - Poison Pill
    /// Activates a "poison pill" key path. `oldPin` may be used to validate/rotate.
    func activatePoisonPill(oldPin: HashedPin?)
}
