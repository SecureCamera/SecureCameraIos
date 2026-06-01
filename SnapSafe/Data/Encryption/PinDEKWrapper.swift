//
//  PinDEKWrapper.swift
//  SnapSafe
//
//  Created by Claude on 2026-05-31.
//
//  C1 fix — PIN-derived AES wrap for the DEK.
//
//  Historically the DEK was derived directly from the PIN (PBKDF2) and then
//  wrapped only by the Secure Enclave key. On the load path the SE alone
//  reproduced the DEK, so the PIN was a Swift-level gate, not a cryptographic
//  dependency — anything reaching `SecKeyCreateDecryptedData` on an unlocked
//  device recovered the DEK without the PIN.
//
//  This type adds a PIN-derived AES-GCM layer *under* the SE wrap:
//
//      DEK     = random(32)                      // independent of the PIN
//      pinKey  = PBKDF2(prefix ‖ PIN ‖ deviceID, salt)
//      payload = AES-GCM(DEK, key: pinKey)       // nonce ‖ ciphertext ‖ tag
//      stored  = SE_wrap(payload)
//
//  Recovering the DEK now requires the user to actually type the PIN; the
//  attacker on an unlocked device gets only the PIN-wrapped blob. The PIN
//  remains uncoercible (unlike biometrics / device passcode), which is the
//  point — see design/2026-05-31-c1-pin-binding-analysis.
//
//  This unit deliberately depends only on CryptoKit + CommonCrypto (no
//  keychain / Secure Enclave) so it is fully unit-testable on the simulator.

import CommonCrypto
import CryptoKit
import Foundation

enum PinDEKWrapper {

    /// Domain-separation prefix so the PIN-wrap key derivation can never collide
    /// with any other PBKDF2 use of the same PIN/salt.
    private static let domainPrefix = "snapsafe-pinwrap-v1:"

    /// PBKDF2 iterations. Matches the scheme's existing cost (OWASP 2024 ≥ 600k).
    static let iterations: UInt32 = 600_000

    /// 256-bit derived key / 256-bit DEK.
    static let keySize = 32

    /// AES-GCM framing sizes.
    static let nonceSize = 12
    static let tagSize = 16

    /// A raw (legacy) DEK is exactly `keySize` bytes; a PIN-wrapped payload is
    /// `nonceSize + keySize + tagSize` bytes. The two never collide, so length
    /// is an unambiguous discriminator for one-shot migration.
    static let wrappedSize = nonceSize + keySize + tagSize

    // MARK: - Key derivation

    /// Derives the PIN-wrap key from the plain PIN, bound to the device.
    /// - Parameters:
    ///   - plainPin: the user's PIN (never persisted).
    ///   - salt: per-credential salt (the Argon2 `hashedPin.salt`).
    ///   - deviceId: stable device identifier bytes.
    static func derivePinKey(plainPin: String, salt: Data, deviceId: Data) throws -> SymmetricKey {
        var input = Data(domainPrefix.utf8)
        input.append(Data(plainPin.utf8))
        input.append(deviceId)

        var derived = Data(count: keySize)
        let status = derived.withUnsafeMutableBytes { outBytes in
            input.withUnsafeBytes { inBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        inBytes.bindMemory(to: Int8.self).baseAddress!,
                        input.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress!,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        outBytes.bindMemory(to: UInt8.self).baseAddress!,
                        keySize
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw CryptoError.keyDerivationFailed
        }
        return SymmetricKey(data: derived)
    }

    // MARK: - Wrap / unwrap

    /// Wraps a DEK under the PIN-derived key. Output is `nonce ‖ ciphertext ‖ tag`.
    static func wrap(dek: Data, pinKey: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(dek, using: pinKey)
        var out = Data()
        out.append(sealed.nonce.withUnsafeBytes { Data($0) })
        out.append(sealed.ciphertext)
        out.append(sealed.tag)
        return out
    }

    /// Unwraps a PIN-wrapped payload. Throws `CryptoError.wrongPin` if the PIN
    /// key does not match (AES-GCM authentication failure) or the payload is
    /// malformed.
    static func unwrap(payload: Data, pinKey: SymmetricKey) throws -> Data {
        guard payload.count == wrappedSize else {
            throw CryptoError.wrongPin
        }
        let nonceData = payload.prefix(nonceSize)
        let ciphertext = payload.dropFirst(nonceSize).dropLast(tagSize)
        let tag = payload.suffix(tagSize)

        do {
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: nonceData),
                ciphertext: ciphertext,
                tag: tag
            )
            return try AES.GCM.open(box, using: pinKey)
        } catch {
            // Any failure here (auth-tag mismatch, bad framing) means the PIN
            // key was wrong. Collapse to a single, non-leaky error.
            throw CryptoError.wrongPin
        }
    }

    /// True if the on-disk payload is a legacy, SE-only-wrapped raw DEK (exactly
    /// `keySize` bytes), as opposed to a PIN-wrapped payload (`wrappedSize`).
    static func isLegacyRawDEK(_ data: Data) -> Bool {
        data.count == keySize
    }
}
