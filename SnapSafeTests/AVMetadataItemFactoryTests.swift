//
//  AVMetadataItemFactoryTests.swift
//  SnapSafeTests
//

import XCTest
import AVFoundation
import CoreLocation
@testable import SnapSafe

final class AVMetadataItemFactoryTests: XCTestCase {

    // MARK: - makeCaptureItems

    func testMakeCaptureItemsIncludesLocationCreationDateAndSoftware() async throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let location = CLLocation(latitude: 37.7749, longitude: -122.4194)

        let items = AVMetadataItemFactory.makeCaptureItems(location: location, date: date)

        let locationItem = AVMetadataItem.metadataItems(
            from: items, filteredByIdentifier: .commonIdentifierLocation).first
        let dateItem = AVMetadataItem.metadataItems(
            from: items, filteredByIdentifier: .commonIdentifierCreationDate).first
        let softwareItem = AVMetadataItem.metadataItems(
            from: items, filteredByIdentifier: .commonIdentifierSoftware).first

        XCTAssertNotNil(locationItem, "Location item should be present when a location is supplied")
        XCTAssertNotNil(dateItem, "Creation date item should always be present")
        let softwareValue = try await softwareItem?.load(.stringValue)
        XCTAssertEqual(softwareValue, "SnapSafe",
                       "Software item should be the constant app name")
    }

    func testMakeCaptureItemsOmitsLocationWhenNil() {
        let items = AVMetadataItemFactory.makeCaptureItems(
            location: nil, date: Date(timeIntervalSince1970: 0))

        let locationItem = AVMetadataItem.metadataItems(
            from: items, filteredByIdentifier: .commonIdentifierLocation).first
        XCTAssertNil(locationItem,
                     "Location item must be omitted when no location is available; got \(String(describing: locationItem))")
    }

    func testCreationDateItemMatchesInputDate() async throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let items = AVMetadataItemFactory.makeCaptureItems(location: nil, date: date)

        let dateItem = try XCTUnwrap(AVMetadataItem.metadataItems(
            from: items, filteredByIdentifier: .commonIdentifierCreationDate).first)
        let rawOptional = try await dateItem.load(.stringValue)
        let raw = try XCTUnwrap(rawOptional)
        let parsed = try XCTUnwrap(AVMetadataItemFactory.iso8601Date(from: raw))

        XCTAssertEqual(parsed.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 1.0,
                       "Round-tripped creation date \(parsed) should match input \(date) to the second")
    }

    // MARK: - ISO 6709

    func testISO6709RoundTripPreservesCoordinates() {
        let samples: [(Double, Double)] = [
            (37.7749, -122.4194),
            (-33.8688, 151.2093),
            (0.000001, -0.000002),
            (-51.5, -0.12)
        ]
        for (lat, lon) in samples {
            let string = AVMetadataItemFactory.iso6709String(latitude: lat, longitude: lon)
            let parsed = AVMetadataItemFactory.parseISO6709(string)
            XCTAssertEqual(parsed?.latitude ?? .nan, lat, accuracy: 1e-6,
                           "latitude round-trip failed for \(string): got \(String(describing: parsed?.latitude))")
            XCTAssertEqual(parsed?.longitude ?? .nan, lon, accuracy: 1e-6,
                           "longitude round-trip failed for \(string): got \(String(describing: parsed?.longitude))")
        }
    }

    func testParseISO6709ReturnsNilForGarbage() {
        XCTAssertNil(AVMetadataItemFactory.parseISO6709("not a coordinate"))
        XCTAssertNil(AVMetadataItemFactory.parseISO6709(""))
    }

    // MARK: - Codec mapping

    func testCodecStringMapsKnownFourCCs() {
        let hevc = AVMetadataItemFactory.codecString(fromMediaSubType: kCMVideoCodecType_HEVC)
        XCTAssertEqual(hevc, "HEVC", "Expected HEVC for kCMVideoCodecType_HEVC, got \(hevc)")
        let h264 = AVMetadataItemFactory.codecString(fromMediaSubType: kCMVideoCodecType_H264)
        XCTAssertEqual(h264, "H.264", "Expected H.264 for kCMVideoCodecType_H264, got \(h264)")
    }

    func testCodecStringFallsBackToFourCCStringForUnknownSubType() {
        // 'abcd' as a FourCharCode: 0x61626364
        let code: FourCharCode = 0x6162_6364
        let result = AVMetadataItemFactory.codecString(fromMediaSubType: code)
        XCTAssertEqual(result, "abcd", "Unknown subtype should fall back to its FourCC string, got \(result)")
    }

    // MARK: - Orientation mapping

    func testOrientationFromTransformMapsRotationAngles() {
        XCTAssertEqual(AVMetadataItemFactory.videoOrientation(fromTransform: .identity), .up)
        XCTAssertEqual(AVMetadataItemFactory.videoOrientation(
            fromTransform: CGAffineTransform(rotationAngle: .pi / 2)), .right)
        XCTAssertEqual(AVMetadataItemFactory.videoOrientation(
            fromTransform: CGAffineTransform(rotationAngle: .pi)), .down)
        XCTAssertEqual(AVMetadataItemFactory.videoOrientation(
            fromTransform: CGAffineTransform(rotationAngle: -.pi / 2)), .left)
    }
}
