//
//  AVPlayerItemStatusObservationTests.swift
//  SnapSafeTests
//
//  VideoPlayerView observes AVPlayerItem.status via Combine to drive its loading /
//  ready / failed UI. The custom (and racy) Publisher/Subscription that used to back
//  this was removed in favour of Foundation's thread-safe `NSObject.publisher(for:)`.
//  These tests pin the observable behaviour the view depends on so the refactor — and
//  any future one — preserves it.
//

import XCTest
import AVFoundation
import Combine
@testable import SnapSafe

final class AVPlayerItemStatusObservationTests: XCTestCase {

    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    /// A fresh AVPlayerItem reports `.unknown`, and the KVO `.initial` option must
    /// deliver that current value synchronously on subscribe — the view relies on
    /// this to render its initial loading state without waiting for a change.
    func test_statusPublisher_emitsCurrentStatusImmediately() {
        let item = AVPlayerItem(url: URL(fileURLWithPath: "/dev/null/nonexistent.mov"))

        var received: [AVPlayerItem.Status] = []
        item.publisher(for: \.status)
            .sink { received.append($0) }
            .store(in: &cancellables)

        XCTAssertEqual(received.first, .unknown,
                       "Status observation must emit the current status synchronously on subscribe")
    }

    /// Driving an item that can't load (no such file) through an AVPlayer must surface
    /// a `.failed` transition to subscribers — i.e. the `.new` change path works.
    func test_statusPublisher_emitsStatusChange() {
        let item = AVPlayerItem(url: URL(fileURLWithPath: "/var/empty/does-not-exist.mov"))

        let failed = expectation(description: "status reaches .failed")
        var sawFailure = false
        item.publisher(for: \.status)
            .sink { status in
                if status == .failed, !sawFailure {
                    sawFailure = true
                    failed.fulfill()
                }
            }
            .store(in: &cancellables)

        // Status only advances once an AVPlayer attempts to load the item.
        let player = AVPlayer(playerItem: item)
        player.play()

        wait(for: [failed], timeout: 10)
        XCTAssertTrue(sawFailure, "Observers must receive the .failed status change")
    }

    /// Cancelling the subscription must tear the observation down cleanly and stop
    /// delivery. The previous hand-rolled subscription niled its state in `cancel()`
    /// without synchronization; the built-in publisher handles this safely.
    func test_statusPublisher_stopsDeliveringAfterCancel() {
        let item = AVPlayerItem(url: URL(fileURLWithPath: "/var/empty/does-not-exist.mov"))

        var received: [AVPlayerItem.Status] = []
        let cancellable = item.publisher(for: \.status)
            .sink { received.append($0) }

        let countAfterInitial = received.count
        XCTAssertGreaterThanOrEqual(countAfterInitial, 1)

        cancellable.cancel()

        // Drive a status change after cancelling; no further values must arrive.
        let player = AVPlayer(playerItem: item)
        player.play()

        // Give AVFoundation a moment to attempt the load and (would-be) emit.
        let settled = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { settled.fulfill() }
        wait(for: [settled], timeout: 5)

        XCTAssertEqual(received.count, countAfterInitial,
                       "No values must be delivered after the subscription is cancelled")
    }
}
