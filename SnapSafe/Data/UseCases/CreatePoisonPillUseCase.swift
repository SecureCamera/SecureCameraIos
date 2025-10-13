//
//  CreatePoisonPillUseCase.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/11/25.
//

final class CreatePoisonPillUseCase: @unchecked Sendable {
    private let pinRepository: PinRepository
    private let encryptionScheme: EncryptionScheme
    
    init(pinRepository: PinRepository, encryptionScheme: EncryptionScheme) {
        self.pinRepository = pinRepository
        self.encryptionScheme = encryptionScheme
    }
    
    func createPin(pppin: String) async -> Bool {
        await pinRepository.setPoisonPillPin(pppin)
        guard let hashedPPPin = await pinRepository.getHashedPoisonPillPin()
                else {
            fatalError("Failed to retrieve hashed pin")
        }
        try! await encryptionScheme.createKey(plainPin: pppin, hashedPin: hashedPPPin)
        
        return true
    }
}
