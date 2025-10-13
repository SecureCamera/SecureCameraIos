//
//  SecurityResetUseCase.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/8/25.
//

import Foundation
import Logging

final class SecurityResetUseCase: @unchecked Sendable {
    private let authRepo: AuthorizationRepository
    private let imageRepository: SecureImageRepository
    private let encryptionScheme: EncryptionScheme
    
    init(
        authManager: AuthorizationRepository,
        imageRepository: SecureImageRepository,
        encryptionScheme: EncryptionScheme
    ) {
        self.authRepo = authManager
        self.imageRepository = imageRepository
        self.encryptionScheme = encryptionScheme
    }
    
    func reset() async {
        await authRepo.securityFailureReset()
        await imageRepository.securityFailureReset()
        await encryptionScheme.securityFailureReset()
        Logger.security.info("Security Reset Complete!")
    }
}
