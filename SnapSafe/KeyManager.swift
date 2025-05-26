//
//  KeyManager.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/3/25.
//

import LocalAuthentication
import Security

// class KeyManagement {
//
//    private let keyTag = "com.securecamera.encryptionkey"
//    private let accessControlFlags: SecAccessControlCreateFlags = [.userPresence, .privateKeyUsage]
//
//    func generateEncryptionKey() throws -> SecKey {
//        // Create access control requiring device PIN
//        let access = SecAccessControlCreateWithFlags(
//            nil,
//            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
//            accessControlFlags,
//            nil
//        )
//
//        // Key generation attributes
//        let attributes: [String: Any] = [
//            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
//            kSecAttrKeySizeInBits as String: 256,
//            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
//            kSecPrivateKeyAttrs as String: [
//                kSecAttrIsPermanent as String: true,
//                kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
//                kSecAttrAccessControl as String: access!
//            ]
//        ]
//
//        // Generate key pair in Secure Enclave
//        var error: Unmanaged<CFError>?
//        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
//            throw error!.takeRetainedValue() as Error
//        }
//
//        return privateKey
//    }
//
//    func getEncryptionKey() throws -> SecKey {
//        let query: [String: Any] = [
//            kSecClass as String: kSecClassKey,
//            kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
//            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
//            kSecReturnRef as String: true
//        ]
//
//        var item: CFTypeRef?
//        let status = SecItemCopyMatching(query as CFDictionary, &item)
//
//        guard status == errSecSuccess else {
//            throw NSError(domain: "com.securecamera", code: Int(status), userInfo: nil)
//        }
//
//        return (item as! SecKey)
//    }
// }
