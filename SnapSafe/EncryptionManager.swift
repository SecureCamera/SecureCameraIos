//
//  EncryptionManager.swift
//  Snap Safe
//
//  Created by Bill Booth on 5/3/25.
//

import Foundation
import CryptoKit
import Security

//class EncryptionManager {
//    private let keyManager = KeyManagement()
//    
//    func encryptData(_ data: Data) throws -> Data {
//        // Generate a random symmetric key
//        let symmetricKey = SymmetricKey(size: .bits256)
//        
//        // Encrypt the data using AES-GCM
//        let nonce = AES.GCM.Nonce()
//        let ciphertext = try AES.GCM.seal(data, using: symmetricKey, nonce: nonce)
//        
//        // Encrypt the symmetric key with the Secure Enclave key
//        let encryptedSymmetricKey = try encryptSymmetricKey(symmetricKey)
//        
//        // Combine everything into a single encrypted package
//        var encryptedData = Data()
//        encryptedData.append(nonce.withUnsafeBytes { Data($0) })
//        encryptedData.append(encryptedSymmetricKey)
//        encryptedData.append(try ciphertext.combined())
//        
//        return encryptedData
//    }
//    
//    func decryptData(_ encryptedData: Data) throws -> Data {
//        // Extract components from the encrypted package
//        let nonceSize = AES.GCM.Nonce.byteCount
//        let encryptedKeySize = 256 // Adjust based on your key encryption method
//        
//        let nonce = encryptedData.prefix(nonceSize)
//        let encryptedKey = encryptedData.subdata(in: nonceSize..<(nonceSize + encryptedKeySize))
//        let sealedBox = encryptedData.suffix(from: nonceSize + encryptedKeySize)
//        
//        // Decrypt the symmetric key
//        let symmetricKey = try decryptSymmetricKey(encryptedKey)
//        
//        // Create AES-GCM seal box
//        let nonceObj = try AES.GCM.Nonce(data: nonce)
//        let box = try AES.GCM.SealedBox(combined: sealedBox)
//        
//        // Decrypt the data
//        return try AES.GCM.open(box, using: symmetricKey)
//    }
//    
//    private func encryptSymmetricKey(_ key: SymmetricKey) throws -> Data {
//        // Get the public key corresponding to the private key in Secure Enclave
//        let privateKey = try keyManager.getEncryptionKey()
//        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
//            throw NSError(domain: "com.securecamera", code: -1, userInfo: nil)
//        }
//        
//        // Convert SymmetricKey to Data
//        let keyData = key.withUnsafeBytes { Data($0) }
//        
//        // Encrypt the symmetric key with the public key
//        guard let encryptedKey = SecKeyCreateEncryptedData(
//            publicKey,
//            .eciesEncryptionCofactorX963SHA256AESGCM,
//            keyData as CFData,
//            nil
//        ) as Data? else {
//            throw NSError(domain: "com.securecamera", code: -2, userInfo: nil)
//        }
//        
//        return encryptedKey
//    }
//    
//    private func decryptSymmetricKey(_ encryptedKey: Data) throws -> SymmetricKey {
//        // Get the private key from Secure Enclave
//        let privateKey = try keyManager.getEncryptionKey()
//        
//        // Decrypt the symmetric key
//        guard let decryptedKey = SecKeyCreateDecryptedData(
//            privateKey,
//            .eciesEncryptionCofactorX963SHA256AESGCM,
//            encryptedKey as CFData,
//            nil
//        ) as Data? else {
//            throw NSError(domain: "com.securecamera", code: -3, userInfo: nil)
//        }
//        
//        // Convert Data back to SymmetricKey
//        return SymmetricKey(data: decryptedKey)
//    }
//}
