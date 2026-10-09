//
//  AVMetadataItemFactory.swift
//  SnapSafe
//
//  Builds the QuickTime common-metadata items embedded into recorded videos,
//  and the inverse helpers used to read them back. Shared by VideoCaptureService
//  (write) and SecureImageRepository (read).
//

import AVFoundation
import CoreLocation
import CoreMedia

internal enum AVMetadataItemFactory {

    internal static let softwareName = "SnapSafe"

    /// Build the common-metadata items to embed at record-time. The location
    /// item is omitted entirely when `location` is nil (permission denied or no
    /// fix); no other behavior changes.
    internal static func makeCaptureItems(location: CLLocation?, date: Date) -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []

        if let location {
            items.append(utf8Item(
                identifier: .commonIdentifierLocation,
                value: iso6709String(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude)))
        }

        items.append(utf8Item(
            identifier: .commonIdentifierCreationDate,
            value: iso8601Formatter.string(from: date)))

        items.append(utf8Item(
            identifier: .commonIdentifierSoftware,
            value: softwareName))

        return items
    }

    private static func utf8Item(identifier: AVMetadataIdentifier, value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        return item
    }

    // MARK: - ISO 6709 (single-point)

    /// ISO 6709 string, e.g. "+37.774900-122.419400/". Six fractional digits
    /// preserves the input to well within 1e-6 degrees (the read-path contract).
    internal static func iso6709String(latitude: Double, longitude: Double) -> String {
        String(format: "%+.6f%+.6f/", latitude, longitude)
    }

    private static let iso6709Regex = try? NSRegularExpression(
        pattern: #"([+-]\d+(?:\.\d+)?)([+-]\d+(?:\.\d+)?)"#)

    /// Parse the latitude/longitude out of an ISO 6709 string. Ignores any
    /// altitude component and the trailing solidus. Returns nil if the string
    /// does not contain two signed decimal numbers.
    internal static func parseISO6709(_ string: String) -> GpsCoordinates? {
        guard let regex = iso6709Regex else { return nil }
        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, range: range),
              let latRange = Range(match.range(at: 1), in: string),
              let lonRange = Range(match.range(at: 2), in: string),
              let lat = Double(string[latRange]),
              let lon = Double(string[lonRange]) else {
            return nil
        }
        return GpsCoordinates(latitude: lat, longitude: lon)
    }

    // MARK: - Date

    internal static func iso8601Date(from string: String) -> Date? {
        iso8601Formatter.date(from: string)
    }

    nonisolated(unsafe) private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Codec

    /// Human-readable codec name for a video track's media subtype FourCC.
    internal static func codecString(fromMediaSubType subType: FourCharCode) -> String {
        switch subType {
        case kCMVideoCodecType_HEVC: return "HEVC"
        case kCMVideoCodecType_H264: return "H.264"
        default: return fourCCString(subType)
        }
    }

    private static func fourCCString(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        let string = String(bytes: bytes, encoding: .ascii)?
            .trimmingCharacters(in: .whitespaces)
        return (string?.isEmpty == false ? string : nil) ?? "Unknown"
    }

    // MARK: - Orientation

    /// Decode a video track's preferredTransform into a TiffOrientation, mapping
    /// 0/90/180/270 degrees to .up(1)/.right(6)/.down(3)/.left(8). Non-right-angle
    /// rotations fall back to .up.
    internal static func videoOrientation(fromTransform transform: CGAffineTransform) -> TiffOrientation {
        let radians = atan2(transform.b, transform.a)
        let degrees = Int((radians * 180 / .pi).rounded())
        switch ((degrees % 360) + 360) % 360 {
        case 90: return .right
        case 180: return .down
        case 270: return .left
        default: return .up
        }
    }
}
