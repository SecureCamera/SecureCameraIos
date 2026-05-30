//
//  FakeVideoEncryptionService.swift
//  SnapSafeTests
//
//  Minimal fake that simulates SECV encrypt/decrypt by writing marker files,
//  so decoy-video logic can be tested without real video crypto.
//

import Foundation
import Combine
import CryptoKit
@testable import SnapSafe

@MainActor
final class FakeVideoEncryptionService: VideoEncryptionServiceProtocol {

    static let decryptedMarker = Data("plaintext".utf8)
    static let reEncryptedMarker = Data("decoy-reencrypted".utf8)

    private(set) var decryptForSharingCalled = false
    private(set) var encryptForDecoyCalled = false

    func encryptVideo(inputURL: URL, outputURL: URL, encryptionKey: SymmetricKey) -> (progress: AnyPublisher<Double, Never>, completion: (Result<URL, Error>) -> Void) {
        (Empty<Double, Never>().eraseToAnyPublisher(), { _ in })
    }

    func decryptVideo(inputURL: URL, outputURL: URL, encryptionKey: SymmetricKey) -> (progress: AnyPublisher<Double, Never>, completion: (Result<URL, Error>) -> Void) {
        (Empty<Double, Never>().eraseToAnyPublisher(), { _ in })
    }

    func decryptVideoForSharing(inputURL: URL, outputURL: URL, encryptionKey: SymmetricKey) async throws {
        decryptForSharingCalled = true
        try Self.decryptedMarker.write(to: outputURL)
    }

    func encryptVideoForDecoy(inputURL: URL, outputURL: URL, encryptionKey: SymmetricKey) async throws {
        encryptForDecoyCalled = true
        try Self.reEncryptedMarker.write(to: outputURL)
    }

    func validateSECVFile(fileURL: URL) -> Bool { true }
}
