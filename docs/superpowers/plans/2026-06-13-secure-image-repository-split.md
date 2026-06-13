# SecureImageRepository Split — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decompose the 1,140-line `@MainActor SecureImageRepository` into a pure image utility, a storage data source, and a slim off-main `actor` repository that returns `Data`, aligning it with the SecureCameraAndroid layering.

**Architecture:** Three sequential, independently-shippable PRs. **This document fully specifies PR1** (extract `ImageProcessing`); PR2 and PR3 are scoped roadmaps at the end and will be expanded into full task detail once PR1 lands, because their exact edits depend on the realized post-PR1 code.

**Tech Stack:** Swift 6 (`SWIFT_APPROACHABLE_CONCURRENCY = YES`), UIKit/ImageIO, CryptoKit, XCTest, FactoryKit DI.

**Spec:** `docs/superpowers/specs/2026-06-13-secure-image-repository-split-design.md`

**Conventions for this plan:**
- Build (in-session): use the Xcode MCP `BuildProject` on tab `windowtab2`. CLI equivalent: `xcodebuild -project SnapSafe.xcodeproj -scheme SnapSafe -destination 'platform=iOS Simulator,name=iPhone 16' build` (adjust the simulator name to one installed locally).
- Run specific tests (in-session): Xcode MCP `RunSomeTests` on `windowtab2`. CLI equivalent: `xcodebuild ... test -only-testing:SnapSafeTests/<Class>`.
- No `try!` / `as!` anywhere (Codacy CRITICAL); tests use `throws` + `try XCTUnwrap`.
- "Move verbatim" means cut the method body unchanged; do not rewrite logic in PR1 (behavior must be identical).

---

## PR1 — Extract `ImageProcessing`

**Scope:** Move the pure UIKit/ImageIO image + EXIF helpers out of `SecureImageRepository` into a new stateless `ImageProcessing` namespace, and repoint the repo's call sites. The repository stays `@MainActor` and still returns `UIImage` — **no isolation or API change in this PR**. `readImageMetadata` (which drags in `ParsedImageMetadata`/`TiffOrientation`/`Size`) is intentionally deferred to PR2 to keep this PR a clean, dependency-light extraction.

**Methods moved (from `SnapSafe/Data/SecureImage/SecureImageRepository.swift`):**
`compressImageToJpeg` (219–221), `applyImageMetadata` (237–281), `cgImageOrientation` (284–291), `rotateImage` (337–356), `resizeImage` (433–439), `extractEXIFMetadata` (952–981), `processImageWithEXIFMetadata` (984–1025).

**Files:**
- Create: `SnapSafe/Data/SecureImage/ImageProcessing.swift`
- Create: `SnapSafeTests/ImageProcessingTests.swift`
- Modify: `SnapSafe/Data/SecureImage/SecureImageRepository.swift` (delete the 7 methods, repoint call sites at 319, 323, 328, 408, 931, 934)
- Modify: `SnapSafe.xcodeproj/project.pbxproj` (add both new files to their targets)

### Task 1: Create the `ImageProcessing` namespace

**Files:**
- Create: `SnapSafe/Data/SecureImage/ImageProcessing.swift`

- [ ] **Step 1: Verify `ImageRepositoryError` is module-accessible (not `private` nested)**

`processImageWithEXIFMetadata` throws `ImageRepositoryError.invalidImageData` / `.compressionFailed`. It is also thrown by the non-private `saveImage`/`readImage`, so it must already be at least `internal`. Confirm:

Run: `grep -rn "enum ImageRepositoryError" SnapSafe/`
Expected: a declaration that is NOT marked `private` (file- or module-scope). If it is `private` inside the repo class, move it to file scope in `SecureImageRepository.swift` (delete `private`) before proceeding.

- [ ] **Step 2: Create `ImageProcessing.swift` with the moved methods**

```swift
//
//  ImageProcessing.swift
//  SnapSafe
//
//  Pure image/EXIF utilities extracted from SecureImageRepository. No file I/O,
//  no encryption, no shared state — a stateless namespace so callers (and the
//  off-main repository actor in a later phase) can run CPU-bound image work
//  without touching the data or UI layers.
//
//  NOTE: rotate/resize use the UIGraphics image-context API exactly as the
//  original code did. These run on the caller's context today (the repository
//  is still @MainActor). When the repository becomes an off-main actor in PR3,
//  re-verify thread safety or migrate these two to UIGraphicsImageRenderer.
//

import CoreLocation
import ImageIO
import UIKit
import UniformTypeIdentifiers

enum ImageProcessing {

    /// Compresses a UIImage to JPEG data with the given quality.
    static func compressImageToJpeg(_ image: UIImage, quality: CGFloat) -> Data? {
        image.jpegData(compressionQuality: quality)
    }

    /// Rotates a UIImage by the given degrees.
    static func rotateImage(_ image: UIImage, degrees: Int) -> UIImage {
        let radians = CGFloat(degrees) * .pi / 180

        var newSize = CGRect(origin: CGPoint.zero, size: image.size)
            .applying(CGAffineTransform(rotationAngle: radians)).size
        newSize.width = floor(newSize.width)
        newSize.height = floor(newSize.height)

        UIGraphicsBeginImageContextWithOptions(newSize, false, image.scale)
        let context = UIGraphicsGetCurrentContext()!

        context.translateBy(x: newSize.width / 2, y: newSize.height / 2)
        context.rotate(by: radians)

        image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2,
                              width: image.size.width, height: image.size.height))

        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage ?? image
    }

    /// Resizes a UIImage to the specified size.
    static func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resizedImage ?? image
    }

    /// Converts rotation degrees to CGImagePropertyOrientation.
    static func cgImageOrientation(from degrees: Int) -> CGImagePropertyOrientation {
        switch degrees {
        case 90: return .right
        case 180: return .down
        case 270: return .left
        default: return .up
        }
    }

    /// Writes timestamp / orientation / GPS metadata into JPEG data.
    static func applyImageMetadata(
        _ imageData: Data,
        location: CLLocation?,
        applyRotation: Bool,
        rotationDegrees: Int
    ) -> Data {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return imageData
        }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return imageData
        }

        var properties: [String: Any] = [:]

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        properties[kCGImagePropertyExifDateTimeOriginal as String] = formatter.string(from: Date())

        if !applyRotation {
            let orientation = cgImageOrientation(from: rotationDegrees)
            properties[kCGImagePropertyOrientation as String] = orientation.rawValue
        }

        if let location = location {
            let gpsInfo: [String: Any] = [
                kCGImagePropertyGPSLatitude as String: abs(location.coordinate.latitude),
                kCGImagePropertyGPSLatitudeRef as String: location.coordinate.latitude >= 0 ? "N" : "S",
                kCGImagePropertyGPSLongitude as String: abs(location.coordinate.longitude),
                kCGImagePropertyGPSLongitudeRef as String: location.coordinate.longitude >= 0 ? "E" : "W"
            ]
            properties[kCGImagePropertyGPSDictionary as String] = gpsInfo
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        CGImageDestinationFinalize(destination)

        return mutableData as Data
    }

    /// Extracts orientation/EXIF/TIFF/GPS metadata dictionaries from JPEG data.
    static func extractEXIFMetadata(from imageData: Data) -> [String: Any] {
        var exifMetadata: [String: Any] = [:]

        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else {
            return exifMetadata
        }

        if let orientation = imageProperties[kCGImagePropertyOrientation as String] as? Int {
            exifMetadata[kCGImagePropertyOrientation as String] = orientation
        }
        if let exifDict = imageProperties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exifMetadata[kCGImagePropertyExifDictionary as String] = exifDict
        }
        if let tiffDict = imageProperties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            exifMetadata[kCGImagePropertyTIFFDictionary as String] = tiffDict
        }
        if let gpsDict = imageProperties[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
            exifMetadata[kCGImagePropertyGPSDictionary as String] = gpsDict
        }

        return exifMetadata
    }

    /// Re-encodes image data to JPEG, preserving the supplied EXIF metadata.
    static func processImageWithEXIFMetadata(
        imageData: Data,
        preservedEXIFMetadata: [String: Any],
        filename _: String
    ) throws -> Data {
        guard let image = UIImage(data: imageData) else {
            throw ImageRepositoryError.invalidImageData
        }

        guard let jpegData = image.jpegData(compressionQuality: 0.9) else {
            throw ImageRepositoryError.compressionFailed
        }

        if preservedEXIFMetadata.isEmpty {
            return jpegData
        }

        let mutableData = NSMutableData(data: jpegData)
        let type = UTType.jpeg.identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(mutableData as CFMutableData, type, 1, nil) else {
            return jpegData
        }

        guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return jpegData
        }

        CGImageDestinationAddImage(destination, cgImage, preservedEXIFMetadata as CFDictionary)

        if CGImageDestinationFinalize(destination) {
            return mutableData as Data
        }

        return jpegData
    }
}
```

- [ ] **Step 3: Add `ImageProcessing.swift` to the `SnapSafe` app target**

In Xcode, ensure the new file's Target Membership includes `SnapSafe`. (Creating via the Xcode MCP `XcodeWrite` adds it automatically; a raw filesystem write does not.)

Run: `grep -c "ImageProcessing.swift" SnapSafe.xcodeproj/project.pbxproj`
Expected: `>= 2` (one `PBXFileReference`, one `PBXBuildFile` in Sources).

- [ ] **Step 4: Build to confirm `ImageProcessing` compiles**

Run: Xcode MCP `BuildProject` (tab `windowtab2`).
Expected: `The project built successfully.` (The repo still has its own copies of these methods — duplication is expected and fine until Task 3.)

### Task 2: Add `ImageProcessingTests`

**Files:**
- Create: `SnapSafeTests/ImageProcessingTests.swift`

- [ ] **Step 1: Write the tests**

```swift
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
        // applyImageMetadata writes the orientation only when applyRotation == false.
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
```

- [ ] **Step 2: Add the test file to the `SnapSafeTests` target**

This project has a history of test files silently not being target members. Verify:

Run: `grep -c "ImageProcessingTests.swift" SnapSafe.xcodeproj/project.pbxproj`
Expected: `>= 2`.

- [ ] **Step 3: Run the tests — expect PASS**

Run: Xcode MCP `RunSomeTests` (tab `windowtab2`) for `SnapSafeTests/ImageProcessingTests`.
Expected: 6 tests, all pass. (The functions already exist from Task 1, so these pass immediately — they are characterization tests locking in current behavior before we repoint the repo.)

- [ ] **Step 4: Commit**

```bash
git add SnapSafe/Data/SecureImage/ImageProcessing.swift SnapSafeTests/ImageProcessingTests.swift SnapSafe.xcodeproj/project.pbxproj
git commit -m "refactor(secureimage): add ImageProcessing namespace + tests"
```

### Task 3: Repoint `SecureImageRepository` to `ImageProcessing` and delete the moved methods

**Files:**
- Modify: `SnapSafe/Data/SecureImage/SecureImageRepository.swift`

- [ ] **Step 1: Repoint the six call sites**

Apply these exact replacements:

- Line 319: `processedImage = rotateImage(image.sensorBitmap, degrees: image.rotationDegrees)`
  → `processedImage = ImageProcessing.rotateImage(image.sensorBitmap, degrees: image.rotationDegrees)`
- Line 323: `guard let jpegData = compressImageToJpeg(processedImage, quality: quality) else {`
  → `guard let jpegData = ImageProcessing.compressImageToJpeg(processedImage, quality: quality) else {`
- Line 328: `let updatedData = applyImageMetadata(jpegData, location: location, applyRotation: applyRotation, rotationDegrees: image.rotationDegrees)`
  → `let updatedData = ImageProcessing.applyImageMetadata(jpegData, location: location, applyRotation: applyRotation, rotationDegrees: image.rotationDegrees)`
- Line 408: `thumbnailImage = resizeImage(fullImage, to: thumbnailSize)`
  → `thumbnailImage = ImageProcessing.resizeImage(fullImage, to: thumbnailSize)`
- Line 931: `let existingMetadata = extractEXIFMetadata(from: existingImageData)`
  → `let existingMetadata = ImageProcessing.extractEXIFMetadata(from: existingImageData)`
- Line 934–938: `let processedData = try processImageWithEXIFMetadata(` → `let processedData = try ImageProcessing.processImageWithEXIFMetadata(` (arguments unchanged)

- [ ] **Step 2: Delete the now-duplicated private methods from the repository**

Delete these method definitions from `SecureImageRepository.swift` (now living in `ImageProcessing`):
`compressImageToJpeg` (219–221), `applyImageMetadata` (237–281), `cgImageOrientation` (284–291), `rotateImage` (337–356), `resizeImage` (433–439), `extractEXIFMetadata` (952–981), `processImageWithEXIFMetadata` (984–1025).

Do **not** delete `encryptToFile`, `decryptFile`, `encryptAndSaveImage`, `getThumbnailFile`, `readImageMetadata`, or any non-listed method.

- [ ] **Step 3: Build — expect success**

Run: Xcode MCP `BuildProject` (tab `windowtab2`).
Expected: `The project built successfully.` If the build complains that `readImageMetadata` references a now-missing helper, stop — `readImageMetadata` was deferred and must remain in the repo untouched.

- [ ] **Step 4: Run the full repository + image test suites — expect PASS**

Run: Xcode MCP `RunSomeTests` for `SnapSafeTests/SecureImageRepositoryTests` and `SnapSafeTests/ImageProcessingTests`.
Expected: all pass (behavior unchanged — the methods only moved).

- [ ] **Step 5: Confirm the repository shrank and no image helpers remain**

Run: `grep -nE "func (compressImageToJpeg|rotateImage|resizeImage|cgImageOrientation|applyImageMetadata|extractEXIFMetadata|processImageWithEXIFMetadata)" SnapSafe/Data/SecureImage/SecureImageRepository.swift`
Expected: no output (all moved). `readImageMetadata` is expected to still be present.

- [ ] **Step 6: Commit**

```bash
git add SnapSafe/Data/SecureImage/SecureImageRepository.swift
git commit -m "refactor(secureimage): route image work through ImageProcessing"
```

**PR1 done.** The repository is ~150 lines lighter, the UIKit/ImageIO rendering + EXIF logic is isolated and independently tested, and behavior is unchanged.

---

## PR2 — Extract `PhotoStorageDataSource` (roadmap)

To be expanded into full task detail after PR1 lands. Scope:

- New `SnapSafe/Data/SecureImage/PhotoStorageDataSource.swift` owning: the directory layout (`getGalleryDirectory`, `getDecoyDirectory`, `getVideosDirectory`, `getVideoThumbnailsDirectory`, `getDecoyVideoThumbnailsDirectory`, `getThumbnailsDirectory`) with `isExcludedFromBackup`; raw encrypted file I/O (`encryptToFile`, `decryptFile`, `encryptAndSaveImage`); and file enumeration/delete used by `getPhotos`, `getDecoyFiles`, video file listing, etc. Depends on `EncryptionScheme` + `FileManager`.
- `SecureImageRepository` delegates all path + file I/O to the data source; still `@MainActor`, still returns `UIImage`.
- Also move `readImageMetadata` + relocate its value types (`ParsedImageMetadata`, `TiffOrientation`, `Size`, `GpsCoordinates`) to module scope, then move `readImageMetadata` into `ImageProcessing` (deferred from PR1).
- New `SnapSafeTests/PhotoStorageDataSourceTests.swift`: encrypted write→read round-trip, directory creation + backup exclusion, enumeration, delete.
- Each step keeps build + `SecureImageRepositoryTests` green.

## PR3 — Actor conversion + `Data` boundary (roadmap)

To be expanded into full task detail after PR2 lands. Scope:

- Make `SecureImageRepository` an `actor` (drop `@MainActor`); ensure no `import UIKit` remains.
- Change read APIs to return `Data`: `readImage -> Data`, `readThumbnail -> Data?`, `readVideoThumbnail -> Data?` (callers decode `UIImage(data:)`).
- Make `ThumbnailCache` a `Sendable final class` (documented `@unchecked Sendable` over thread-safe `NSCache`); move the decoded-`UIImage` cache to the VM/UI layer. The repository may keep an internal `Data` cache if re-decrypt cost warrants.
- Fix actor reentrancy on read-through paths (capture locals across `await`; optionally coalesce in-flight loads).
- Re-verify `rotateImage`/`resizeImage` thread safety off the main actor; migrate to `UIGraphicsImageRenderer` if needed.
- Route `PhotoCell` + `SecureGalleryView` through the shared `MixedMediaGalleryViewModel` via `.task(id: photo.id)` (cancels on reuse/scroll); remove their `@Injected(\.secureImageRepository)`. Adapt `VideoPlayerView` minimally to compile (full extraction is a separate P2 effort).
- Verify `VideoEncryptionServiceProtocol` is `Sendable`.
- Adjust `SecureImageRepositoryTests` for `Data` returns; add a task-group reentrancy/concurrency test mirroring the `AuthorizationRepository` pattern.

---

## Self-review (against the spec)

- **Spec coverage:** PR1 implements the `ImageProcessing` component (spec §Components.1) fully; PR2 covers `PhotoStorageDataSource` (§Components.2); PR3 covers the `actor` repo + `Data` boundary + `ThumbnailCache` + per-cell loading (§Components.3–4, §Required collaborator changes, §Concurrency & SwiftUI review notes). All spec sections map to a PR.
- **Placeholders:** PR1 contains complete code for every changed file and exact call-site edits. PR2/PR3 are explicitly labeled roadmaps (not executable tasks yet) by design — to be expanded post-PR1.
- **Type consistency:** `ImageProcessing` method names match the originals exactly (`compressImageToJpeg`, `rotateImage`, `resizeImage`, `cgImageOrientation`, `applyImageMetadata`, `extractEXIFMetadata`, `processImageWithEXIFMetadata`), so call-site edits are pure `ImageProcessing.` prefixes. `ImageRepositoryError` is reused, not redefined.
