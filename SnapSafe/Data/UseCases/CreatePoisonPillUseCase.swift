//
//  CreatePoisonPillUseCase.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/11/25.
//

final class CreatePoisonPillUseCase {
    private let pinRepository: PinRepository
    private let encryptionScheme: EncryptionScheme
    
    init(pinRepository: PinRepository, encryptionScheme: EncryptionScheme) {
        self.pinRepository = pinRepository
        self.encryptionScheme = encryptionScheme
    }
    
    func createPin(pppin: String) async {
        await pinRepository.setPoisonPillPin(pppin)
        guard let hashedPPPin = await pinRepository.getHashedPoisonPillPin()
                else {
            fatalError("Failed to retrieve hashed pin")
        }
        try! await encryptionScheme.createKey(plainPin: pppin, hashedPin: hashedPPPin)
    }
}
