//
//  EncryptionDataSource.swift
//  SnapSafe
//
//  Created by Claude on 5/28/25.
//

import CryptoKit
import Foundation

final class EncryptionDataSource: EncryptionDataSourceProtocol {
    private let keyManager: KeyManager

    init(keyManager: KeyManager) {
        self.keyManager = keyManager
    }

    func encryptImageData(_ data: Data) async throws -> Data {
        let key = try await keyManager.getOrCreateEncryptionKey()
        let sealedBox = try AES.GCM.seal(data, using: key)
        return sealedBox.combined!
    }

    func decryptImageData(_ encryptedData: Data) async throws -> Data {
        let key = try await keyManager.getOrCreateEncryptionKey()
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        return try AES.GCM.open(sealedBox, using: key)
    }

    func generateSecureKey() async throws -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }
}
