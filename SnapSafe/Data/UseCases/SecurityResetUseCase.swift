//
//  SecurityResetUseCase.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/8/25.
//

import Foundation

final class SecurityResetUseCase {
    private let authManager: AuthorizationRepository
    private let imageRepository: SecureImageRepository
    private let encryptionScheme: EncryptionScheme
    
    init(
        authManager: AuthorizationRepository,
        imageRepository: SecureImageRepository,
        encryptionScheme: EncryptionScheme
    ) {
        self.authManager = authManager
        self.imageRepository = imageRepository
        self.encryptionScheme = encryptionScheme
    }
    
    func reset() async {
        await authManager.securityFailureReset()
        await imageRepository.securityFailureReset()
        await encryptionScheme.securityFailureReset()
        print("Security Reset Complete!") // Timber.d equivalent
    }
}
