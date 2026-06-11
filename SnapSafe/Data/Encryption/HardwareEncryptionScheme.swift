//
//  HardwareEncryptionScheme.swift
//  SnapSafe
//
//  Created by Claude on 9/10/25.
//

import CommonCrypto
import CryptoKit
import Foundation
import Logging
import Security

// MARK: - KeyCache Actor for Thread-Safe Key Management
private actor KeyCache {
    private var shardedKey: ShardedKey?
    
    func hasKey() -> Bool {
        return shardedKey != nil
    }
    
    func getKey() -> Data? {
        return try! shardedKey?.reconstructKey()
    }
    
    func setKey(_ key: Data) {
        // Only set if not already cached (prevents duplicate work)
        if shardedKey == nil {
            shardedKey = ShardedKey(key: key)
        }
    }
    
    func evictKey() {
        // Securely evict the sharded key
        shardedKey?.evict()
        shardedKey = nil
    }
}

/// Hardware-backed encryption scheme that uses iOS Keychain and Secure Enclave for key protection
/// Similar to Android's HardwareBackedEncryptionScheme but without ephemeral key mode
final class HardwareEncryptionScheme: EncryptionScheme {
    
    // MARK: - Constants
    private static let defaultKeyAlias = "snapsafe_kek"
    private static let ivLengthBytes = 12  // 96-bit IV recommended for GCM
    private static let tagLengthBits = 128 // 128-bit tag appended automatically
    private static let dekFilenamePrefix = "dek"
    private static let dekDirectory = "keys"
    private static let defaultKeySize = 32 // 256-bit keys

    // MARK: - Dependencies
    private let deviceInfo: DeviceInfoDataSource
    private let keyCache = KeyCache()
    private let logger = Logger.encryption

    /// The hardware KEK alias. Injectable so tests can use an isolated alias and
    /// never touch the production `snapsafe_kek` in a shared (on-device) keychain.
    private let keyAlias: String

    // MARK: - Initialization
    init(deviceInfo: DeviceInfoDataSource, keyAlias: String = HardwareEncryptionScheme.defaultKeyAlias) {
        self.deviceInfo = deviceInfo
        self.keyAlias = keyAlias
    }
    
    // MARK: - EncryptionScheme Protocol Implementation
    
    func encryptToFile(plain: Data, targetFile: URL) async throws {
        let keyBytes = try await getDerivedKey()
        try await encryptToFile(plain: plain, keyBytes: keyBytes, targetFile: targetFile)
    }
    
    func encryptToFile(plain: Data, keyBytes: Data, targetFile: URL) async throws {
        let encrypted = try await encrypt(plain: plain, keyBytes: keyBytes)
        try encrypted.write(to: targetFile)
    }
    
    func encrypt(plain: Data, keyBytes: Data) async throws -> Data {
        let symmetricKey = SymmetricKey(data: keyBytes)
        let sealedBox = try AES.GCM.seal(plain, using: symmetricKey)
        
        // Format: IV + ciphertext + tag (compatible with Android format)
        var result = Data()
        result.append(sealedBox.nonce.withUnsafeBytes { Data($0) })
        result.append(sealedBox.ciphertext)
        result.append(sealedBox.tag)
        
        return result
    }
    
    func encryptWithKeyAlias(plain: Data, keyAlias: String) async throws -> Data {
        try createHardwareKeyIfNeeded(keyAlias: keyAlias)
        return try encryptWithHardwareKey(plain: plain, keyAlias: keyAlias)
    }
    
    func decryptWithKeyAlias(encrypted: Data, keyAlias: String) async throws -> Data {
        // Do NOT create a key on the decrypt path. If the key is missing or
        // inaccessible (e.g. a device migration drops the Secure-Enclave key, or the
        // keychain access group changed), surface the failure so callers can treat it
        // as a recoverable "secure key unavailable" state. Silently minting a new key
        // here permanently shadows the original and makes all existing ciphertext
        // undecryptable — the exact cause of the PIN-upgrade lockout.
        return try decryptWithHardwareKey(encrypted: encrypted, keyAlias: keyAlias)
    }
    
    func decryptFile(_ encryptedFile: URL) async throws -> Data {
        let encrypted = try Data(contentsOf: encryptedFile)
        let keyBytes = try await getDerivedKey()
        
        guard encrypted.count > Self.ivLengthBytes + (Self.tagLengthBits / 8) else {
            throw CryptoError.invalidCiphertext
        }
        
        // Extract components (IV + ciphertext + tag)
        let nonce = encrypted.prefix(Self.ivLengthBytes)
        let tagSize = Self.tagLengthBits / 8
        let ciphertext = encrypted.dropFirst(Self.ivLengthBytes).dropLast(tagSize)
        let tag = encrypted.suffix(tagSize)
        
        // Decrypt using AES-GCM
        let symmetricKey = SymmetricKey(data: keyBytes)
        let sealedBox = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce),
                                              ciphertext: ciphertext,
                                              tag: tag)
        
        return try AES.GCM.open(sealedBox, using: symmetricKey)
    }
    
    func deriveAndCacheKey(plainPin: String, hashedPin: HashedPin) async throws {
        // Check if key is already cached (fast path)
        if await keyCache.hasKey() {
            logger.debug("Key already cached, skipping derivation")
            return
        }
        
        logger.info("Key not cached, deriving key")
        
        // Derive key with timing
        let derivedKey = try await logger.logAsyncOperation("derive_and_cache_key") {
            try await deriveKey(plainPin: plainPin, hashedPin: hashedPin)
        }
        
        // Cache the derived key
        await keyCache.setKey(derivedKey)
        logger.info("Successfully derived and cached key")
    }
    
    func getDerivedKey() async throws -> Data {
        guard let cachedKey = await keyCache.getKey() else {
            logger.error("No key cached, and cannot get derived key")
            throw CryptoError.keyNotDerived
        }
        return cachedKey
    }
    
    func deriveKey(plainPin: String, hashedPin: HashedPin) async throws -> Data {
        return try await deriveWrappedKey(plainPin: plainPin, hashedPin: hashedPin)
    }
    
    func evictKey() async {
        await keyCache.evictKey()
    }
    
    func createKey(plainPin: String, hashedPin: HashedPin) async throws {
        try await logger.logAsyncOperation("create_key") {
            // Create hardware-backed KEK if it doesn't exist (outside of lock)
            if !hardwareKeyExists(keyAlias: self.keyAlias) {
                logger.info("Hardware key doesn't exist, creating new one", metadata: [
                    "key_alias": .string(self.keyAlias)
                ])
                try createHardwareKey(keyAlias: self.keyAlias)
            } else {
                logger.debug("Hardware key already exists", metadata: [
                    "key_alias": .string(self.keyAlias)
                ])
            }
            
            try await createWrappedKey(plainPin: plainPin, hashedPin: hashedPin)
        }
    }
    
    func securityFailureReset() async {
        logger.warning("Performing security failure reset")

        // 1. Evict any in-memory derived key. Must be awaited so the cache is
        //    guaranteed empty before reset returns — otherwise an attacker who
        //    triggered the reset by racing the device-lock state could observe
        //    the key still cached momentarily after reset.
        await evictKey()

        // 2. Delete hardware-backed key material (Secure Enclave / keychain).
        //    Without this, the EC keys (snapsafe_kek, pin_key, ...) survive
        //    reset and can decrypt any DEK that ever leaks via backup/extraction.
        let deletedKeyCount = deleteAllHardwareKeys()
        logger.info("Deleted hardware keys", metadata: [
            "count": .stringConvertible(deletedKeyCount)
        ])

        // 3. Delete all DEKs on disk
        let keyDir = getKeyDirectory()
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: keyDir, includingPropertiesForKeys: nil)
            let dekFiles = contents.filter { file in
                file.lastPathComponent.hasPrefix(Self.dekFilenamePrefix)
            }

            logger.info("Found DEK files to delete", metadata: [
                "file_count": .stringConvertible(dekFiles.count),
                "directory": .string(keyDir.lastPathComponent)
            ])

            for file in dekFiles {
                try FileManager.default.removeItem(at: file)
                logger.debug("Deleted DEK file", metadata: [
                    "file": .string(file.lastPathComponent)
                ])
            }

            logger.info("Security failure reset completed successfully", metadata: [
                "deleted_files": .stringConvertible(dekFiles.count)
            ])
        } catch {
            logger.error("Failed to reset security keys", metadata: [
                "error": .string(String(describing: error))
            ])
        }
    }

    /// Deletes every EC hardware key this app owns from the keychain.
    /// Returns the number of items deleted (or 0 on errSecItemNotFound).
    @discardableResult
    private func deleteAllHardwareKeys() -> Int {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom
        ]

        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess:
            return 1  // SecItemDelete does not report a count; report at least one
        case errSecItemNotFound:
            return 0
        default:
            logger.error("SecItemDelete failed during security reset", metadata: [
                "status": .stringConvertible(status)
            ])
            return 0
        }
    }
    
    func activatePoisonPill(oldPin: HashedPin?) {
        if let oldPin = oldPin {
            let dekFile = getDekFile(hashedPin: oldPin)
            try? FileManager.default.removeItem(at: dekFile)
        }
    }
}

// MARK: - Private Implementation
private extension HardwareEncryptionScheme {
    
    // MARK: - Key Derivation
    
    func deriveWrappedKey(plainPin: String, hashedPin: HashedPin) async throws -> Data {
        let dekFile = getDekFile(hashedPin: hashedPin)
        if !FileManager.default.fileExists(atPath: dekFile.path) {
            logger.info("DEK file not found, creating new key", metadata: [
                "file": .string(dekFile.lastPathComponent)
            ])
            try await createKey(plainPin: plainPin, hashedPin: hashedPin)
        } else {
            logger.debug("Loading existing DEK", metadata: [
                "file": .string(dekFile.lastPathComponent)
            ])
        }

        // 1. Remove the Secure Enclave wrap to recover the on-disk payload.
        let encryptedDek = try Data(contentsOf: dekFile)
        logger.logDataOperation("decrypt_dek", dataSize: encryptedDek.count)
        let payload = try decryptWithHardwareKey(encrypted: encryptedDek, keyAlias: self.keyAlias)

        // 2. Derive the PIN-wrap key. This is the cryptographic dependency that
        //    makes the PIN actually required to recover the DEK (C1).
        let pinKey = try await pinWrapKey(plainPin: plainPin, hashedPin: hashedPin)

        // 3a. Legacy migration: a payload that is exactly a raw DEK predates the
        //     PIN-wrap layer (the DEK was PBKDF2(PIN‖…) and only SE-wrapped).
        //     Preserve that exact DEK value — existing content depends on it —
        //     and re-wrap it under the PIN key, one shot.
        if PinDEKWrapper.isLegacyRawDEK(payload) {
            logger.info("Migrating legacy SE-only-wrapped DEK to PIN-wrapped form")
            try storeWrappedDEK(dek: payload, pinKey: pinKey, hashedPin: hashedPin)
            return payload
        }

        // 3b. Normal path: unwrap the PIN-wrapped payload. A wrong PIN fails the
        //     AES-GCM auth tag and surfaces as CryptoError.wrongPin.
        return try PinDEKWrapper.unwrap(payload: payload, pinKey: pinKey)
    }

    func createWrappedKey(plainPin: String, hashedPin: HashedPin) async throws {
        try await logger.logAsyncOperation("create_wrapped_key") {
            // The DEK is now a fresh random key, independent of the PIN. The PIN's
            // role moves entirely into the wrap layer (see pinWrapKey), so an
            // attacker who SE-unwraps the file still cannot recover the DEK
            // without the user typing the PIN.
            var dekBytes = Data(count: Self.defaultKeySize)
            let result = dekBytes.withUnsafeMutableBytes { bytes in
                SecRandomCopyBytes(kSecRandomDefault, Self.defaultKeySize, bytes.bindMemory(to: UInt8.self).baseAddress!)
            }
            guard result == errSecSuccess else {
                logger.error("Failed to generate random DEK", metadata: [
                    "sec_result": .stringConvertible(result)
                ])
                throw CryptoError.randomGenerationFailed
            }

            let pinKey = try await pinWrapKey(plainPin: plainPin, hashedPin: hashedPin)
            try storeWrappedDEK(dek: dekBytes, pinKey: pinKey, hashedPin: hashedPin)
        }
    }

    /// Derives the PIN-wrap key, binding the PIN to the per-credential salt and
    /// the device identifier.
    func pinWrapKey(plainPin: String, hashedPin: HashedPin) async throws -> SymmetricKey {
        guard let salt = Data(base64URLString: hashedPin.salt) else {
            throw CryptoError.keyDerivationFailed
        }
        let deviceId = await deviceInfo.getDeviceIdentifier()
        return try PinDEKWrapper.derivePinKey(plainPin: plainPin, salt: salt, deviceId: deviceId)
    }

    /// AES-GCM-wraps the DEK under the PIN key, then Secure-Enclave-wraps that
    /// payload and writes it to disk with complete file protection.
    func storeWrappedDEK(dek: Data, pinKey: SymmetricKey, hashedPin: HashedPin) throws {
        let pinWrapped = try PinDEKWrapper.wrap(dek: dek, pinKey: pinKey)
        let encryptedDek = try encryptWithHardwareKey(plain: pinWrapped, keyAlias: self.keyAlias)
        let dekFile = getDekFile(hashedPin: hashedPin)
        try encryptedDek.write(to: dekFile, options: [.completeFileProtection, .atomic])

        logger.info("Encrypted and stored PIN-wrapped DEK", metadata: [
            "file": .string(dekFile.lastPathComponent),
            "encrypted_size": .stringConvertible(encryptedDek.count)
        ])
    }
    
    // MARK: - Hardware Key Management
    
    func createHardwareKey(keyAlias: String) throws {
        try logger.logOperation("create_hardware_key") {
            logger.info("Creating hardware key", metadata: [
                "key_alias": .string(keyAlias)
            ])
            
            // First try with Secure Enclave
            do {
                logger.debug("Attempting Secure Enclave key generation")
                
                let accessControl = SecAccessControlCreateWithFlags(
                    kCFAllocatorDefault,
                    kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                    [.privateKeyUsage],
                    nil
                )
                
                let attributes: [String: Any] = [
                    kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                    kSecAttrKeySizeInBits as String: 256,
                    kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
                    kSecPrivateKeyAttrs as String: [
                        kSecAttrIsPermanent as String: true,
                        kSecAttrApplicationTag as String: keyAlias.data(using: .utf8)!,
                        kSecAttrAccessControl as String: accessControl as Any
                    ]
                ]
                
                var error: Unmanaged<CFError>?
                guard let _ = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
                    if let error = error?.takeRetainedValue() {
                        let errorDesc = CFErrorCopyDescription(error) as String? ?? "Unknown error"
                        logger.warning("Secure Enclave key generation failed", metadata: [
                            "error": .string(errorDesc)
                        ])
                        throw CryptoError.keyGenerationFailed(errorDesc)
                    }
                    logger.warning("Secure Enclave key generation failed with unknown error")
                    throw CryptoError.keyGenerationFailed("Unknown error")
                }
                
                logger.info("Successfully created Secure Enclave key", metadata: [
                    "key_type": .string("secure_enclave")
                ])
            } catch {
                // Fallback to regular keychain if Secure Enclave fails
                logger.warning("Secure Enclave unavailable, falling back to regular keychain", metadata: [
                    "fallback_reason": .string(String(describing: error))
                ])
                try createFallbackKey(keyAlias: keyAlias)
            }
        }
    }
    
    func createFallbackKey(keyAlias: String) throws {
        try logger.logOperation("create_fallback_key") {
            logger.info("Creating fallback keychain key")
            
            let accessControl = SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                [.privateKeyUsage],
                nil
            )
            
            let attributes: [String: Any] = [
                kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                kSecAttrKeySizeInBits as String: 256,
                kSecPrivateKeyAttrs as String: [
                    kSecAttrIsPermanent as String: true,
                    kSecAttrApplicationTag as String: keyAlias.data(using: .utf8)!,
                    kSecAttrAccessControl as String: accessControl as Any
                ]
            ]
            
            var error: Unmanaged<CFError>?
            guard let _ = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
                if let error = error?.takeRetainedValue() {
                    let errorDesc = CFErrorCopyDescription(error) as String? ?? "Unknown error"
                    logger.error("Fallback key generation failed", metadata: [
                        "error": .string(errorDesc)
                    ])
                    throw CryptoError.keyGenerationFailed(errorDesc)
                }
                logger.error("Fallback key generation failed with unknown error")
                throw CryptoError.keyGenerationFailed("Unknown error")
            }
            
            logger.info("Successfully created fallback keychain key", metadata: [
                "key_type": .string("regular_keychain")
            ])
        }
    }
    
    func createHardwareKeyIfNeeded(keyAlias: String) throws {
        if !hardwareKeyExists(keyAlias: keyAlias) {
            try createHardwareKey(keyAlias: keyAlias)
        }
    }
    
    func hardwareKeyExists(keyAlias: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyAlias.data(using: .utf8)!,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return status == errSecSuccess
    }
    
    func getHardwareKey(keyAlias: String) throws -> SecKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyAlias.data(using: .utf8)!,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess, let key = item else {
            throw CryptoError.keyNotFound
        }
        
        return key as! SecKey
    }
    
    // MARK: - Hardware Encryption/Decryption
    
    func encryptWithHardwareKey(plain: Data, keyAlias: String) throws -> Data {
        let privateKey = try getHardwareKey(keyAlias: keyAlias)
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            logger.error("Failed to get public key from private key", metadata: [
                "key_alias": .string(keyAlias)
            ])
            throw CryptoError.keyNotFound
        }
        
        var error: Unmanaged<CFError>?
        guard let encryptedData = SecKeyCreateEncryptedData(
            publicKey,
            .eciesEncryptionStandardX963SHA256AESGCM,
            plain as CFData,
            &error
        ) else {
            if let error = error?.takeRetainedValue() {
                let errorDesc = CFErrorCopyDescription(error) as String? ?? "Unknown error"
                logger.error("Hardware encryption failed", metadata: [
                    "error": .string(errorDesc),
                    "key_alias": .string(keyAlias),
                    "data_size": .stringConvertible(plain.count)
                ])
                throw CryptoError.encryptionFailed(errorDesc)
            }
            logger.error("Hardware encryption failed with unknown error", metadata: [
                "key_alias": .string(keyAlias),
                "data_size": .stringConvertible(plain.count)
            ])
            throw CryptoError.encryptionFailed("Unknown error")
        }
        
        return encryptedData as Data
    }
    
    func decryptWithHardwareKey(encrypted: Data, keyAlias: String) throws -> Data {
        let privateKey = try getHardwareKey(keyAlias: keyAlias)
        
        var error: Unmanaged<CFError>?
        guard let decryptedData = SecKeyCreateDecryptedData(
            privateKey,
            .eciesEncryptionStandardX963SHA256AESGCM,
            encrypted as CFData,
            &error
        ) else {
            if let error = error?.takeRetainedValue() {
                let errorDesc = CFErrorCopyDescription(error) as String? ?? "Unknown error"
                logger.error("Hardware decryption failed", metadata: [
                    "error": .string(errorDesc),
                    "key_alias": .string(keyAlias),
                    "encrypted_size": .stringConvertible(encrypted.count)
                ])
                throw CryptoError.decryptionFailed(errorDesc)
            }
            logger.error("Hardware decryption failed with unknown error", metadata: [
                "key_alias": .string(keyAlias),
                "encrypted_size": .stringConvertible(encrypted.count)
            ])
            throw CryptoError.decryptionFailed("Unknown error")
        }
        
        return decryptedData as Data
    }
}

// MARK: - File Management
extension HardwareEncryptionScheme {

    func getKeyDirectory() -> URL {
        let appSupportPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var keyDir = appSupportPath.appendingPathComponent(Self.dekDirectory)

        // Create directory, set file protection, and exclude from backup
        do {
            try FileManager.default.createDirectory(at: keyDir, withIntermediateDirectories: true, attributes: nil)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try keyDir.setResourceValues(resourceValues)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: keyDir.path)
        } catch {
            Logger.storage.error("Failed to setup key directory: \(error)")
        }

        return keyDir
    }

    func getDekFile(hashedPin: HashedPin) -> URL {
        // Hash the pin hash to create a safe filename (similar to Android implementation)
        guard let pinData = Data(base64URLString: hashedPin.hash) else {
            fatalError("Failed to convert hashed pin to Data")
        }
        let hash = SHA512.hash(data: pinData)
        let hashString = Data(hash).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")

        return getKeyDirectory().appendingPathComponent("\(Self.dekFilenamePrefix)_\(hashString)")
    }

    /// Test-only hook: Secure-Enclave-unwrap an on-disk DEK file payload so tests
    /// can assert it is stored PIN-wrapped (not as a raw DEK). Uses the scheme's
    /// own KEK alias.
    func decryptWithHardwareKeyForTesting(encrypted: Data) throws -> Data {
        try decryptWithHardwareKey(encrypted: encrypted, keyAlias: self.keyAlias)
    }
}

// MARK: - Custom Errors
enum CryptoError: Error, LocalizedError, Equatable {
    case keyNotDerived
    case keyNotFound
    case keyGenerationFailed(String)
    case encryptionFailed(String)
    case decryptionFailed(String)
    case keyDerivationFailed
    case randomGenerationFailed
    case invalidCiphertext
    /// The supplied PIN could not unwrap the DEK (AES-GCM authentication failed
    /// or the wrapped payload was malformed). Surfaced as a clean "wrong PIN".
    case wrongPin

    var errorDescription: String? {
        switch self {
        case .keyNotDerived:
            return "Encryption key has not been derived"
        case .keyNotFound:
            return "Hardware encryption key not found"
        case .keyGenerationFailed(let message):
            return "Key generation failed: \(message)"
        case .encryptionFailed(let message):
            return "Encryption failed: \(message)"
        case .decryptionFailed(let message):
            return "Decryption failed: \(message)"
        case .keyDerivationFailed:
            return "Key derivation failed"
        case .randomGenerationFailed:
            return "Random number generation failed"
        case .invalidCiphertext:
            return "Invalid ciphertext format"
        case .wrongPin:
            return "Incorrect PIN"
        }
    }
}

