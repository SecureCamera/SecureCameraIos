//
//  RemoveDecoyPhotoUseCase.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/14/25.
//

import Foundation
import FactoryKit
import Logging


/**
 This one is kinda too simple to be a usecase, it's
 purely a pass-through. But we have an AddDecoyPhotoUseCase,
 so I like the obvious symetry of having both.
 */
final class RemoveDecoyPhotoUseCase {
    private let imageRepository: SecureImageRepository

    init(
        imageRepository: SecureImageRepository
    ) {
        self.imageRepository = imageRepository
    }

    @MainActor func removeDecoyPhoto(_ photoDef: PhotoDef) -> Bool {
        return self.imageRepository.removeDecoyPhoto(photoDef)
    }
}
