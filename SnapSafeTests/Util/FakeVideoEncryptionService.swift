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

    // periphery:ignore
    func encryptVideo(inputURL: URL, outputURL: URL, encryptionKey: SymmetricKey) -> (progress: AnyPublisher<Double, Never>, completion: (Result<URL, Error>) -> Void) {
        (Empty<Double, Never>().eraseToAnyPublisher(), { _ in })
    }

    // periphery:ignore
    func decryptVideo(inputURL: URL, outputURL: URL, encryptionKey: SymmetricKey) -> (progress: AnyPublisher<Double, Never>, completion: (Result<URL, Error>) -> Void) {
        (Empty<Double, Never>().eraseToAnyPublisher(), { _ in })
    }

    func decryptVideoForSharing(inputURL: URL, outputURL: URL, encryptionKey: SymmetricKey) async throws {
        decryptForSharingCalled = true
        try requireExistingOutput(outputURL)
        try Self.decryptedMarker.write(to: outputURL)
    }

    func encryptVideoForDecoy(inputURL: URL, outputURL: URL, encryptionKey: SymmetricKey) async throws {
        encryptForDecoyCalled = true
        try requireExistingOutput(outputURL)
        try Self.reEncryptedMarker.write(to: outputURL)
    }

    /// The real `VideoEncryptionService` opens its output with
    /// `FileHandle(forWritingTo:)`, which requires the file to already exist.
    /// Model that precondition so tests catch callers that forget to pre-create
    /// the output file.
    private func requireExistingOutput(_ outputURL: URL) throws {
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw NSError(
                domain: "FakeVideoEncryptionService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "output file must exist before writing: \(outputURL.lastPathComponent)"]
            )
        }
    }

    // periphery:ignore
    func validateSECVFile(fileURL: URL) -> Bool { true }
}
