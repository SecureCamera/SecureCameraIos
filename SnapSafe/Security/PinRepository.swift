//
//  PinRepository.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/2/25.
//

import Mockable

@Mockable
public protocol PinRepository {
    // MARK: - Core PIN APIs

    func setAppPin(_ pin: String) async
    func getHashedPin() async -> HashedPin?

    func hashPin(_ pin: String) async -> HashedPin
    func verifyPin(inputPin: String, storedHash: HashedPin) async -> Bool
    func verifyPoisonPillPin(_ pin: String) async -> Bool
    
    func verifySecurityPin(_ pin: String) async -> Bool
    func hasPoisonPillPin() async throws -> Bool
    
    // MARK: - Poison Pill APIs

    func setPoisonPillPin(_ pin: String) async
    func getPlainPoisonPillPin() async -> String?
    func getHashedPoisonPillPin() async -> HashedPin?
    func activatePoisonPill() async
    func removePoisonPillPin() async

}
