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
    private var cachedKey: Data?
    
    func hasKey() -> Bool {
        return cachedKey != nil
    }
    
    func getKey() -> Data? {
        return cachedKey
    }
    
    func setKey(_ key: Data) {
        // Only set if not already cached (prevents duplicate work)
        if cachedKey == nil {
            cachedKey = key
        }
    }
    
    func evictKey() {
        // Zero the memory before releasing
        _ = cachedKey?.withUnsafeMutableBytes { bytes in
            memset(bytes.baseAddress!, 0, bytes.count)
        }
        cachedKey = nil
    }
}

/// Hardware-backed encryption scheme that uses iOS Keychain and Secure Enclave for key protection
/// Similar to Android's HardwareBackedEncryptionScheme but without ephemeral key mode
final class HardwareEncryptionScheme: EncryptionScheme {
    
    // MARK: - Constants
    private static let keyAlias = "snapsafe_kek"
    private static let aesGCMMode = "AES/GCM/NoPadding"
    private static let ivLengthBytes = 12  // 96-bit IV recommended for GCM
    private static let tagLengthBits = 128 // 128-bit tag appended automatically
    private static let dSaltSize = 64
    private static let dekFilenamePrefix = "dek"
    private static let dekDirectory = "keys"
    private static let defaultIterations: UInt32 = 600_000 // PBKDF2 iterations
    private static let defaultKeySize = 32 // 256-bit keys
    
    // MARK: - Dependencies
    private let deviceInfo: DeviceInfoDataSource
    private let keyCache = KeyCache()
    private let logger = Logger.encryption
    
    // MARK: - Initialization
    init(deviceInfo: DeviceInfoDataSource) {
        self.deviceInfo = deviceInfo
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
        try createHardwareKeyIfNeeded(keyAlias: keyAlias)
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
        
        logger.info("Key not cached, deriving new key")
        
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
    
    func evictKey() {
        Task {
            await keyCache.evictKey()
        }
    }
    
    func createKey(plainPin: String, hashedPin: HashedPin) async throws {
        try await logger.logAsyncOperation("create_key") {
            // Create hardware-backed KEK if it doesn't exist (outside of lock)
            if !hardwareKeyExists(keyAlias: Self.keyAlias) {
                logger.info("Hardware key doesn't exist, creating new one", metadata: [
                    "key_alias": .string(Self.keyAlias)
                ])
                try createHardwareKey(keyAlias: Self.keyAlias)
            } else {
                logger.debug("Hardware key already exists", metadata: [
                    "key_alias": .string(Self.keyAlias)
                ])
            }
            
            try await createWrappedKey(plainPin: plainPin, hashedPin: hashedPin)
        }
    }
    
    func securityFailureReset() async {
        logger.warning("Performing security failure reset")
        
        // Delete all DEKs
        let keyDir = getKeyDirectory()
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: keyDir, 
                                                                       includingPropertiesForKeys: nil)
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
        
        let encryptedDek = try Data(contentsOf: dekFile)
        logger.logDataOperation("decrypt_dek", dataSize: encryptedDek.count)
        
        return try decryptWithHardwareKey(encrypted: encryptedDek, keyAlias: Self.keyAlias)
    }
    
    func createWrappedKey(plainPin: String, hashedPin: HashedPin) async throws {
        try await logger.logAsyncOperation("create_wrapped_key") {
            // Create the dSalt (device salt)
            var dSalt = Data(count: Self.dSaltSize)
            let result = dSalt.withUnsafeMutableBytes { bytes in
                SecRandomCopyBytes(kSecRandomDefault, Self.dSaltSize, bytes.bindMemory(to: UInt8.self).baseAddress!)
            }
            
            guard result == errSecSuccess else {
                logger.error("Failed to generate random dSalt", metadata: [
                    "sec_result": .stringConvertible(result)
                ])
                throw CryptoError.randomGenerationFailed
            }
            
            logger.debug("Generated dSalt", metadata: [
                "size_bytes": .stringConvertible(Self.dSaltSize)
            ])
            
            // Derive the key using PBKDF2
            let encodedDSalt = dSalt.base64EncodedString()
            let deviceId = await deviceInfo.getDeviceIdentifier()
            let encodedDeviceId = deviceId.base64EncodedString()
            
            let dekInput = plainPin.data(using: .utf8)! + 
                          encodedDSalt.data(using: .utf8)! + 
                          encodedDeviceId.data(using: .utf8)!
            
            logger.debug("Deriving DEK using PBKDF2", metadata: [
                "iterations": .stringConvertible(Self.defaultIterations),
                "key_size": .stringConvertible(Self.defaultKeySize)
            ])
            
            let salt = Data(base64Encoded: hashedPin.salt) ?? Data()
            let dekBytes = try derivePBKDF2Key(input: dekInput, salt: salt)
            
            logger.logDataOperation("derived_dek", dataSize: dekBytes.count)
            
            // Encrypt and store the DEK using hardware-backed key
            let encryptedDek = try encryptWithHardwareKey(plain: dekBytes, keyAlias: Self.keyAlias)
            let dekFile = getDekFile(hashedPin: hashedPin)
            try encryptedDek.write(to: dekFile)
            
            logger.info("Encrypted and stored DEK", metadata: [
                "file": .string(dekFile.lastPathComponent),
                "encrypted_size": .stringConvertible(encryptedDek.count)
            ])
        }
    }
    
    func derivePBKDF2Key(input: Data, salt: Data) throws -> Data {
        var derivedKey = Data(count: Self.defaultKeySize)
        let result = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            input.withUnsafeBytes { inputBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        inputBytes.bindMemory(to: Int8.self).baseAddress!,
                        input.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress!,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        Self.defaultIterations,
                        derivedKeyBytes.bindMemory(to: UInt8.self).baseAddress!,
                        Self.defaultKeySize
                    )
                }
            }
        }
        
        guard result == kCCSuccess else {
            logger.error("PBKDF2 key derivation failed", metadata: [
                "cc_result": .stringConvertible(result),
                "expected": .stringConvertible(kCCSuccess)
            ])
            throw CryptoError.keyDerivationFailed
        }
        
        return derivedKey
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
    
    // MARK: - File Management
    
    func getKeyDirectory() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let keyDir = documentsPath.appendingPathComponent(Self.dekDirectory)
        
        if !FileManager.default.fileExists(atPath: keyDir.path) {
            try? FileManager.default.createDirectory(at: keyDir, withIntermediateDirectories: true)
        }
        
        return keyDir
    }
    
    func getDekFile(hashedPin: HashedPin) -> URL {
        // Hash the pin hash to create a safe filename (similar to Android implementation)
        let pinData = Data(base64Encoded: hashedPin.hash) ?? Data()
        let hash = SHA512.hash(data: pinData)
        let hashString = Data(hash).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        
        return getKeyDirectory().appendingPathComponent("\(Self.dekFilenamePrefix)_\(hashString)")
    }
}

// MARK: - Custom Errors
enum CryptoError: Error, LocalizedError {
    case keyNotDerived
    case keyNotFound
    case keyGenerationFailed(String)
    case encryptionFailed(String)
    case decryptionFailed(String)
    case keyDerivationFailed
    case randomGenerationFailed
    case invalidCiphertext
    
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
        }
    }
}

