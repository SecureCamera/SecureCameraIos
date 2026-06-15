import CryptoKit
import Foundation
import Logging
import Security

class PinRepositoryImpl: PinRepository, @unchecked Sendable {
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

    func setAppPin(_ pin: String, pinType: PINType) async {
        do {
            var hashedPin = try await hashPin(pin)
            hashedPin.pinType = pinType
            let hashedPinData = try jsonEncoder().encode(hashedPin)
            let cipheredHash = try await encryptionScheme.encryptWithKeyAlias(
                plain: hashedPinData, keyAlias: Self.PIN_KEY_ALIAS)
            let cipheredHashBase64 = cipheredHash.base64EncodedString()
            await dataSource.setAppPin(cipheredPin: cipheredHashBase64)
        } catch {
            Logger.storage.error("Failed to store app pin: \(error)")
        }
    }

    func getHashedPin() async -> HashedPin? {
        guard let cipheredPinBase64 = await dataSource.getCipheredPin(),
            let cipheredPinData = Data(base64Encoded: cipheredPinBase64)
        else {
            Logger.security.debug("Failed to get hashed pin: no stored pin or invalid base64 encoding")
            return nil
        }

        do {
            let hashedPinData = try await encryptionScheme.decryptWithKeyAlias(
                encrypted: cipheredPinData,
                keyAlias: Self.PIN_KEY_ALIAS
            )
            return try JSONDecoder().decode(HashedPin.self, from: hashedPinData)
        } catch {
            Logger.security.error("Failed to decrypt or decode hashed pin", metadata: [
                "error": .string(String(describing: error))
            ])
            return nil
        }
    }

    func verifySecurityPin(_ pin: String) async -> Bool {
        guard let storedHashedPin = await getHashedPin() else {
            Logger.security.warning("Failed to verify security pin: no stored hashed pin available")
            return false
        }
        return await verifyPin(inputPin: pin, storedHash: storedHashedPin)
    }

    func hashPin(_ pin: String) async throws -> HashedPin {
        return try pinCrypto.hashPin(pin: pin, deviceId: await deviceInfo.getDeviceIdentifier())
    }

    func verifyPin(inputPin: String, storedHash: HashedPin) async -> Bool {
        return pinCrypto.verifyPin(
            pin: inputPin, stored: storedHash, deviceId: await deviceInfo.getDeviceIdentifier())
    }

    func hasPoisonPillPin() async -> Bool {
        let hasPrimary = await getHashedPin() != nil
        let hasPoison = await getHashedPoisonPillPin() != nil
        return hasPrimary && hasPoison
    }

    /// Verify if the input matches the Poison Pill PIN.
    func verifyPoisonPillPin(_ pin: String) async -> Bool {
        guard let stored = await getHashedPoisonPillPin() else {
            Logger.security.debug("Failed to verify poison pill pin: no stored poison pill pin available")
            return false
        }
        return await verifyPin(inputPin: pin, storedHash: stored)
    }

    func setPoisonPillPin(_ pin: String, pinType: PINType) async {
        do {
            var hashedPin = try await hashPin(pin)
            hashedPin.pinType = pinType
            let hashedPinData = try jsonEncoder().encode(hashedPin)

            Logger.security.debug("Setting poison pill PIN", metadata: [
                "hashedPinDataSize": .stringConvertible(hashedPinData.count)
            ])

            let cipheredHashedPpp = try await encryptionScheme.encryptWithKeyAlias(
                plain: hashedPinData, keyAlias: Self.PIN_KEY_ALIAS)
            let cipheredHashedPppBase64 = cipheredHashedPpp.base64EncodedString()

            guard let plainPinData = pin.data(using: .utf8) else {
                Logger.security.error("Failed to encode poison pill pin as UTF-8 data")
                throw PinError.stringEncodingFailed
            }
            let cipheredPlainPpp = try await encryptionScheme.encryptWithKeyAlias(
                plain: plainPinData, keyAlias: Self.PIN_KEY_ALIAS)
            let cipheredPlainPppBase64 = cipheredPlainPpp.base64EncodedString()

            await dataSource.setPoisonPillPin(
                cipheredHashedPin: cipheredHashedPppBase64, cipheredPlainPin: cipheredPlainPppBase64
            )
        } catch {
            Logger.security.critical("Failed to set Poison Pill PIN", metadata: [
                "error": .string(String(describing: error))
            ])
        }
    }

    func getPlainPoisonPillPin() async -> String? {
        guard let encryptedStoredPinBase64 = await dataSource.getPlainPoisonPillPin(),
            let encryptedStoredPin = Data(base64Encoded: encryptedStoredPinBase64)
        else {
            Logger.security.debug("Failed to get plain poison pill pin: no stored pin or invalid base64 encoding")
            return nil
        }

        do {
            let decryptedData = try await encryptionScheme.decryptWithKeyAlias(
                encrypted: encryptedStoredPin,
                keyAlias: Self.PIN_KEY_ALIAS
            )
            return String(data: decryptedData, encoding: .utf8)
        } catch {
            Logger.security.error("Failed to decrypt plain poison pill pin", metadata: [
                "error": .string(String(describing: error))
            ])
            return nil
        }
    }

    func getHashedPoisonPillPin() async -> HashedPin? {
        guard let encryptedPinBase64 = await dataSource.getHashedPoisonPillPin(),
            let encryptedPinData = Data(base64Encoded: encryptedPinBase64)
        else {
            Logger.security.debug("Failed to get hashed poison pill pin: no stored pin or invalid base64 encoding")
            return nil
        }

        do {
            let storedPinData = try await encryptionScheme.decryptWithKeyAlias(
                encrypted: encryptedPinData,
                keyAlias: Self.PIN_KEY_ALIAS,
            )
            return try JSONDecoder().decode(HashedPin.self, from: storedPinData)
        } catch {
            Logger.security.error("Failed to decrypt or decode hashed poison pill pin", metadata: [
                "error": .string(String(describing: error))
            ])
            return nil
        }
    }

    func activatePoisonPill() async {
        guard let poisonPillPin = await getHashedPoisonPillPin() else {
            Logger.security.warning("Failed to activate poison pill: no hashed poison pill pin available")
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
            Logger.security.error("Failed to activate poison pill", metadata: [
                "error": .string(String(describing: error))
            ])
        }
    }

    func removePoisonPillPin() async {
        await dataSource.removePoisonPillPin()
    }
}

enum PinError: Error {
    case stringEncodingFailed
}
