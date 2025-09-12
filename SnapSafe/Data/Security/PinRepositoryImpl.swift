import CryptoKit
import Foundation
import Logging
import Security

class PinRepositoryImpl: PinRepository {
    private let dataSource: SettingsDataSource
    private let encryptionScheme: EncryptionScheme
    private let deviceInfo: DeviceInfoDataSource
    private let pinCrypto: PinCrypto

    private static let PIN_KEY_ALIAS = "pin_key"

    init(
        dataSource: SettingsDataSource,
        encryptionScheme: EncryptionScheme,
        deviceInfo: DeviceInfoDataSource,
        pinCrypto: PinCrypto
    ) {
        self.dataSource = dataSource
        self.encryptionScheme = encryptionScheme
        self.deviceInfo = deviceInfo
        self.pinCrypto = pinCrypto
    }

    func setAppPin(_ pin: String) async {
        let hashedPin = await hashPin(pin)

        do {
            let hashedPinData = try jsonEncoder().encode(hashedPin)
            let cipheredHash = try await encryptionScheme.encryptWithKeyAlias(
                plain: hashedPinData, keyAlias: Self.PIN_KEY_ALIAS)
            let cipheredHashBase64 = cipheredHash.base64EncodedString()

            await dataSource.setAppPin(cipheredPin: cipheredHashBase64)
        } catch {
            // Handle encoding/encryption errors silently
        }
    }

    func getHashedPin() async -> HashedPin? {
        guard let cipheredPinBase64 = await dataSource.getCipheredPin(),
            let cipheredPinData = Data(base64Encoded: cipheredPinBase64)
        else {
            return nil
        }

        do {
            let hashedPinData = try await encryptionScheme.decryptWithKeyAlias(
                encrypted: cipheredPinData,
                keyAlias: Self.PIN_KEY_ALIAS
            )
            return try JSONDecoder().decode(HashedPin.self, from: hashedPinData)
        } catch {
            return nil
        }
    }

    func verifySecurityPin(_ pin: String) async -> Bool {
        guard let storedHashedPin = await getHashedPin() else {
            return false
        }
        return await verifyPin(inputPin: pin, storedHash: storedHashedPin)
    }

    func hashPin(_ pin: String) async -> HashedPin {
        return pinCrypto.hashPin(pin: pin, deviceId: await deviceInfo.getDeviceIdentifier())
    }

    func verifyPin(inputPin: String, storedHash: HashedPin) async -> Bool {
        return pinCrypto.verifyPin(
            pin: inputPin, stored: storedHash, deviceId: await deviceInfo.getDeviceIdentifier())
    }

    func hasPoisonPillPin() async throws -> Bool {
        let hasPrimary = await getHashedPin() != nil
        let hasPoison = await getHashedPoisonPillPin() != nil
        return hasPrimary && hasPoison
    }

    /// Verify if the input matches the Poison Pill PIN.
    func verifyPoisonPillPin(_ pin: String) async -> Bool {
        guard let stored = await getHashedPoisonPillPin() else { return false }
        return await verifyPin(inputPin: pin, storedHash: stored)
    }

    func setPoisonPillPin(_ pin: String) async {
        let hashedPin = await hashPin(pin)

        do {
            let hashedPinData = try jsonEncoder().encode(hashedPin)

            Logger.security.debug("Setting poison pill PIN", metadata: [
                "hashedPinDataSize": .stringConvertible(hashedPinData.count)
            ])
            
            let cipheredHashedPpp = try await encryptionScheme.encryptWithKeyAlias(
                plain: hashedPinData, keyAlias: Self.PIN_KEY_ALIAS)
            let cipheredHashedPppBase64 = cipheredHashedPpp.base64EncodedString()

            guard let plainPinData = pin.data(using: .utf8) else {
                throw PinError.stringEncodingFailed
            }
            let cipheredPlainPpp = try await encryptionScheme.encryptWithKeyAlias(
                plain: plainPinData, keyAlias: Self.PIN_KEY_ALIAS)
            let cipheredPlainPppBase64 = cipheredPlainPpp.base64EncodedString()

            await dataSource.setPoisonPillPin(
                cipheredHashedPin: cipheredHashedPppBase64, cipheredPlainPin: cipheredPlainPppBase64
            )
        } catch {
            // TODO: What do we want to do with encoding/encryption errors here?
            Logger.security.critical("Failed to set Poison Pill PIN!")
        }
    }

    func getPlainPoisonPillPin() async -> String? {
        guard let encryptedStoredPinBase64 = await dataSource.getPlainPoisonPillPin(),
            let encryptedStoredPin = Data(base64Encoded: encryptedStoredPinBase64)
        else {
            return nil
        }

        do {
            let decryptedData = try await encryptionScheme.decryptWithKeyAlias(
                encrypted: encryptedStoredPin,
                keyAlias: Self.PIN_KEY_ALIAS
            )
            return String(data: decryptedData, encoding: .utf8)
        } catch {
            return nil
        }
    }

    func getHashedPoisonPillPin() async -> HashedPin? {
        guard let encryptedPinBase64 = await dataSource.getHashedPoisonPillPin(),
            let encryptedPinData = Data(base64Encoded: encryptedPinBase64)
        else {
            return nil
        }

        do {
            let storedPinData = try await encryptionScheme.decryptWithKeyAlias(
                encrypted: encryptedPinData,
                keyAlias: Self.PIN_KEY_ALIAS,
            )
            return try JSONDecoder().decode(HashedPin.self, from: storedPinData)
        } catch {
            return nil
        }
    }

    func activatePoisonPill() async {
        guard let poisonPillPin = await getHashedPoisonPillPin() else {
            return
        }

        do {
            let poisonPillPinData = try jsonEncoder().encode(poisonPillPin)
            let ciphered = try await encryptionScheme.encryptWithKeyAlias(
                plain: poisonPillPinData,
                keyAlias: Self.PIN_KEY_ALIAS,
            )
            let cipheredBase64 = ciphered.base64EncodedString()

            await dataSource.activatePoisonPill(ciphered: cipheredBase64)
            await removePoisonPillPin()
        } catch {
            // Handle encoding/encryption errors silently
        }
    }

    func removePoisonPillPin() async {
        await dataSource.removePoisonPillPin()
    }
}

enum PinError: Error {
    case stringEncodingFailed
}
