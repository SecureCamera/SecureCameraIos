# Photo Detail Tap-to-Toggle Chrome

**Date:** 2026-06-14  
**Branch:** video

## Problem

The video detail view lets the user single-tap to hide the playback controls and counter chip, revealing only the video. The photo detail view has no equivalent: the toolbar and counter chip are always visible (counter auto-hides after 5 s but the toolbar never does). Users should be able to single-tap a photo to hide all chrome and see just the image, then tap again to restore it.

## Goal

Single tap on a photo hides the toolbar + counter chip. Another single tap shows them again. Double-tap still zooms in. Swiping to a new page restores chrome.

## Non-goals

- Auto-hide the toolbar on a timer (user controls visibility manually)
- Change video chrome behavior (already works correctly)

## Architecture

### State: `EnhancedPhotoDetailViewModel`

Add `@Published var isPhotoChromeVisible: Bool = true`.

New `togglePhotoChrome()`:
- Video pages: delegate to existing `showCounterThenAutoHide()` — no behavior change
- Photo page, chrome visible: cancel `counterHideTask`, animate `isPhotoChromeVisible = false` and `isCounterVisible = false` together (0.25 s easeInOut)
- Photo page, chrome hidden: set `isPhotoChromeVisible = true`, call `showCounterThenAutoHide()` (shows counter and schedules 5 s auto-hide)

Update `showCounterThenAutoHide()`: for photo pages, also set `isPhotoChromeVisible = true` so that swiping to a new page always restores the chrome.

### View: `EnhancedPhotoDetailView`

Remove the outer `.simultaneousGesture(TapGesture())` — single-tap is now handled inside `ZoomableScrollView` which properly gates on double-tap failure.

Pass `onPhotoSingleTap: { viewModel.togglePhotoChrome() }` into `PhotoPageViewController`.

Update the photo toolbar overlay modifiers:
```swift
.opacity((viewModel.isDismissDragging || !viewModel.isPhotoChromeVisible) ? 0 : 1)
.allowsHitTesting(!viewModel.isDismissDragging && viewModel.isPhotoChromeVisible)
.animation(.easeInOut(duration: 0.2), value: viewModel.isDismissDragging)
.animation(.easeInOut(duration: 0.25), value: viewModel.isPhotoChromeVisible)
```

Disabling `allowsHitTesting` when hidden is required: invisible toolbar buttons would otherwise swallow taps that should be showing chrome.

### Plumbing

Thread `onPhotoSingleTap: (() -> Void)` through each layer without changing any other behavior:

| Layer | Change |
|---|---|
| `PhotoPageViewController` | New init param; coordinator stores it; `updateUIViewController` syncs it; `viewController(at:)` passes it to `PhotoDetailHostingController` |
| `PhotoDetailHostingController` | New init param; passes to `PhotoDetailView` |
| `PhotoDetailView` | Store as `let onSingleTap: (() -> Void)?`; pass to `ZoomableScrollView(onSingleTap:)` |
| `ZoomableScrollView` | No change — already installs a UIKit single-tap recognizer that `require(toFail:)` the double-tap recognizer |

### Behavior table

| Action | Result |
|---|---|
| Single tap (chrome visible) | Toolbar + counter chip fade out |
| Single tap (chrome hidden) | Toolbar + counter chip fade in; counter starts 5 s auto-hide |
| Double tap | Zoom in; chrome unaffected |
| Swipe to next/prev page | Chrome resets to visible |
| Zoom in (`isZoomed`) | Toolbar hides via existing `isZoomed` path in `PhotoDetailToolbar` |
| Dismiss drag | Chrome hides via existing `isDismissDragging` path |

## Files Changed

1. `SnapSafe/Screens/PhotoDetail/EnhancedPhotoDetailViewModel.swift`
2. `SnapSafe/Screens/PhotoDetail/EnhancedPhotoDetailView.swift`
3. `SnapSafe/Screens/PhotoDetail/PhotoPageViewController.swift`
4. `SnapSafe/Screens/PhotoDetail/PhotoDetailView.swift`
