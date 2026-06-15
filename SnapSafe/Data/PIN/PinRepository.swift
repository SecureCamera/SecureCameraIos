//
//  PinRepository.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/2/25.
//

import Mockable

@Mockable
protocol PinRepository: Sendable {
    // MARK: - Core PIN APIs

    func setAppPin(_ pin: String, pinType: PINType) async
    func getHashedPin() async -> HashedPin?

    func hashPin(_ pin: String) async throws -> HashedPin
    func verifyPin(inputPin: String, storedHash: HashedPin) async -> Bool
    func verifyPoisonPillPin(_ pin: String) async -> Bool
    
    func verifySecurityPin(_ pin: String) async -> Bool
    func hasPoisonPillPin() async -> Bool
    
    // MARK: - Poison Pill APIs

    func setPoisonPillPin(_ pin: String, pinType: PINType) async
    func getPlainPoisonPillPin() async -> String?
    func getHashedPoisonPillPin() async -> HashedPin?
    func activatePoisonPill() async
    func removePoisonPillPin() async
}

let MIN_PIN_LENGTH = 4
let MAX_PIN_LENGTH = 10
