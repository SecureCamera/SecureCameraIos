# Video Info Sheet

**Date:** 2026-06-14
**Branch:** video

## Problem

The photo detail view has an Info sheet (`ImageInfoView`) showing filename, dimensions, file size, capture date, orientation, GPS location, and camera-specific EXIF (make/model, aperture, shutter, ISO, focal length). The video detail view has no equivalent — there is no Info button on the video toolbar and no way for a user to see when or where a video was captured. The video capture pipeline also doesn't sample location at all: `VideoCaptureService` never touches `LocationRepository` and never writes `AVMetadataItem` to the output `.mov`, so no embedded GPS exists for any SnapSafe-captured video.

## Goal

Add an Info sheet for videos that mirrors `ImageInfoView`, with capture metadata (location + creation date) embedded in the `.mov` at record-time and a video-specific technical section (duration, codec, frame rate, bitrate) replacing the photo's camera-specific section.

## Non-goals

- No timed/path location track. A single coordinate sampled at record-start, matching how photos sample at shutter press and matching Apple Camera.app's ISO 6709 single-point convention.
- No migration of existing videos. Pre-feature SnapSafe recordings get the technical section (from `AVAsset`) plus a filename-derived capture date; their location section shows "—".
- No stripping of metadata in imported videos. If a `.mov` brought in via import already has GPS, we display it; we never strip user data.
- No raw "All Metadata" debug dump (the expandable section at the bottom of `ImageInfoView`).
- No change to the share/export path. Shared videos keep whatever metadata the encrypted source had, mirroring how shared photos keep their EXIF.

## Architecture

### Capture path

`VideoCaptureService.startRecording()` (`SnapSafe/Screens/Camera/Services/VideoCaptureService.swift`) currently calls `movieFileOutput.startRecording(to:recordingDelegate:)` with no metadata setup. Change:

1. Inject `LocationRepository` into `VideoCaptureService` (mirrors `PhotoCaptureService`'s constructor injection in `SnapSafe/Screens/Camera/Services/PhotoCaptureService.swift`).
2. Immediately before `startRecording`, sample `let location = locationRepository.lastLocation`.
3. Build `[AVMetadataItem]` via a new `AVMetadataItemFactory.makeCaptureItems(location:date:)`. Set `movieFileOutput.metadata = items`.
4. `AVCaptureMovieFileOutput` writes the items into the QuickTime header of the output `.mov` during recording. No post-record mutation pass needed.

`AVMetadataItemFactory` produces:
- `kCommonIdentifierLocation` — ISO 6709 string (e.g., `+37.7749-122.4194/`) when `location != nil`; omitted otherwise.
- `kCommonIdentifierCreationDate` — capture date, ISO 8601.
- `kCommonIdentifierSoftware` — `"SnapSafe"` (constant).

If location permission was denied or no fix is available, `lastLocation` is `nil` and the location item is simply omitted. No new permission UX.

After recording finishes, the existing `encryptRecordedVideo` callback encrypts the tagged plaintext `.mov` into `.secv`. The metadata travels inside the encrypted bytes — same trust model as photo EXIF inside an encrypted JPEG.

### Read path

New repository method on `SecureImageRepository`:

```swift
func getVideoMetaData(_ videoDef: VideoDef) async throws -> VideoMetaData
```

Lives next to the existing `getPhotoMetaData` (`SnapSafe/Data/SecureImage/SecureImageRepository.swift:663`).

Flow:
1. File size from disk via `FileManager.default.attributesOfItem`.
2. Build an `AVAsset`. For `.secv`: use `EncryptedVideoDataSource` (the existing `AVAssetResourceLoaderDelegate`) so we read from the in-memory decrypted stream without writing a temp plaintext file. For imported `.mov` (non-encrypted): use the file URL directly.
3. `await asset.load(.commonMetadata, .duration, .tracks)`.
4. Walk `commonMetadata`: find `kCommonIdentifierLocation` → parse ISO 6709 → `GpsCoordinates`. If absent, location = `nil`.
5. Find `kCommonIdentifierCreationDate` → `Date` (`dateTakenSource = .embedded`). If absent, fall back to `videoDef.dateTaken()` which parses the filename (`dateTakenSource = .filename`). If both are unavailable, use `Date(timeIntervalSince1970: 0)` — matches the photo behavior at `SecureImageRepository.getPhotoMetaData` line ~665.
6. From the first video track: `naturalSize` → resolution; `nominalFrameRate` → frame rate; `estimatedDataRate` → bitrate; `formatDescriptions[0]` FourCC → human codec string (e.g., `"hvc1"` → `"HEVC"`, `"avc1"` → `"H.264"`).
7. Compute orientation from `track.preferredTransform`. Decode the rotation angle (0° / 90° / 180° / 270°) and map to the existing `TiffOrientation` enum used by photos (1 / 6 / 3 / 8 respectively). Non-90°-multiple rotations are rare in practice; map to `.up` (1) as a safe default.
8. Pack into `VideoMetaData` and return.

### New types

`SnapSafe/Data/Models/VideoMetaData.swift`:

```swift
struct VideoMetaData {
    let resolution: Size
    let duration: TimeInterval
    let dateTaken: Date
    let dateTakenSource: DateSource   // .embedded or .filename — UI shows "(from filename)" hint for .filename
    let location: GpsCoordinates?
    let orientation: TiffOrientation?
    let codec: String?
    let frameRate: Double?
    let bitrate: Int?                  // bits per second
    let fileSize: Int64
}

enum DateSource { case embedded, filename }
```

### UI

**`Screens/PhotoDetail/VideoInfoView.swift`** (new) — same section grouping as `ImageInfoView`, same `LabeledContent` row style:

- **Basic** — filename, resolution, file size
- **Date** — capture date (with a small "(from filename)" footnote when `dateTakenSource == .filename`)
- **Orientation** — orientation string
- **Location** — formatted lat/long with N/S/E/W, or "—"
- **Video** (replaces photo's Camera section) — duration (mm:ss or h:mm:ss), codec, frame rate (e.g., "30 fps"), bitrate (e.g., "12 Mbps")

**`Screens/PhotoDetail/VideoInfoViewModel.swift`** (new) — mirrors `ImageInfoViewModel`. Initializes with a `VideoDef`, injects `SecureImageRepository`, calls `getVideoMetaData` in a `task`, exposes computed display strings.

**`Screens/PhotoDetail/MediaDetailToolbar.swift`** — add an Info button to the video toolbar (currently Share / Decoy / Delete, lines 61–93). Leading position, matching the photo toolbar's Info button placement. Calls `onInfo` like the photo path.

**`Util/AppNavigation.swift`** — add `case videoInfo(VideoDef)` to the sheet enum (mirrors `case photoInfo(PhotoDef)`).

**`Screens/ContentView.swift`** — render `VideoInfoView(videoDef:)` for the new sheet case (mirrors the photo case at line 125).

**`Screens/PhotoDetail/EnhancedPhotoDetailView.swift`** — wire `onInfo: { nav.presentSheet(.videoInfo(currentVideoDef)) }` in the video branch.

**`Localizable.xcstrings`** — new strings for the video-section labels (Duration, Codec, Frame Rate, Bitrate). All other labels (Filename, Resolution, File Size, Date Taken, Orientation, Location, etc.) are already in the catalog from the photo info sheet and are reused as-is.

**`Util/AVMetadataItemFactory.swift`** is placed under `SnapSafe/Util/` so it's reachable from both `VideoCaptureService` (write side) and `SecureImageRepository` (read side, if shared ISO-6709 parsing helpers live there).

### Dependency wiring

`VideoCaptureService` constructor gains a `LocationRepository` parameter. Update the call site (wherever it's currently constructed — likely `CameraView` or a Factory) to pass it. `LocationRepository` is already shared with `PhotoCaptureService`, so no new singleton.

## Error handling

- `getVideoMetaData` is `async throws`. Underlying failures (file missing, decryption error, AVAsset load timeout) propagate up. `VideoInfoViewModel` catches and shows a single error row in place of the sections, matching how `ImageInfoViewModel` handles its load failures.
- Missing-metadata case is NOT an error — it's the documented fallback path (location = nil, date from filename).
- Best-effort field parsing: if an individual track field (e.g., `nominalFrameRate`) is `0` or unavailable, the corresponding `VideoMetaData` field is `nil` and the UI shows "—" for that row. One bad field doesn't fail the sheet.

## Testing

Unit:
- `AVMetadataItemFactory.makeCaptureItems` produces `kCommonIdentifierLocation` in ISO 6709 format for representative coordinates (positive/negative lat, positive/negative long, near-zero), and omits the location item when `location: nil`.
- `AVMetadataItemFactory.makeCaptureItems` produces `kCommonIdentifierCreationDate` matching the input `Date`.
- ISO 6709 round-trip: `GpsCoordinates → AVMetadataItem → parsed back → GpsCoordinates` preserves coordinates to within `1e-6` degrees.

Integration:
- **Round-trip with metadata**: Build a synthetic `.mov` via `AVAssetWriter` with the factory's items, encrypt via `VideoEncryptionService.encryptVideoForDecoy`, then call `getVideoMetaData` on the resulting `VideoDef`. Assert: location matches, date matches, resolution matches, duration matches.
- **Backwards-compat**: Encrypt a `.mov` *without* any custom metadata, call `getVideoMetaData`. Assert: location is `nil`, `dateTakenSource == .filename`, `dateTaken` matches the value parsed from the filename, technical fields (resolution, duration, codec) still populated.
- **Imported video**: Take a `.mov` with pre-existing GPS metadata (constructed via `AVAssetWriter` with a different `kCommonIdentifierLocation`), encrypt via the import path, call `getVideoMetaData`. Assert: pre-existing GPS is preserved and returned.

No new UI tests (existing pattern: ImageInfoView has no unit tests; manual verification on the simulator covers the sheet rendering).

## Out of scope (deferred)

- Editing metadata (no UI to change a video's capture date or location after-the-fact).
- "All Metadata" debug dump section (could be added later; mirrors a deferred photo nicety).
- SECV format version / encrypted file size / chunk count display.
- Per-clip metadata refresh on the file (the metadata is whatever was captured; no later edits).
