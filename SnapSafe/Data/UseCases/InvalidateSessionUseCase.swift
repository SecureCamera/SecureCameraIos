//
//  InvalidateSessionUseCase.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/8/25.
//

import Foundation


@MainActor
final class InvalidateSessionUseCase {
    private let imageRepository: SecureImageRepository
    private let authManager: AuthorizationRepository

    init(
        imageRepository: SecureImageRepository,
        authManager: AuthorizationRepository
    ) {
        self.imageRepository = imageRepository
        self.authManager = authManager
    }

    func invalidateSession() async {
        await imageRepository.evictKey()
        imageRepository.thumbnailCache.clear()
        authManager.revokeAuthorization()
    }
}
