//
//  ImageProcessingTests.swift
//  SnapSafeTests
//

import XCTest
import ImageIO
import UIKit
@testable import SnapSafe

final class ImageProcessingTests: XCTestCase {

    private func solidImage(width: Int, height: Int) -> UIImage {
        let size = CGSize(width: width, height: height)
        UIGraphicsBeginImageContextWithOptions(size, true, 1)
        UIColor.red.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return image
    }

    func test_compressImageToJpeg_producesJpegMagicBytes() throws {
        let data = try XCTUnwrap(
            ImageProcessing.compressImageToJpeg(solidImage(width: 16, height: 16), quality: 0.9)
        )
        XCTAssertGreaterThan(data.count, 2)
        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8], "JPEG must start with the SOI marker")
    }

    func test_resizeImage_producesRequestedSize() {
        let resized = ImageProcessing.resizeImage(
            solidImage(width: 100, height: 80), to: CGSize(width: 25, height: 20))
        XCTAssertEqual(resized.size, CGSize(width: 25, height: 20))
    }

    func test_rotateImage_ninetyDegrees_swapsDimensions() {
        let rotated = ImageProcessing.rotateImage(solidImage(width: 40, height: 20), degrees: 90)
        XCTAssertEqual(Int(rotated.size.width), 20)
        XCTAssertEqual(Int(rotated.size.height), 40)
    }

    func test_cgImageOrientation_mapsDegrees() {
        XCTAssertEqual(ImageProcessing.cgImageOrientation(from: 0), .up)
        XCTAssertEqual(ImageProcessing.cgImageOrientation(from: 90), .right)
        XCTAssertEqual(ImageProcessing.cgImageOrientation(from: 180), .down)
        XCTAssertEqual(ImageProcessing.cgImageOrientation(from: 270), .left)
        XCTAssertEqual(ImageProcessing.cgImageOrientation(from: 45), .up)
    }

    func test_extractEXIFMetadata_roundTripsOrientationWrittenByApplyMetadata() throws {
        let jpeg = try XCTUnwrap(
            ImageProcessing.compressImageToJpeg(solidImage(width: 16, height: 16), quality: 0.9))
        let withMeta = ImageProcessing.applyImageMetadata(
            jpeg, location: nil, applyRotation: false, rotationDegrees: 90)
        let meta = ImageProcessing.extractEXIFMetadata(from: withMeta)
        let orientation = try XCTUnwrap(meta[kCGImagePropertyOrientation as String] as? Int)
        XCTAssertEqual(orientation, Int(CGImagePropertyOrientation.right.rawValue), "90° → .right")
    }

    func test_processImageWithEXIFMetadata_invalidData_throws() {
        XCTAssertThrowsError(
            try ImageProcessing.processImageWithEXIFMetadata(
                imageData: Data([0x00, 0x01]), preservedEXIFMetadata: [:], filename: "x"))
    }
}
