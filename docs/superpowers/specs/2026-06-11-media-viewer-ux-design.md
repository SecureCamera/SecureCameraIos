# Media Viewer Drag/Zoom UX + Capture Framing — Design

**Date:** 2026-06-11
**Branch:** video
**Status:** Approved

## Problem

Four related UX defects in the media detail pager and camera:

1. **Dismiss drag "catches".** While holding a photo and sliding the finger
   around, the image intermittently freezes — most noticeably near the bottom
   toolbar. Cause: `EnhancedPhotoDetailViewModel.handleDragChanged` re-checks
   `abs(translation.height) > abs(translation.width)` on *every* update and
   silently drops updates when the cumulative translation turns more
   horizontal than vertical. The drag also forces `dragOffset.width = 0`, so
   the image never follows the finger sideways.
2. **Video pages drag inconsistently.** The photo action toolbar lives outside
   the transformed pager layer (stationary during drag), but the video
   transport bar and action toolbar are rendered inside `InlineVideoPlayerView`
   — inside the layer that receives the dismiss transform — so they move with
   the video.
3. **No pinch-zoom on videos.** Photos zoom via `ZoomableScrollView`
   (UIScrollView); the video page renders a bare `AVPlayerLayer` surface.
4. **Capture framing ≠ preview framing.** The session uses the `.high` preset:
   the preview feed, captured photos, and videos are all 16:9 (1920×1080). The
   preview is aspect-FILLED into a hard-coded 3:4 container
   (`CameraPreviewView.photoAspectRatio`), cropping the top and bottom on
   screen. Captures keep the full 16:9 frame, so saved media shows strips
   above and below what the preview displayed. `.high` also caps stills at
   ~2MP.

## Decisions (user-confirmed)

- **Controls fade out during the dismiss drag** (Apple Photos behavior), for
  both photos and videos. They fade back if the drag is cancelled.
- **Preview shows the full 16:9 capture frame** (WYSIWYG). No cropping of
  captures; photos and videos share identical framing.

## Design

### 1. Free-floating dismiss drag

In `EnhancedPhotoDetailViewModel`:

- Add a per-gesture **direction latch** (`dragMode`), set once on the first
  `onChanged` of a gesture: initial direction predominantly vertical → dismiss
  mode for the rest of the gesture; horizontal → not a dismiss drag (pager
  pages as today). No per-update re-checking.
- In dismiss mode, `dragOffset` tracks the **full 2D translation** (width no
  longer forced to 0). `dismissProgress` still derives from vertical travel
  only. `DismissTransformModifier` applies both axes.
- `handleDragEnded` resets the latch; the existing dismiss threshold /
  velocity logic is unchanged.
- While a dismiss drag is engaged, the pager's horizontal scroll is disabled
  via the existing `updatePagingEnabled` pathway (extended to consider
  "dismiss drag active" alongside `isZoomed`).

Latch logic lives in the view model and gets unit tests (same style as
`mayDismissByDrag`).

### 2. Chrome fades during the drag

- New shared `@MainActor @Observable` class (`PagerChromeState`, single flag
  `isDismissDragging`), owned by `EnhancedPhotoDetailView`, passed into
  `PhotoPageViewController` and injected into each hosted page's root view via
  `.environment`.
- Photo toolbar + counter chip (already outside the pager layer): opacity tied
  to the drag — fade out when the dismiss drag latches, fade back on cancel.
  Toolbar gets `allowsHitTesting(false)` while hidden.
- `InlineVideoPlayerView` observes `PagerChromeState` and hides its transport
  bar + action toolbar with the same animation while dragging. With controls
  hidden, nothing visible moves with the video — resolving the inconsistency
  without restructuring the video page hierarchy.

### 3. Pinch-zoom for videos

- Wrap `VideoSurfaceView` in the existing `ZoomableScrollView` inside
  `InlineVideoPlayerView`, same configuration as photos (1×–6×). Pinch,
  pan-while-zoomed, double-tap zoom, and centering come free; `AVPlayerLayer`
  keeps rendering while scaled, so zoom works during playback and while
  paused.
- Thread the same `isZoomed` binding photos use through
  `InlineVideoHostingController` so paging disables while zoomed and the
  dismiss gate (`mayDismissByDrag`) works unchanged.
- Tap conflict: the video page toggles controls on single tap, and
  `ZoomableScrollView` owns a UIKit double-tap recognizer. Add an optional
  `onSingleTap` callback to `ZoomableScrollView`, wired with
  `require(toFail: doubleTap)`, and move the controls toggle there — double
  tap zooms without flashing the controls.

### 4. Camera preview = capture frame (WYSIWYG)

In `CameraPreviewView` / `CameraDeviceService`:

- The preview container's aspect ratio is **derived from the active capture
  format's dimensions** (e.g. 1920×1080 under `.high` → 9:16 portrait), with
  9:16 as the fallback — not a new hard-coded constant, so it stays correct if
  the preset changes.
- `videoGravity` stays `.resizeAspectFill`; with the container matching the
  feed ratio, fill ≡ fit and nothing is cropped.
- Border/corner brackets already lay out from the container size — they adapt.
  Tap-to-focus conversion goes through `captureDevicePointConverted`, which
  accounts for gravity — unaffected.
- Raise still resolution: set the photo output's `maxPhotoDimensions` (and the
  per-capture `photoSettings.maxPhotoDimensions`) to the active format's
  largest entry in `supportedMaxPhotoDimensions` (~4032×2268, still 16:9).

## Out of scope

- Cropping captures to a 3:4 window (rejected: lossy, and video would need
  re-encoding through the encrypted pipeline).
- Mode-dependent aspect ratios (rejected: photos and videos must share
  framing).
- UIKit interactive-transition rewrite of the dismiss gesture.

## Error handling

No new failure paths. Gesture changes are pure state-machine logic in the
view model. `maxPhotoDimensions` is set only from values the format reports in
`supportedMaxPhotoDimensions`.

## Testing

- Unit tests for the drag latch state machine (engage vertical, ignore
  horizontal, full-2D offset while latched, reset on end).
- Manual on-device verification:
  - Drag photo and video through all four screen regions, including over the
    toolbar area; verify no catching, chrome fades out and back, cancel and
    complete both work.
  - Pinch video while playing and while paused; pan while zoomed; double-tap
    zooms in/out without toggling controls; paging disabled while zoomed.
  - Capture a photo and a video; compare framing edge-for-edge against the
    preview; verify still resolution is the format max.
