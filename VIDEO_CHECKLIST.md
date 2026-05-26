# SECV Video Implementation Checklist - SnapSafe iOS

## Context

SnapSafe iOS has video capture, SECV encryption/decryption services, an encrypted video player, and a mixed media gallery ViewModel already written — but none of it is wired together. The files aren't in the Xcode project, DI registrations are missing, and the camera doesn't trigger encryption after recording. This checklist tracks connecting all the existing pieces and filling the remaining gaps, mirroring the Android reference implementation's flow: **record → encrypt → gallery → playback → share**.

---

## Phase 1: Project Foundation & DI Wiring

- [ ] **1a. Add missing files to Xcode project**
  - `SnapSafe/Data/Encryption/VideoEncryptionService.swift`
  - `SnapSafe/Util/EncryptedVideoDataSource.swift`
  - `SnapSafe/Screens/PhotoDetail/VideoPlayerView.swift`
  - `SnapSafe/Screens/Gallery/MixedMediaGalleryViewModel.swift`
  - `SnapSafe/Data/Models/MediaItem.swift`

- [ ] **1b. Register VideoEncryptionService in DI container**
  - File: `SnapSafe/Data/AppDependencyInjection.swift`
  - Add `var videoEncryptionService: Factory<VideoEncryptionService>` registration

- [ ] **1c. Fix compile errors**
  - Verify `MediaItem` protocol conformance on `PhotoDef` and `VideoDef`
  - Verify `MixedMediaGalleryViewModel` compiles with DI injection
  - Verify `Logger` extensions don't conflict

---

## Phase 2: Post-Recording Encryption Pipeline

- [ ] **2a. Add encryption callback to VideoCaptureService**
  - File: `SnapSafe/Screens/Camera/Services/VideoCaptureService.swift`
  - Add `var onRecordingFinished: ((URL) -> Void)?` callback
  - Call it in `fileOutput(_:didFinishRecordingTo:from:error:)` on success

- [ ] **2b. Wire encryption in CameraViewModel**
  - File: `SnapSafe/Screens/Camera/CameraViewModel.swift`
  - Inject `VideoEncryptionService` and get encryption key from auth
  - After recording: encrypt .mov → .secv, then delete .mov
  - Add `@Published var isEncryptingVideo: Bool`
  - Add `@Published var encryptionProgress: Double`

- [ ] **2c. Add encryption progress UI in CameraView**
  - Show progress indicator when `isEncryptingVideo` is true
  - Prevent or warn on navigation during encryption

---

## Phase 3: Gallery Integration

- [ ] **3a. Switch gallery to MixedMediaGalleryViewModel**
  - File: `SnapSafe/Screens/Gallery/SecureGalleryView.swift`
  - Replace `SecureGalleryViewModel` with `MixedMediaGalleryViewModel`
  - Pass encryption key from auth context

- [ ] **3b. Add video cell rendering in gallery grid**
  - Video icon overlay and duration badge on video cells
  - Tap routing: photos → PhotoDetailView, videos → VideoPlayerView

- [ ] **3c. Add video playback navigation**
  - File: `SnapSafe/Screens/AppNavigation.swift` — add `.videoPlayer(VideoDef, SymmetricKey?)` destination
  - File: `SnapSafe/Screens/ContentView.swift` — route to `VideoPlayerView`

- [ ] **3d. Pass encryption key through navigation**
  - Flow: auth → gallery → video player
  - Ensure key is available for encrypted video playback

---

## Phase 4: Security & Cleanup

- [ ] **4a. Add video cleanup to SecurityResetUseCase**
  - File: `SnapSafe/Data/UseCases/SecurityResetUseCase.swift`
  - Delete all files in `ApplicationSupport/videos/`

- [ ] **4b. Clean up stranded temp files on app launch**
  - Scan for `.mov` files in videos directory on startup
  - Delete them (safer than re-encrypting)

- [ ] **4c. Session invalidation cleanup**
  - File: `SnapSafe/Data/UseCases/InvalidateSessionUseCase.swift`
  - Clear cached decrypted video data on session invalidation

---

## Phase 5: Video Sharing

- [ ] **5a. Verify sharing flow**
  - `MixedMediaGalleryViewModel.prepareAndShareMedia()` already has video decryption
  - Confirm decryption-for-sharing works end-to-end
  - Verify temp decrypted files are cleaned up after sharing

---

## Phase 6: Build & Verify

- [ ] **6a. Build succeeds** — `xcodebuild build` with no errors
- [ ] **6b. Unit tests pass** — `SECVFileFormatTests`
- [ ] **6c. Manual flow test:**
  - Switch to video mode → record → stop
  - Verify .mov encrypted to .secv, then .mov deleted
  - Gallery shows video with icon overlay
  - Tap video → plays via encrypted data source
  - Share video → temp decrypt → share sheet
  - Security reset → all videos deleted

---

## Key Files

| File | Action |
|------|--------|
| `project.pbxproj` | Add 5 missing Swift files to build |
| `AppDependencyInjection.swift` | Register VideoEncryptionService |
| `VideoCaptureService.swift` | Add recording-finished callback |
| `CameraViewModel.swift` | Wire post-recording encryption |
| `CameraView.swift` | Add encryption progress UI |
| `SecureGalleryView.swift` | Switch to mixed media ViewModel |
| `AppNavigation.swift` | Add video player destination |
| `ContentView.swift` | Route video player destination |
| `SecurityResetUseCase.swift` | Add video directory cleanup |
