//
//  VideoMetaData.swift
//  SnapSafe
//
//  Structured metadata for a video, surfaced by SecureImageRepository and
//  rendered by VideoInfoView. Mirrors SecureImageRepository.PhotoMetaData plus
//  video-specific technical fields.
//

import Foundation

enum DateSource {
    case embedded   // read from the file's kCommonIdentifierCreationDate
    case filename   // derived from the video_yyyyMMdd_HHmmss filename
}

struct VideoMetaData {
    let resolution: Size
    let duration: TimeInterval
    let dateTaken: Date
    let dateTakenSource: DateSource
    let location: GpsCoordinates?
    let orientation: TiffOrientation?
    let codec: String?
    let frameRate: Double?
    let bitrate: Int?          // bits per second
    let fileSize: Int64
}

// MARK: - Display strings

extension VideoMetaData {

    /// Shown in rows when the underlying value is missing/unavailable.
    static let unavailable = "—"

    var resolutionString: String {
        guard resolution.width > 0, resolution.height > 0 else { return Self.unavailable }
        return "\(resolution.width) × \(resolution.height)"
    }

    var fileSizeString: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    var dateTakenString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: dateTaken)
    }

    var isDateFromFilename: Bool { dateTakenSource == .filename }

    var orientationString: String {
        guard let orientation else { return Self.unavailable }
        switch orientation {
        case .up: return "Normal"
        case .down: return "Rotated 180°"
        case .right: return "Rotated 90° CW"
        case .left: return "Rotated 90° CCW"
        default: return "Normal"
        }
    }

    var locationString: String {
        guard let location else { return Self.unavailable }
        let lat = String(format: "%.6f°%@", abs(location.latitude), location.latitude >= 0 ? "N" : "S")
        let lon = String(format: "%.6f°%@", abs(location.longitude), location.longitude >= 0 ? "E" : "W")
        return "\(lat), \(lon)"
    }

    var durationString: String {
        guard duration > 0 else { return Self.unavailable }
        return duration.formattedTime   // existing TimeInterval extension (VideoPlayerView.swift)
    }

    var codecString: String { codec ?? Self.unavailable }

    var frameRateString: String {
        guard let frameRate, frameRate > 0 else { return Self.unavailable }
        return String(format: "%.0f fps", frameRate)
    }

    var bitrateString: String {
        guard let bitrate, bitrate > 0 else { return Self.unavailable }
        let mbps = Double(bitrate) / 1_000_000
        if mbps >= 1 { return String(format: "%.1f Mbps", mbps) }
        return String(format: "%.0f Kbps", Double(bitrate) / 1_000)
    }
}
