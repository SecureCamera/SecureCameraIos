//
//  VideoMetaDataFormattingTests.swift
//  SnapSafeTests
//

import XCTest
@testable import SnapSafe

final class VideoMetaDataFormattingTests: XCTestCase {

    private func make(
        resolution: Size = Size(width: 1920, height: 1080),
        duration: TimeInterval = 75,
        dateTaken: Date = Date(timeIntervalSince1970: 1_700_000_000),
        dateTakenSource: DateSource = .embedded,
        location: GpsCoordinates? = GpsCoordinates(latitude: 37.7749, longitude: -122.4194),
        orientation: TiffOrientation? = .up,
        codec: String? = "HEVC",
        frameRate: Double? = 30,
        bitrate: Int? = 12_000_000,
        fileSize: Int64 = 5_000_000
    ) -> VideoMetaData {
        VideoMetaData(
            resolution: resolution, duration: duration, dateTaken: dateTaken,
            dateTakenSource: dateTakenSource, location: location, orientation: orientation,
            codec: codec, frameRate: frameRate, bitrate: bitrate, fileSize: fileSize)
    }

    func testResolutionString() {
        XCTAssertEqual(make().resolutionString, "1920 × 1080")
        XCTAssertEqual(make(resolution: Size(width: 0, height: 0)).resolutionString, "—")
    }

    func testDurationString() {
        XCTAssertEqual(make(duration: 75).durationString, "1:15")
        XCTAssertEqual(make(duration: 3661).durationString, "1:01:01")
        XCTAssertEqual(make(duration: 0).durationString, "—")
    }

    func testFrameRateString() {
        XCTAssertEqual(make(frameRate: 30).frameRateString, "30 fps")
        XCTAssertEqual(make(frameRate: nil).frameRateString, "—")
        XCTAssertEqual(make(frameRate: 0).frameRateString, "—")
    }

    func testBitrateString() {
        XCTAssertEqual(make(bitrate: 12_000_000).bitrateString, "12.0 Mbps")
        XCTAssertEqual(make(bitrate: 500_000).bitrateString, "500 Kbps")
        XCTAssertEqual(make(bitrate: nil).bitrateString, "—")
    }

    func testCodecString() {
        XCTAssertEqual(make(codec: "HEVC").codecString, "HEVC")
        XCTAssertEqual(make(codec: nil).codecString, "—")
    }

    func testLocationString() {
        XCTAssertEqual(
            make(location: GpsCoordinates(latitude: 37.7749, longitude: -122.4194)).locationString,
            "37.774900°N, 122.419400°W")
        XCTAssertEqual(make(location: nil).locationString, "—")
    }

    func testOrientationString() {
        XCTAssertEqual(make(orientation: .up).orientationString, "Normal")
        XCTAssertEqual(make(orientation: .right).orientationString, "Rotated 90° CW")
        XCTAssertEqual(make(orientation: nil).orientationString, "—")
    }

    func testDateFromFilenameFlag() {
        XCTAssertFalse(make(dateTakenSource: .embedded).isDateFromFilename)
        XCTAssertTrue(make(dateTakenSource: .filename).isDateFromFilename)
    }
}
