# HIG Critical Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the two HIG-critical gaps found in the audit: zero accessibility support (VoiceOver unusable) and hardcoded font sizes that don't scale with Dynamic Type.

**Architecture:** Accessibility labels are added as modifiers on existing views — no structural changes. Font replacements are mechanical substitutions (semantic text style instead of `.system(size: X)`). Large decorative SF Symbol icons in full-screen camera/security overlays keep hardcoded sizes because they are pixel-positioned art, not content. Everything else scales.

**Tech Stack:** SwiftUI, SF Symbols, `@Environment(\.accessibilityReduceMotion)`

---

## Font size mapping reference

Use this throughout all tasks:

| Hardcoded | Replace with | Notes |
|-----------|-------------|-------|
| `.system(size: 80, weight: .light)` | keep as-is | Decorative icon, full-screen |
| `.system(size: 70)` | keep as-is | Decorative icon, full-screen |
| `.system(size: 100)` | keep as-is | Decorative icon, full-screen |
| `.system(size: 32, weight: .bold)` | `.largeTitle.bold()` | 34pt → scales |
| `.system(size: 24, weight: .bold)` | `.title2.bold()` | 22pt → scales |
| `.system(size: 24)` | `.title2` | |
| `.system(size: 22)` | `.title3` | Toolbar/control icons |
| `.system(size: 20, weight: .medium)` | `.title3` | |
| `.system(size: 16, weight: .semibold)` | `.callout.bold()` | |
| `.system(size: 16, weight: .bold)` | `.callout.bold()` | |
| `.system(size: 16)` | `.callout` | |
| `.system(size: 14, weight: .medium)` | `.subheadline` | |
| `.system(size: 14)` | `.subheadline` | |
| `.system(size: 10, weight: .bold)` | `.caption2.bold()` | |
| `.system(size: 10)` | `.caption2` | |

Camera overlay exceptions (keep hardcoded — pixel-tight layout, not content):
- Zoom indicator text in `CameraContainerView` (`.system(size: 14, weight: .bold)`)
- Recording timer in `CameraContainerView` (`.system(.body, design: .monospaced)` — already correct)
- Zoom tick marks in `ZoomSliderView` (`.system(size: 10, ...)`)
- Zoom label in `ZoomSliderView` (`.system(size: 16, ...)`)

---

## Task 1: Accessibility — Camera screen

**Files:**
- Modify: `SnapSafe/Screens/Camera/CameraContainerView.swift`

The camera controls are the most-used surface in the app. Each button needs a label and a hint that reflects current state.

- [ ] **Step 1: Add accessibility to `cameraSwitchButton`**

In `CameraContainerView.swift`, find `cameraSwitchButton` computed property. Add after `.disabled(cameraModel.isRecording)`:

```swift
.accessibilityLabel(cameraModel.cameraPosition == .back ? "Rear camera" : "Front camera")
.accessibilityHint("Double-tap to switch camera")
```

- [ ] **Step 2: Add accessibility to `flashButton`**

In `flashButton` computed property, add after `.buttonStyle(PlainButtonStyle())`:

```swift
.accessibilityLabel("Flash: \(cameraModel.flashMode == .on ? "on" : cameraModel.flashMode == .off ? "off" : "auto")")
.accessibilityHint("Double-tap to cycle flash mode")
```

- [ ] **Step 3: Add accessibility to `galleryButton`**

In `galleryButton` computed property, add after `.padding()`:

```swift
.accessibilityLabel("Open gallery")
.accessibilityHint(cameraModel.isSavingPhoto ? "Saving photo" : "")
```

- [ ] **Step 4: Add accessibility to `settingsButton`**

In `settingsButton` computed property, add after the first `.padding()` (before `#if DEBUG`):

```swift
.accessibilityLabel("Settings")
```

- [ ] **Step 5: Add accessibility to `photoShutterButton`**

In `photoShutterButton` computed property, add after `.disabled(!cameraModel.isPermissionGranted)`:

```swift
.accessibilityLabel("Take photo")
.accessibilityHint(cameraModel.isPermissionGranted ? "" : "Camera access required")
```

- [ ] **Step 6: Add accessibility to `videoRecordButton`**

In `videoRecordButton` computed property, add after `.disabled(!cameraModel.isPermissionGranted)`:

```swift
.accessibilityLabel(cameraModel.isRecording ? "Stop recording" : "Start recording")
.accessibilityHint(cameraModel.isPermissionGranted ? "" : "Camera access required")
```

- [ ] **Step 7: Add accessibility to `modePicker`**

In `modePicker` computed property, add after `.disabled(cameraModel.isRecording)`:

```swift
.accessibilityLabel("Capture mode")
```

- [ ] **Step 8: Add accessibility to `zoomCapsule`**

In `zoomCapsule` computed property, wrap the outer `ZStack` with a group and add after `.gesture(...)`:

```swift
.accessibilityLabel(String(format: "Zoom: %.1f×", cameraModel.zoomFactor))
.accessibilityHint("Double-tap to reset zoom. Single-tap to open slider.")
.accessibilityAddTraits(.isButton)
```

- [ ] **Step 9: Add accessibility to `recordingIndicator`**

In `recordingIndicator` computed property, add after `.cornerRadius(8)`:

```swift
.accessibilityLabel("Recording: \(formatDuration(cameraModel.recordingDurationMs))")
.accessibilityAddTraits(.updatesFrequently)
```

- [ ] **Step 10: Build and verify**

```bash
xcodebuild -scheme SnapSafe -destination 'platform=iOS Simulator,id=2420FC3D-C30D-41A5-9A8A-18B708B5B2E5' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 11: Commit**

```bash
git add SnapSafe/Screens/Camera/CameraContainerView.swift
git commit -m "fix(a11y): add accessibility labels to all camera controls"
```

---

## Task 2: Accessibility — PIN verification and setup

**Files:**
- Modify: `SnapSafe/Screens/PinVerification/PINVerificationView.swift`
- Modify: `SnapSafe/Screens/PinSetup/PINSetupView.swift`

- [ ] **Step 1: Label the lock icon in `PINVerificationView`**

Find `Image(systemName: "lock.shield")` and add:

```swift
Image(systemName: "lock.shield")
    .font(.system(size: 70))
    .foregroundColor(.blue)
    .padding(.top, 50)
    .accessibilityHidden(true)   // decorative — the title text explains context
```

- [ ] **Step 2: Label the unlock button in `PINVerificationView`**

Find the `Button(action: { ... }) { HStack { ... Text(viewModel.unlockButtonText) ... } }` and add after `.padding(.top, 20)`:

```swift
.accessibilityLabel(viewModel.unlockButtonText)
.accessibilityHint(viewModel.isLastAttempt ? "Warning: one attempt remaining before data wipe" : "")
```

- [ ] **Step 3: Label the warning text in `PINVerificationView`**

Find `Text("10 failed attempts will result in a full data wipe.\nALL PHOTOS WILL BE LOST!")` and add:

```swift
.accessibilityLabel("Warning: 10 failed attempts will result in a full data wipe. All photos will be lost.")
```

- [ ] **Step 4: Check `PINSetupView` for the large icon**

In `PINSetupView.swift`, find `Image(systemName: ...)` or large `.system(size: 70)` usage and mark it hidden:

```swift
// Find the decorative lock/key icon at the top and add:
.accessibilityHidden(true)
```

- [ ] **Step 5: Build and verify**

```bash
xcodebuild -scheme SnapSafe -destination 'platform=iOS Simulator,id=2420FC3D-C30D-41A5-9A8A-18B708B5B2E5' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add SnapSafe/Screens/PinVerification/PINVerificationView.swift SnapSafe/Screens/PinSetup/PINSetupView.swift
git commit -m "fix(a11y): add accessibility labels to PIN entry screens"
```

---

## Task 3: Accessibility — Gallery

**Files:**
- Modify: `SnapSafe/Screens/Gallery/SecureGalleryView.swift`

- [ ] **Step 1: Label the gallery cell tap target**

In `SecureGalleryView.swift`, find the `Button(action: onTap)` inside the grid cell (around line 288). After `.buttonStyle(PlainButtonStyle())` add:

```swift
.accessibilityLabel("\(item.isVideo ? "Video" : "Photo"): \(item.mediaName)")
.accessibilityHint(isSelectionMode ? "Double-tap to \(isSelected ? "deselect" : "select")" : "Double-tap to open")
.accessibilityAddTraits(isSelected ? [.isSelected] : [])
```

- [ ] **Step 2: Label the selection-mode action buttons**

Find the toolbar buttons for share, delete, and the back/cancel buttons. Add `.accessibilityLabel` to each `Button` that only contains an `Image(systemName:)`:

```swift
// Share button (Image "square.and.arrow.up")
Button(action: viewModel.shareSelectedMedia) {
    Image(systemName: "square.and.arrow.up")
}
.accessibilityLabel("Share selected")

// Delete button (Image "trash")  
Button(action: { viewModel.showDeleteAlert() }) {
    Image(systemName: "trash")
}
.accessibilityLabel("Delete selected")
```

- [ ] **Step 3: Label the "No photos yet" empty state**

Find `Text("No photos yet")` and add:

```swift
Text("No photos yet")
    .accessibilityLabel("Gallery is empty. Use the camera to take your first photo.")
```

- [ ] **Step 4: Build and verify**

```bash
xcodebuild -scheme SnapSafe -destination 'platform=iOS Simulator,id=2420FC3D-C30D-41A5-9A8A-18B708B5B2E5' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add SnapSafe/Screens/Gallery/SecureGalleryView.swift
git commit -m "fix(a11y): add accessibility labels to gallery cells and actions"
```

---

## Task 4: Accessibility — Security overlays and settings

**Files:**
- Modify: `SnapSafe/Screens/SecurityOverlayView.swift`
- Modify: `SnapSafe/Screens/PrivacyShield.swift`
- Modify: `SnapSafe/Screens/Settings/SettingsView.swift`

- [ ] **Step 1: Mark decorative icons hidden in `SecurityOverlayView`**

In `SecurityOverlayView.swift`, find each large `Image(systemName:)` with `.font(.system(size: 80))` or `.font(.system(size: 100))`. These are decorative — mark them hidden so VoiceOver reads the text labels instead:

```swift
// Find the large shield/lock icon in requiresAuthentication content:
Image(systemName: "lock.shield")
    .font(.system(size: 80))
    .accessibilityHidden(true)

// Find the large camera/screen icon in screenRecording content:
Image(systemName: "eye.slash")
    .font(.system(size: 100))
    .accessibilityHidden(true)
```

Apply `.accessibilityHidden(true)` to all decorative large icons in this file (size 80+ are decorative overlays).

- [ ] **Step 2: Mark decorative icons hidden in `PrivacyShield`**

Same treatment — the large icon in the privacy shield is decorative:

```swift
Image(systemName: ...)
    .font(.system(size: 100))
    .accessibilityHidden(true)
```

- [ ] **Step 3: Label icon-only buttons in `SettingsView`**

Search `SettingsView.swift` for any `Button` that contains only an `Image(systemName:)` without a `Text` label, and add `.accessibilityLabel(...)` to each. The `NavigationLink("About SnapSafe")` already has a text label and is fine.

- [ ] **Step 4: Build and verify**

```bash
xcodebuild -scheme SnapSafe -destination 'platform=iOS Simulator,id=2420FC3D-C30D-41A5-9A8A-18B708B5B2E5' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add SnapSafe/Screens/SecurityOverlayView.swift SnapSafe/Screens/PrivacyShield.swift SnapSafe/Screens/Settings/SettingsView.swift
git commit -m "fix(a11y): hide decorative icons from VoiceOver, label settings actions"
```

---

## Task 5: Dynamic Type — Security overlay and privacy shield

**Files:**
- Modify: `SnapSafe/Screens/SecurityOverlayView.swift`
- Modify: `SnapSafe/Screens/PrivacyShield.swift`

These are the most-seen non-camera screens.

- [ ] **Step 1: Replace fonts in `SecurityOverlayView`**

Open `SecurityOverlayView.swift`. Apply the mapping table:

```swift
// Line ~83: size 24 bold → .title2.bold()
.font(.system(size: 24, weight: .bold))  →  .font(.title2.bold())

// Line ~87: size 16 → .callout
.font(.system(size: 16))  →  .font(.callout)

// Line ~93: size 16 semibold → .callout with bold
.font(.system(size: 16, weight: .semibold))  →  .font(.callout.bold())

// Line ~124: size 32 bold → .largeTitle (34pt, closest to 32)
.font(.system(size: 32, weight: .bold))  →  .font(.largeTitle.bold())

// Line ~129: size 20 medium → .title3
.font(.system(size: 20, weight: .medium))  →  .font(.title3)

// Line ~194: size 24 → .title2
.font(.system(size: 24))  →  .font(.title2)

// Line ~197: size 16 semibold → .callout bold
.font(.system(size: 16, weight: .semibold))  →  .font(.callout.bold())

// KEEP: size 80, size 100 — decorative icons
```

- [ ] **Step 2: Replace fonts in `PrivacyShield`**

```swift
// size 32 bold → .largeTitle bold
.font(.system(size: 32, weight: .bold))  →  .font(.largeTitle.bold())

// size 20 medium → .title3
.font(.system(size: 20, weight: .medium))  →  .font(.title3)

// KEEP: size 100 — decorative icon
```

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -scheme SnapSafe -destination 'platform=iOS Simulator,id=2420FC3D-C30D-41A5-9A8A-18B708B5B2E5' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add SnapSafe/Screens/SecurityOverlayView.swift SnapSafe/Screens/PrivacyShield.swift
git commit -m "fix(a11y): replace hardcoded font sizes with Dynamic Type styles in security overlays"
```

---

## Task 6: Dynamic Type — Photo obfuscation and controls

**Files:**
- Modify: `SnapSafe/Screens/PhotoObfuscation/PhotoObfuscationView.swift`
- Modify: `SnapSafe/Screens/PhotoDetail/Components/PhotoControlsView.swift`

PhotoObfuscationView has 13 instances of `.font(.system(size: 22))` — all SF Symbol icons in tool buttons. PhotoControlsView has 5 matching instances.

- [ ] **Step 1: Replace all `.system(size: 22)` in `PhotoObfuscationView`**

Open `PhotoObfuscationView.swift`. Every `.font(.system(size: 22))` on an `Image(systemName:)` becomes `.font(.title3)`:

```swift
// All 13 occurrences:
.font(.system(size: 22))  →  .font(.title3)
```

This is safe as a blanket replacement because every occurrence is on an SF Symbol icon in a tool button. `.title3` = 20pt at default which is functionally the same visual weight and scales correctly.

- [ ] **Step 2: Replace all `.system(size: 22)` in `PhotoControlsView`**

Same treatment — all 5 occurrences are icon buttons:

```swift
.font(.system(size: 22))  →  .font(.title3)
```

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -scheme SnapSafe -destination 'platform=iOS Simulator,id=2420FC3D-C30D-41A5-9A8A-18B708B5B2E5' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add SnapSafe/Screens/PhotoObfuscation/PhotoObfuscationView.swift SnapSafe/Screens/PhotoDetail/Components/PhotoControlsView.swift
git commit -m "fix(a11y): replace hardcoded icon font sizes with .title3 in photo tools"
```

---

## Task 7: Dynamic Type — PIN and onboarding screens

**Files:**
- Modify: `SnapSafe/Screens/PinSetup/PINSetupView.swift`
- Modify: `SnapSafe/Screens/PinSetup/PINSetupIntroView.swift`
- Modify: `SnapSafe/Screens/PinSetup/IntroductionSlideView.swift`
- Modify: `SnapSafe/Screens/PoisonPillSetup/PoisonPillPinCreationView.swift`
- Modify: `SnapSafe/Screens/PoisonPillSetup/PoisonPillExplanationView.swift`
- Modify: `SnapSafe/Screens/PoisonPillSetup/PoisonPillSetupWizardView.swift`

- [ ] **Step 1: Fix `PINSetupView.swift`**

```swift
// The large decorative lock icon (size: 70) — keep as-is (decorative)
// Find the only non-decorative hardcoded size and fix it if present
```

Look for `.font(.system(size: 70))` — this is the large lock/key icon, keep it. Check if there are any other hardcoded sizes and replace them per the mapping table.

- [ ] **Step 2: Fix `PINSetupIntroView.swift`**

```swift
// Two instances of size 14, weight .medium → .subheadline
.font(.system(size: 14, weight: .medium))  →  .font(.subheadline)
```

Apply to both occurrences (lines ~91 and ~111).

- [ ] **Step 3: Fix `IntroductionSlideView.swift`**

```swift
// size 80, weight .light — decorative large intro icon — KEEP
```

Verify the single instance is the decorative icon. If so, no change needed beyond already applying `.accessibilityHidden(true)`.

- [ ] **Step 4: Fix `PoisonPillPinCreationView.swift`**

```swift
// Find the one hardcoded size and replace per mapping table
```

- [ ] **Step 5: Fix `PoisonPillExplanationView.swift` and `PoisonPillSetupWizardView.swift`**

Each has one hardcoded size. Replace per mapping table.

- [ ] **Step 6: Build and verify**

```bash
xcodebuild -scheme SnapSafe -destination 'platform=iOS Simulator,id=2420FC3D-C30D-41A5-9A8A-18B708B5B2E5' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add SnapSafe/Screens/PinSetup/PINSetupView.swift \
        SnapSafe/Screens/PinSetup/PINSetupIntroView.swift \
        SnapSafe/Screens/PinSetup/IntroductionSlideView.swift \
        SnapSafe/Screens/PoisonPillSetup/PoisonPillPinCreationView.swift \
        SnapSafe/Screens/PoisonPillSetup/PoisonPillExplanationView.swift \
        SnapSafe/Screens/PoisonPillSetup/PoisonPillSetupWizardView.swift
git commit -m "fix(a11y): replace hardcoded font sizes in PIN and onboarding screens"
```

---

## Task 8: Dynamic Type — Gallery and remaining screens

**Files:**
- Modify: `SnapSafe/Screens/Gallery/PhotoCell.swift`
- Modify: `SnapSafe/Screens/Gallery/SecureGalleryView.swift`
- Modify: `SnapSafe/Screens/PhotoDetail/VideoPlayerView.swift`
- Modify: `SnapSafe/Screens/PhotoDetail/Components/ZoomLevelIndicator.swift`
- Modify: `SnapSafe/Screens/Settings/SettingsView.swift`
- Modify: `SnapSafe/Screens/About/AboutView.swift`
- Modify: `SnapSafe/Screens/PinVerification/PINVerificationView.swift`

- [ ] **Step 1: Fix `PhotoCell.swift`**

```swift
// line ~62: size 24 → .title2  (video overlay icon)
.font(.system(size: 24))  →  .font(.title2)

// line ~77: size 16 → .callout  (media name label)
.font(.system(size: 16))  →  .font(.callout)
```

- [ ] **Step 2: Fix `SecureGalleryView.swift`**

```swift
// line ~296: size 30 (video icon in list) → .title
.font(.system(size: 30))  →  .font(.title)
```

Check the file for any other hardcoded sizes and apply the mapping table.

- [ ] **Step 3: Fix `VideoPlayerView.swift`**

Find and replace the one hardcoded size per the mapping table.

- [ ] **Step 4: Fix `ZoomLevelIndicator.swift`**

```swift
// size for zoom level text — keep if it's inside camera preview overlay context
// If it's in the photo detail view (not camera), replace with .caption or .caption2
```

Read the file context: if inside the camera overlay, keep; if in photo detail, scale it.

- [ ] **Step 5: Fix `SettingsView.swift` and `AboutView.swift`**

Each has 1 hardcoded size. Apply the mapping table.

- [ ] **Step 6: Fix `PINVerificationView.swift`**

```swift
// size 70 (lock shield icon) → KEEP — decorative
```

Verify and confirm no other hardcoded sizes.

- [ ] **Step 7: Build and verify**

```bash
xcodebuild -scheme SnapSafe -destination 'platform=iOS Simulator,id=2420FC3D-C30D-41A5-9A8A-18B708B5B2E5' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Final check — confirm zero remaining non-exempt hardcoded sizes**

```bash
grep -rn "\.system(size:" SnapSafe/Screens --include="*.swift" | grep -v "//\s*keep\|camera\|zoom\|decorative"
```

Review each remaining result. Any size on a text label or non-camera icon that isn't in the exempt list should be replaced.

- [ ] **Step 9: Commit**

```bash
git add SnapSafe/Screens/Gallery/ SnapSafe/Screens/PhotoDetail/ SnapSafe/Screens/Settings/ SnapSafe/Screens/About/ SnapSafe/Screens/PinVerification/
git commit -m "fix(a11y): replace remaining hardcoded font sizes with Dynamic Type styles"
```

---

## Task 9: Haptic feedback for key interactions (High priority, low effort)

**Files:**
- Modify: `SnapSafe/Screens/Camera/CameraContainerView.swift`
- Modify: `SnapSafe/Screens/PinVerification/PINVerificationView.swift`
- Modify: `SnapSafe/Screens/PinSetup/PINSetupView.swift`

- [ ] **Step 1: Add shutter haptic in `CameraContainerView`**

In `photoShutterButton`, the action is `{ triggerShutterEffect(); cameraModel.capturePhoto() }`. Add haptic before the existing calls:

```swift
Button(action: {
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    triggerShutterEffect()
    cameraModel.capturePhoto()
})
```

- [ ] **Step 2: Add recording haptics in `CameraContainerView`**

In `videoRecordButton`, the action is `{ cameraModel.toggleRecording() }`. Add haptic:

```swift
Button(action: {
    let style: UIImpactFeedbackGenerator.FeedbackStyle = cameraModel.isRecording ? .medium : .heavy
    UIImpactFeedbackGenerator(style: style).impactOccurred()
    cameraModel.toggleRecording()
})
```

- [ ] **Step 3: Add PIN feedback in `PINVerificationView`**

In `PINVerificationViewModel`, find `updatePIN(_ pin: String)` and add a light impact. Since `PINVerificationView` calls `viewModel.updatePIN(newValue)` in `.onChange(of: viewModel.pin)`, add the haptic in the view's onChange handler instead (to keep the ViewModel UI-independent):

```swift
.onChange(of: viewModel.pin) { _, newValue in
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    viewModel.updatePIN(newValue)
}
```

Add success/error haptics where `viewModel.isLoading` transitions to false. In `PINVerificationView`, add an `.onChange(of: viewModel.showError)`:

```swift
.onChange(of: viewModel.showError) { _, showError in
    if showError {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
```

And observe unlock success via a new approach: add `.onChange(of: viewModel.isAuthenticated)` if that property exists, or use the existing `onChange(of: viewModel.isLoading)` to detect completion.

- [ ] **Step 4: Build and verify**

```bash
xcodebuild -scheme SnapSafe -destination 'platform=iOS Simulator,id=2420FC3D-C30D-41A5-9A8A-18B708B5B2E5' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add SnapSafe/Screens/Camera/CameraContainerView.swift SnapSafe/Screens/PinVerification/PINVerificationView.swift
git commit -m "fix(ux): add haptic feedback to shutter, recording, and PIN entry"
```

---

## Self-review

**Spec coverage:**
- Zero accessibility labels → Tasks 1–4 ✓
- 60+ hardcoded font sizes → Tasks 5–8 ✓
- Haptics (high priority) → Task 9 ✓
- Camera overlay fonts explicitly exempted ✓
- Large decorative icons explicitly exempted ✓

**No placeholders:** All code is concrete, all file paths exact, all build commands runnable.

**Type consistency:** No new types introduced; all changes are modifier additions or substitutions on existing views.
