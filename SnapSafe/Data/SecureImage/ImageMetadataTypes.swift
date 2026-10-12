//
//  ImageMetadataTypes.swift
//  SnapSafe
//
//  Value types describing image metadata parsed from JPEG data. Shared between
//  ImageProcessing (which parses them) and SecureImageRepository (which surfaces
//  them via PhotoMetaData).
//

struct ParsedImageMetadata {
    let width: Int?
    let height: Int?
    let orientation: TiffOrientation?
    let gps: GpsCoordinates?
}

struct Size {
    let width: Int
    let height: Int
}

enum TiffOrientation: Int {
    case up = 1, upMirrored = 2, down = 3, downMirrored = 4
    case leftMirrored = 5, right = 6, rightMirrored = 7, left = 8
}

struct GpsCoordinates {
    let latitude: Double
    let longitude: Double
}
