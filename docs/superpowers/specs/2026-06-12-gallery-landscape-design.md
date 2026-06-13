# Gallery landscape support

## Problem

The gallery (`SecureGalleryView`) is portrait-locked today. The single-item detail view (`EnhancedPhotoDetailView`) supports `.allButUpsideDown`. Cancelling out of the detail view while the device is held in landscape produces a visible "snap": the gallery flashes in landscape and then rotates back to portrait.

The root cause is `DeviceRotationViewModifier` in `SnapSafe/Util/OrientationManager.swift`. Its `onDisappear` block unconditionally forces the interface back to portrait via `requestGeometryUpdate`. When the detail view disappears, this fires before (or interleaved with) the gallery's reappearance, and the gallery has no orientation modifier of its own to counteract the rotation.

## Goals

- Gallery supports `.allButUpsideDown`. Layout reflows naturally on rotation.
- No visible orientation snap when popping detail back to gallery.
- No layout changes — the existing adaptive grid handles landscape on its own.

## Non-goals

- No changes to the camera (stays portrait-locked).
- No changes to settings, PIN screens, or any other non-gallery screen.
- No changes to the detail view (already declares `.allButUpsideDown`).
- No cell-size or column-count tuning — the adaptive grid is left as-is.

## Design

### 1. Declare landscape support on the gallery

Add `.supportedOrientations(.allButUpsideDown)` to `SecureGalleryView.body`, matching what `EnhancedPhotoDetailView` already does. The grid is `LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))])` with fixed 100×100 cells, so it reflows automatically: ~3 columns in portrait, ~6–7 in landscape on iPhone.

### 2. Stop the portrait reset on disappear

Change `DeviceRotationViewModifier` so its contract becomes "set on appear; do nothing on disappear." The modifier currently runs `requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))` on disappear, which is what produces the snap on pop. Removing that block lets the next appearing view's `onAppear` declare its own orientation without fighting an intermediate portrait rotation.

`AppDelegate.orientationLock` keeps its `.portrait` default, so first-launch behavior is unchanged — only inter-screen transitions are affected.

### Transition table after the change

| From → To | Behavior |
|---|---|
| Camera → Gallery (push) | Gallery's `onAppear` sets `.allButUpsideDown`. User can rotate. |
| Gallery → Detail (push, both landscape-capable) | No rotation request fires. No snap. |
| Detail → Gallery (pop) | Detail's `onDisappear` is now a no-op. Gallery's `onAppear` re-asserts `.allButUpsideDown`. No snap. |
| Gallery → Camera (back) | Camera's `onAppear` sets `.portrait`. Rotates back to portrait if device is landscape — expected behavior; camera is portrait-only. |

## Trade-off

Removing the disappear reset means screens without an orientation modifier inherit whatever the prior screen set. The one path that exposes this in practice is **gallery (opened from Settings for decoy selection) → back to Settings while the device is in landscape**: Settings would render in landscape until the device is rotated. Settings is a SwiftUI `Form` and adapts cleanly, so this is acceptable. Tagging Settings with `.supportedOrientations(.portrait)` would prevent it, but it is out of scope per the agreed tight-scope decision.

## Files touched

- `SnapSafe/Util/OrientationManager.swift` — remove the `.onDisappear` block from `DeviceRotationViewModifier`. Update the explanatory comment.
- `SnapSafe/Screens/Gallery/SecureGalleryView.swift` — add `.supportedOrientations(.allButUpsideDown)` to the view body.

## Verification

- Manual: open the app, navigate to gallery, rotate to landscape — grid reflows. Tap an item — detail opens in landscape with no rotation flash. Cancel the detail — return to gallery in landscape with no snap to portrait. Tap "back" to camera — interface rotates to portrait as expected.
- Existing tests still pass; no unit-testable surface change.
