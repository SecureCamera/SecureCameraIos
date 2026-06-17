//
//  EncryptedVideoDataSourceTests.swift
//  SnapSafeTests
//
//  Covers the lifetime and thread-safety contract of the resource-loader delegate
//  created by `AVAsset.makeEncryptedVideoAsset(with:encryptionKey:)`. The delegate
//  used to be parked in a shared static dictionary that was mutated without
//  synchronization (a data race) and never pruned (an unbounded leak). It is now
//  tied to the asset via an associated object.
//

import XCTest
import AVFoundation
import CryptoKit
@testable import SnapSafe

final class EncryptedVideoDataSourceTests: XCTestCase {

    private func makeTempSecvURL() -> URL {
        // The file need not exist: EncryptedVideoDataSource.init tolerates a missing
        // file (it logs and leaves the trailer nil), and these tests only exercise
        // delegate creation/lifetime, not actual decryption.
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).secv")
    }

    /// The delegate must live exactly as long as the asset. A permanent static cache
    /// (the previous implementation) would keep it alive forever, leaking the
    /// delegate and its decrypted-chunk cache for every video ever played.
    func test_delegate_isReleasedWhenAssetDeallocates() throws {
        weak var weakDelegate: EncryptedVideoDataSource?

        try autoreleasepool {
            let key = SymmetricKey(size: .bits256)
            var asset: AVURLAsset? = AVAsset.makeEncryptedVideoAsset(
                with: makeTempSecvURL(), encryptionKey: key)

            weakDelegate = AVAsset.encryptedVideoDataSource(for: try XCTUnwrap(asset))
            XCTAssertNotNil(weakDelegate, "Delegate must be retained while the asset is alive")

            asset = nil
        }

        XCTAssertNil(weakDelegate,
                     "Delegate must be released when its asset deallocates; the old static cache leaked it")
    }

    /// Creating many assets concurrently must not corrupt shared state. The previous
    /// implementation mutated a shared `Dictionary` from every call with no lock,
    /// which is a data race; the associated-object approach removes the shared state
    /// entirely, so this must complete cleanly with every delegate retained.
    func test_concurrentCreation_isRaceFreeAndRetainsEachDelegate() async {
        let key = SymmetricKey(size: .bits256)
        let count = 200

        let successes = await withTaskGroup(of: Bool.self) { group -> Int in
            for i in 0..<count {
                group.addTask {
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("concurrent-\(i)-\(UUID().uuidString).secv")
                    guard let asset = AVAsset.makeEncryptedVideoAsset(with: url, encryptionKey: key) else {
                        return false
                    }
                    // The delegate must be retained by *this* asset, confirming each
                    // call is independent and the retention survived the race window.
                    return AVAsset.encryptedVideoDataSource(for: asset) != nil
                }
            }

            var ok = 0
            for await didSucceed in group where didSucceed { ok += 1 }
            return ok
        }

        XCTAssertEqual(successes, count,
                       "Every concurrent creation should succeed with its delegate retained")
    }
}
