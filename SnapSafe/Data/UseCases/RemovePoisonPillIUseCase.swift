//
//  RemovePoisonPillIUseCase.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/8/25.
//

import Foundation

final class RemovePoisonPillUseCase {
    private let pinRepository: PinRepository
    private let imageRepository: SecureImageRepository
    
    init(pinRepository: PinRepository, imageRepository: SecureImageRepository) {
        self.pinRepository = pinRepository
        self.imageRepository = imageRepository
    }
    
    func removePoisonPill() async {
        await pinRepository.removePoisonPillPin()
        await imageRepository.removeAllDecoyPhotos()
    }
}
