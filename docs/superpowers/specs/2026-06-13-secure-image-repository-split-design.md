# SecureImageRepository "Full Clean" split (P1) — Design

**Date:** 2026-06-13
**Branch:** `refactor/secure-image-repository-split` (off `video`)
**Status:** approved

## Context

`SecureImageRepository` (`SnapSafe/Data/SecureImage/SecureImageRepository.swift`) is a
1,140-line `@MainActor class` that conflates four responsibilities: filesystem path
management, raw encrypted file I/O, UIKit/ImageIO image processing, and photo/video/decoy
domain logic. It is `import UIKit`, returns `UIImage` from the data layer, and runs all disk
+ crypto on the main thread. It is the top structural finding (P1) of the
[architecture audit vs. SecureCameraAndroid](../../../../notes/bill-dev-notes/Projects/SnapSafe/design/architecture-audit-vs-android.md),
which measured SnapSafe against the Kotlin app
[SecureCamera/SecureCameraAndroid](https://github.com/SecureCamera/SecureCameraAndroid).

This refactor aligns the type with that app's Clean-Architecture layering: data sources do
only data handling, repositories hold core domain functions off the main thread, and image
decoding is a UI-boundary concern.

## Goal

Decompose the god-class into three focused units and route the gallery thumbnail views
through their ViewModels:

1. A pure image utility (no I/O, no crypto).
2. A storage data source (the single filesystem touchpoint for media).
3. A slim, off-main `actor` repository that returns `Data` (not `UIImage`).

## Decisions (locked during brainstorming)

- **Scope:** Full Clean split — responsibility split **plus** drop `@MainActor` (→ `actor`)
  **plus** repo deals in `Data`, with `UIImage` decode moving to the ViewModel boundary.
- **P2 coupling:** Fix the gallery thumbnail call sites (`PhotoCell`, `SecureGalleryView`) by
  routing them through their ViewModels. Adapt `VideoPlayerView` only enough to compile; its
  full logic extraction is a separate, deferred P2 effort.

## Target components

### 1. `ImageProcessing` — pure, stateless, `nonisolated` / `Sendable`
Holds all UIKit/ImageIO work currently in the repo: JPEG compression, rotation,
resize/downscale, EXIF extract/apply, `CGImagePropertyOrientation` mapping, image-metadata
parsing, and `UIImage.sensorBitmap` handling. Boundary types are `Data` in / `Data` out
wherever possible; `UIImage`/`CGImage` stay internal. No file I/O, no encryption.
Independently unit-testable. Lives in `SnapSafe/Data/SecureImage/ImageProcessing.swift`.

### 2. `PhotoStorageDataSource` — data handling only
Owns the directory layout (`photos`, `decoys`, `videos`, `videoThumbnails`,
`decoyVideoThumbnails`, `.thumbnails`), directory creation + `isExcludedFromBackup` resource
values, raw encrypted file I/O (`encryptToFile`, `decryptFile`), and file enumeration / delete.
Depends on `EncryptionScheme` (already `Sendable`) + `FileManager`. Becomes the single place
that touches the filesystem for media — and the future home for the P3 `FileManager` work now
in `MixedMediaGalleryViewModel` / `CameraViewModel` (seam created here, not filled).

### 3. `SecureImageRepository` (slimmed) → `actor`
Core domain functions only: photo / video / decoy / poison-pill operations, `getPhotos`,
deletes, save / update, metadata. Coordinates `PhotoStorageDataSource` (I/O) + `ImageProcessing`
(CPU) + `EncryptionScheme`. No `@MainActor`. **Read APIs return `Data`**, not `UIImage`
(`readImage` → `Data`, `readThumbnail` → `Data?`, `readVideoThumbnail` → `Data?`,
`getPhotoMetaData` → `PhotoMetaData`).

### 4. ViewModel boundary
ViewModels decode `Data → UIImage` on `@MainActor` for display and expose it via `@Published`.

## Required collaborator change

`ThumbnailCache` is a `@MainActor class`; for the repo to be a clean `actor` it must cross the
actor boundary, so convert `ThumbnailCache` to an `actor`. Verify and, if needed, annotate
`VideoEncryptionServiceProtocol` as `Sendable`. `EncryptionScheme` is already `Sendable`.

Rationale: the existing
[swift-concurrency-review](../../../../notes/bill-dev-notes/Projects/SnapSafe/design/swift-concurrency-review.md)
establishes the team rule that `@MainActor` is for types that drive `@Published` UI state. A
heavy I/O + crypto repository is not such a type, so an off-main `actor` is the consistent choice.

## Data flow (thumbnail example)

`PhotoCell` (view) binds to `@Published thumbnail` on its ViewModel → the VM calls
`await repo.readThumbnail(photo) -> Data?` (actor, off-main) → the VM decodes `UIImage(data:)`
on `@MainActor` → sets `@Published`. The view no longer `@Injected`s the repository.

## Error handling

Method contracts are unchanged — methods `throw` or return optional / `Bool` as today; failures
log via `Logger` and degrade. No new force operations (consistent with the 2026-06-13 force-op
removal work).

## Staging — three PRs, each independently green

| PR | Change | Risk | Tests |
|----|--------|------|-------|
| **PR1** | Extract `ImageProcessing`; repo delegates CPU work. No isolation/API change (repo stays `@MainActor`, still returns `UIImage`). | Low | + `ImageProcessingTests` |
| **PR2** | Extract `PhotoStorageDataSource` (paths + encrypted file I/O + enumeration); repo delegates. Still `@MainActor`. | Low–med | + `PhotoStorageDataSourceTests` |
| **PR3** | Actor-ify `ThumbnailCache` + `SecureImageRepository`; drop `@MainActor`; read APIs return `Data`; move `UIImage` decode into gallery/detail ViewModels; route `PhotoCell` + `SecureGalleryView` through their VMs; adapt `VideoPlayerView` minimally. | High | Adjust `SecureImageRepositoryTests` for `Data`; + actor concurrency test |

Each PR keeps the build and the existing test suite green. The high-risk concurrency + boundary
flip is intentionally last, after responsibilities are already isolated.

## Testing

- Existing `SecureImageRepositoryTests` stay green throughout (adjusted for `Data` returns in PR3).
- New focused unit tests for `ImageProcessing` (compress/resize/rotate/EXIF round-trips) and
  `PhotoStorageDataSource` (encrypted write→read, enumeration, delete).
- A task-group concurrency test for the actor'd repo + cache, mirroring the
  `AuthorizationRepository` pattern in the concurrency-review note.

## Out of scope (separate efforts)

- `VideoPlayerView` full logic extraction into its ViewModel (P2).
- Gallery / camera ViewModel `FileManager` work (P3).
- Dead-file deletion — duplicate `PINSetupViewModel`, duplicate `Logger+Extensions` (P4).
- `SettingsView` → `locationRepository` direct access (P2).

## Related

- Audit: [[architecture-audit-vs-android]]
- Today's prior work: [[2026-06-13-codacy-critical-fixes]]
