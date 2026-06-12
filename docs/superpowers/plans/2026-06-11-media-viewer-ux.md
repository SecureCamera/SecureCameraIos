# Media Viewer Drag/Zoom UX + Capture Framing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the dismiss-drag "catching", fade all chrome during the drag (photos and videos), add pinch-zoom to videos, and make the camera preview show exactly the 16:9 frame that gets captured.

**Architecture:** The dismiss drag becomes a direction-latched state machine in `EnhancedPhotoDetailViewModel` (latched once per gesture, full 2D tracking). A new `@Observable PagerChromeState` is injected into hosted pages so the video page can fade its controls during the drag. Video zoom reuses the existing `ZoomableScrollView` (extended with a single-tap callback). The camera preview container derives its aspect ratio from the active capture format instead of a hard-coded 3:4, and still resolution is raised to the format max.

**Tech Stack:** SwiftUI + UIKit interop (`UIViewRepresentable`/`UIHostingController`), AVFoundation, XCTest.

**Spec:** `docs/superpowers/specs/2026-06-11-media-viewer-ux-design.md`

**Build/test commands** (run from repo root `/Users/bill/src/snapsafe/SnapSafe`):

- Full unit tests: `bundle exec fastlane test`
- One test class (faster, used in steps below):
  `xcodebuild test -workspace SnapSafe.xcworkspace -scheme SnapSafe -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SnapSafeTests/<ClassName> -quiet`
- Compile check only:
  `xcodebuild build -workspace SnapSafe.xcworkspace -scheme SnapSafe -destination 'platform=iOS Simulator,name=iPhone 17' -quiet`

New `.swift` files are picked up automatically (file-system-synchronized groups, `objectVersion = 70`). `scripts/check_test_target_membership.rb` (run by the fastlane `test` lane) guards test-target membership.

**Codebase conventions (from AGENTS.md):** new shared state uses `@MainActor @Observable` (not `ObservableObject`); no `DispatchQueue.main.async` in new code; existing `ObservableObject` view models stay as they are.

---

### Task 1: Direction-latched dismiss drag (view model state machine)

The bug: `handleDragChanged` re-checks `abs(height) > abs(width)` on every update and drops updates when the cumulative translation turns horizontal — the image freezes ("catches"). It also forces `dragOffset.width = 0`. Fix: latch the gesture's intent once, on its first `onChanged`, then track the finger on both axes for the rest of the gesture. Handlers take plain values (not `DragGesture.Value`, which can't be constructed in tests).

**Files:**
- Modify: `SnapSafe/Screens/PhotoDetail/EnhancedPhotoDetailViewModel.swift` (drag section, lines ~173–205)
- Modify: `SnapSafe/Screens/PhotoDetail/EnhancedPhotoDetailView.swift` (gesture call sites + `DismissTransformModifier`)
- Create: `SnapSafeTests/EnhancedPhotoDetailViewModelDragTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `SnapSafeTests/EnhancedPhotoDetailViewModelDragTests.swift`:

```swift
//
//  EnhancedPhotoDetailViewModelDragTests.swift
//  SnapSafeTests
//
//  The dismiss drag is a per-gesture state machine: direction is latched on
//  the FIRST movement (vertical → dismissing, horizontal → rejected) and never
//  re-evaluated mid-gesture, and while dismissing the offset follows the
//  finger on BOTH axes. The old per-update direction check made the image
//  freeze ("catch") whenever cumulative translation turned horizontal.
//

import XCTest

@testable import SnapSafe

@MainActor
final class EnhancedPhotoDetailViewModelDragTests: XCTestCase {

    private func makeViewModel() -> EnhancedPhotoDetailViewModel {
        EnhancedPhotoDetailViewModel(allMedia: [], initialIndex: 0)
    }

    // MARK: - Latching

    func test_verticalFirstMovement_latchesDismissing_andTracksFinger() {
        let vm = makeViewModel()

        vm.handleDragChanged(translation: CGSize(width: 5, height: 30), geometryHeight: 800)

        XCTAssertEqual(vm.dragMode, .dismissing)
        XCTAssertTrue(vm.isDismissDragging)
        XCTAssertEqual(vm.dragOffset, CGSize(width: 5, height: 30))
    }

    func test_horizontalFirstMovement_latchesRejected_andNeverMoves() {
        let vm = makeViewModel()

        vm.handleDragChanged(translation: CGSize(width: 40, height: 5), geometryHeight: 800)

        XCTAssertEqual(vm.dragMode, .rejected)
        XCTAssertEqual(vm.dragOffset, .zero)

        // A later vertical-dominant update must NOT re-engage mid-gesture.
        vm.handleDragChanged(translation: CGSize(width: 40, height: 200), geometryHeight: 800)

        XCTAssertEqual(vm.dragMode, .rejected)
        XCTAssertEqual(vm.dragOffset, .zero)
        XCTAssertEqual(vm.dismissProgress, 0)
    }

    func test_dismissingKeepsTrackingBothAxes_whenHorizontalDominates() {
        let vm = makeViewModel()

        vm.handleDragChanged(translation: CGSize(width: 0, height: 30), geometryHeight: 800)
        // The old implementation froze here (|width| > |height|).
        vm.handleDragChanged(translation: CGSize(width: 120, height: 40), geometryHeight: 800)

        XCTAssertEqual(vm.dragMode, .dismissing)
        XCTAssertEqual(vm.dragOffset, CGSize(width: 120, height: 40))
    }

    // MARK: - Progress

    func test_dismissProgress_scalesWithDownwardTravel_andClamps() {
        let vm = makeViewModel()

        vm.handleDragChanged(translation: CGSize(width: 0, height: 160), geometryHeight: 800)
        // 160 / (800 * 0.4) = 0.5
        XCTAssertEqual(vm.dismissProgress, 0.5, accuracy: 1e-9)

        vm.handleDragChanged(translation: CGSize(width: 0, height: 1000), geometryHeight: 800)
        XCTAssertEqual(vm.dismissProgress, 1.0)
    }

    func test_upwardDrag_clampsProgressToZero() {
        let vm = makeViewModel()

        vm.handleDragChanged(translation: CGSize(width: 0, height: -50), geometryHeight: 800)

        XCTAssertEqual(vm.dragMode, .dismissing)
        XCTAssertEqual(vm.dismissProgress, 0)
        // The image still follows the finger upward.
        XCTAssertEqual(vm.dragOffset, CGSize(width: 0, height: -50))
    }

    // MARK: - Gesture end

    func test_dragEnd_belowThreshold_springsBack_andResetsLatch() {
        let vm = makeViewModel()
        vm.handleDragChanged(translation: CGSize(width: 10, height: 100), geometryHeight: 800)

        vm.handleDragEnded(
            translation: CGSize(width: 10, height: 100),
            verticalVelocity: 0,
            geometryHeight: 800
        ) { XCTFail("must not dismiss below threshold") }

        XCTAssertEqual(vm.dragMode, .undecided)
        XCTAssertFalse(vm.isDismissDragging)
        XCTAssertEqual(vm.dragOffset, .zero)
        XCTAssertEqual(vm.dismissProgress, 0)
    }

    func test_dragEnd_pastThreshold_callsDismiss() async {
        let vm = makeViewModel()
        let dismissed = expectation(description: "dismiss called")
        vm.handleDragChanged(translation: CGSize(width: 0, height: 300), geometryHeight: 800)

        // 300 > 800 * 0.25
        vm.handleDragEnded(
            translation: CGSize(width: 0, height: 300),
            verticalVelocity: 0,
            geometryHeight: 800
        ) { dismissed.fulfill() }

        // The dismiss fires from a Task after a 100ms sleep; the async
        // fulfillment API services main-actor jobs while waiting.
        await fulfillment(of: [dismissed], timeout: 2.0)
        XCTAssertEqual(vm.dragMode, .undecided)
    }

    func test_dragEnd_afterRejectedGesture_resetsLatchForNextGesture() {
        let vm = makeViewModel()
        vm.handleDragChanged(translation: CGSize(width: 40, height: 5), geometryHeight: 800)
        XCTAssertEqual(vm.dragMode, .rejected)

        vm.handleDragEnded(
            translation: CGSize(width: 40, height: 5),
            verticalVelocity: 0,
            geometryHeight: 800
        ) { XCTFail("rejected gesture must not dismiss") }
        XCTAssertEqual(vm.dragMode, .undecided)

        // Next gesture can latch fresh.
        vm.handleDragChanged(translation: CGSize(width: 0, height: 30), geometryHeight: 800)
        XCTAssertEqual(vm.dragMode, .dismissing)
    }

    // MARK: - Chrome

    func test_overlayOpacity_isZero_whileDismissDragging() {
        let vm = makeViewModel()
        vm.handleDragChanged(translation: CGSize(width: 0, height: 10), geometryHeight: 800)

        XCTAssertEqual(vm.overlayOpacity, 0)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodebuild test -workspace SnapSafe.xcworkspace -scheme SnapSafe -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SnapSafeTests/EnhancedPhotoDetailViewModelDragTests -quiet
```
Expected: **compile failure** — `dragMode`, `isDismissDragging`, and the new `handleDragChanged(translation:geometryHeight:)` signature don't exist yet.

- [ ] **Step 3: Implement the latch in the view model**

In `SnapSafe/Screens/PhotoDetail/EnhancedPhotoDetailViewModel.swift`:

3a. Below `@Published internal var isZoomed: Bool = false` (line ~71), add:

```swift
    /// Per-gesture intent for the dismiss drag. Latched on the FIRST movement
    /// of each gesture and never re-evaluated mid-gesture: a per-update
    /// direction check made the image freeze ("catch") whenever the finger's
    /// cumulative translation turned more horizontal than vertical.
    enum DismissDragMode {
        /// No gesture in flight (or gesture ended).
        case undecided
        /// First movement was vertical → this gesture dismisses; the offset
        /// follows the finger on both axes until it ends.
        case dismissing
        /// First movement was horizontal → this gesture belongs to the pager;
        /// ignore it entirely until it ends.
        case rejected
    }

    @Published private(set) var dragMode: DismissDragMode = .undecided

    /// True while a dismiss drag is engaged; drives chrome fade-out and
    /// disables the pager's horizontal scroll.
    var isDismissDragging: Bool { dragMode == .dismissing }
```

3b. Replace the entire `// MARK: - Gesture Handling` section (`handleDragChanged` and `handleDragEnded`, lines ~173–205) with:

```swift
    // MARK: - Gesture Handling

    func handleDragChanged(translation: CGSize, geometryHeight: CGFloat) {
        if dragMode == .undecided {
            dragMode = abs(translation.height) > abs(translation.width)
                ? .dismissing
                : .rejected
        }
        guard dragMode == .dismissing else { return }

        dragOffset = translation
        dismissProgress = min(max(translation.height / (geometryHeight * 0.4), 0), 1)
    }

    func handleDragEnded(
        translation: CGSize,
        verticalVelocity: CGFloat,
        geometryHeight: CGFloat,
        dismiss: @escaping () -> Void
    ) {
        let wasDismissing = dragMode == .dismissing
        dragMode = .undecided
        guard wasDismissing else { return }

        let dismissThreshold = geometryHeight * 0.25
        let isQuickDownSwipe = verticalVelocity > 2000

        if translation.height > dismissThreshold || isQuickDownSwipe {
            withAnimation(.easeOut(duration: 0.3)) {
                dragOffset = CGSize(width: 0, height: geometryHeight)
                dismissProgress = 1
            }
            Task {
                try await Task.sleep(for: .milliseconds(100))
                await MainActor.run {
                    self.onDismiss?()
                    dismiss()
                }
            }
        } else {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                dragOffset = .zero
                dismissProgress = 0
            }
        }
    }
```

3c. In `overlayOpacity` (line ~92), add the dismiss-drag case after the `isZoomed` check:

```swift
    var overlayOpacity: Double {
        if isZoomed { return 0.0 }
        if isDismissDragging { return 0.0 }
        if !isCounterVisible { return 0.0 }
        if currentIsVideo && !isVideoControlsVisible { return 0.0 }
        return 1.0 - dismissProgress
    }
```

3d. In `handleIndexChange` (line ~130), reset the latch alongside the offset (defensive — a page change mid-gesture must not leave a stale latch):

```swift
        withAnimation(.easeOut(duration: 0.2)) {
            dragOffset = .zero
            dismissProgress = 0
        }
        dragMode = .undecided
```

- [ ] **Step 4: Update the view call sites and the transform modifier**

In `SnapSafe/Screens/PhotoDetail/EnhancedPhotoDetailView.swift`:

4a. Replace `DismissTransformModifier` and the `dismissTransform` extension (lines 24–50) so the offset applies both axes:

```swift
internal struct DismissTransformModifier: ViewModifier {
    internal let isZoomed: Bool
    internal let scale: CGFloat
    internal let offset: CGSize

    internal func body(content: Content) -> some View {
        content
            .scaleEffect(isZoomed ? 1.0 : scale)
            .offset(
                x: isZoomed ? 0 : offset.width,
                y: isZoomed ? 0 : offset.height
            )
    }
}

internal extension View {
    func dismissTransform(
        isZoomed: Bool,
        scale: CGFloat,
        offset: CGSize
    ) -> some View {
        modifier(
            DismissTransformModifier(
                isZoomed: isZoomed,
                scale: scale,
                offset: offset
            )
        )
    }
}
```

4b. Update the modifier call (line ~118):

```swift
                .dismissTransform(
                    isZoomed: viewModel.isZoomed,
                    scale: viewModel.photoScaleEffect,
                    offset: viewModel.dragOffset
                )
```

4c. Update the gesture (line ~171) to the new signatures:

```swift
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        guard viewModel.mayDismissByDrag() else { return }
                        viewModel.handleDragChanged(
                            translation: value.translation,
                            geometryHeight: geometry.size.height
                        )
                    }
                    .onEnded { value in
                        guard viewModel.mayDismissByDrag() else { return }
                        viewModel.handleDragEnded(
                            translation: value.translation,
                            verticalVelocity: value.velocity.height,
                            geometryHeight: geometry.size.height
                        ) { dismiss() }
                    }
            )
```

- [ ] **Step 5: Run the tests to verify they pass**

Run:
```bash
xcodebuild test -workspace SnapSafe.xcworkspace -scheme SnapSafe -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SnapSafeTests/EnhancedPhotoDetailViewModelDragTests -quiet
```
Expected: **PASS** (9 tests).

- [ ] **Step 6: Commit**

```bash
git add SnapSafe/Screens/PhotoDetail/EnhancedPhotoDetailViewModel.swift SnapSafe/Screens/PhotoDetail/EnhancedPhotoDetailView.swift SnapSafeTests/EnhancedPhotoDetailViewModelDragTests.swift
git commit -m "fix(viewer): latch dismiss-drag direction once and track both axes"
```

---

### Task 2: Chrome fades during the dismiss drag (photos and videos)

The photo toolbar lives outside the dragged layer; the video page's controls live inside it. Rather than restructuring the video page, fade ALL chrome out while the drag is engaged — then nothing visible moves with the video. Hosted UIKit pages learn about the drag through a shared `@Observable` object injected via `.environment`.

**Files:**
- Create: `SnapSafe/Screens/PhotoDetail/PagerChromeState.swift`
- Modify: `SnapSafe/Screens/PhotoDetail/EnhancedPhotoDetailView.swift` (own + sync chrome state, fade photo toolbar)
- Modify: `SnapSafe/Screens/PhotoDetail/PhotoPageViewController.swift` (thread chrome state to video pages; disable paging while dragging)
- Modify: `SnapSafe/Screens/PhotoDetail/Components/InlineVideoPlayerView.swift` (hide controls while dragging)

- [ ] **Step 1: Create `PagerChromeState`**

Create `SnapSafe/Screens/PhotoDetail/PagerChromeState.swift`:

```swift
//
//  PagerChromeState.swift
//  SnapSafe
//
//  Shared chrome state for the media detail pager. Owned by
//  EnhancedPhotoDetailView and injected into each hosted page (via
//  .environment) so pages rendered inside UIHostingControllers — like the
//  inline video player — can fade their controls while a dismiss drag is in
//  flight, matching the page-level photo toolbar.
//

import Observation

@MainActor
@Observable
final class PagerChromeState {
    var isDismissDragging = false
}
```

- [ ] **Step 2: Thread the state through the pager**

In `SnapSafe/Screens/PhotoDetail/PhotoPageViewController.swift`:

2a. Add inputs to the struct (after `@Binding var isZoomed: Bool`, line ~19):

```swift
    /// Shared chrome state injected into hosted pages so they can fade their
    /// controls during a dismiss drag.
    let chromeState: PagerChromeState
    /// True while a dismiss drag is engaged; horizontal paging is disabled so
    /// the pager can't start a page transition mid-dismiss.
    let isDismissDragging: Bool
```

2b. Update the struct's `init` to accept them (insert after the `isZoomed` parameter):

```swift
    init(
        allMedia: [GalleryMediaItem],
        currentIndex: Binding<Int>,
        isZoomed: Binding<Bool>,
        chromeState: PagerChromeState,
        isDismissDragging: Bool,
        onRequestDismiss: @escaping () -> Void,
        onVideoControlsVisibilityChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.allMedia = allMedia
        self._currentIndex = currentIndex
        self._isZoomed = isZoomed
        self.chromeState = chromeState
        self.isDismissDragging = isDismissDragging
        self.onRequestDismiss = onRequestDismiss
        self.onVideoControlsVisibilityChange = onVideoControlsVisibilityChange
    }
```

2c. In `updateUIViewController`, sync the coordinator before `updatePagingEnabled()`:

```swift
    func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {
        context.coordinator.allMedia = allMedia
        context.coordinator.currentIndexBinding = _currentIndex
        context.coordinator.isZoomedBinding = _isZoomed
        context.coordinator.isDismissDragging = isDismissDragging
        context.coordinator.onRequestDismiss = onRequestDismiss
        context.coordinator.onVideoControlsVisibilityChange = onVideoControlsVisibilityChange
        context.coordinator.updatePagingEnabled()
    }
```

2d. In `makeCoordinator`, pass the chrome state:

```swift
    func makeCoordinator() -> Coordinator {
        Coordinator(
            allMedia: allMedia,
            currentIndexBinding: _currentIndex,
            isZoomedBinding: _isZoomed,
            chromeState: chromeState,
            onRequestDismiss: onRequestDismiss,
            onVideoControlsVisibilityChange: onVideoControlsVisibilityChange
        )
    }
```

2e. In `Coordinator`, add the properties and init parameter:

```swift
        var isDismissDragging = false
        let chromeState: PagerChromeState
```

```swift
        init(
            allMedia: [GalleryMediaItem],
            currentIndexBinding: Binding<Int>,
            isZoomedBinding: Binding<Bool>,
            chromeState: PagerChromeState,
            onRequestDismiss: @escaping () -> Void,
            onVideoControlsVisibilityChange: @escaping (Bool) -> Void
        ) {
            self.allMedia = allMedia
            self.currentIndexBinding = currentIndexBinding
            self.isZoomedBinding = isZoomedBinding
            self.chromeState = chromeState
            self.onRequestDismiss = onRequestDismiss
            self.onVideoControlsVisibilityChange = onVideoControlsVisibilityChange
        }
```

2f. Extend `updatePagingEnabled`:

```swift
        // MARK: - Paging Control
        func updatePagingEnabled() {
            pageScrollView?.isScrollEnabled = !isZoomedBinding.wrappedValue && !isDismissDragging
        }
```

2g. In `viewController(at:)`, pass the chrome state to video pages:

```swift
            } else if let videoDef = item.videoDef {
                let hostingVC = InlineVideoHostingController(
                    videoDef: videoDef,
                    encryptionKey: item.encryptionKey,
                    chromeState: chromeState,
                    onRequestDismiss: onRequestDismiss,
                    onControlsVisibilityChange: { [weak self] visible in
                        self?.onVideoControlsVisibilityChange(visible)
                    }
                )
                vc = hostingVC
            }
```

2h. Update `InlineVideoHostingController` to inject the environment:

```swift
class InlineVideoHostingController: UIHostingController<AnyView> {
    init(
        videoDef: VideoDef,
        encryptionKey: SymmetricKey?,
        chromeState: PagerChromeState,
        onRequestDismiss: @escaping () -> Void,
        onControlsVisibilityChange: @escaping (Bool) -> Void
    ) {
        let view = InlineVideoPlayerView(
            videoDef: videoDef,
            encryptionKey: encryptionKey,
            onRequestDismiss: onRequestDismiss,
            onControlsVisibilityChange: onControlsVisibilityChange
        )
        super.init(rootView: AnyView(view.environment(chromeState)))
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
```

- [ ] **Step 3: Own the state in `EnhancedPhotoDetailView` and fade the photo toolbar**

In `SnapSafe/Screens/PhotoDetail/EnhancedPhotoDetailView.swift`:

3a. Add the state next to the view model (line ~74):

```swift
    @StateObject private var viewModel: EnhancedPhotoDetailViewModel
    @State private var chromeState = PagerChromeState()
```

3b. Update the `PhotoPageViewController` call (line ~103) with the new arguments:

```swift
                PhotoPageViewController(
                    allMedia: viewModel.allMedia,
                    currentIndex: $viewModel.currentIndex,
                    isZoomed: $viewModel.isZoomed,
                    chromeState: chromeState,
                    isDismissDragging: viewModel.isDismissDragging,
                    onRequestDismiss: { dismiss() },
                    onVideoControlsVisibilityChange: { visible in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.isVideoControlsVisible = visible
                        }
                    }
                )
```

3c. Fade and hit-disable the floating photo toolbar — wrap the existing `VStack { Spacer(); if !viewModel.currentIsVideo ... }` (line ~135) with:

```swift
                VStack {
                    Spacer()
                    if !viewModel.currentIsVideo, viewModel.currentIndex < viewModel.allMedia.count {
                        PhotoDetailToolbar(
                            onInfo: {
                                if let current = viewModel.currentPhotoDef {
                                    nav.presentSheet(.photoInfo(current))
                                }
                            },
                            onObfuscate: {
                                if let current = viewModel.currentPhotoDef {
                                    nav.navigate(to: .photoObfuscation(current))
                                }
                            },
                            onShare: { viewModel.shareCurrentPhoto() },
                            onDelete: { viewModel.showDeleteConfirmation = true },
                            onToggleDecoy: { viewModel.toggleDecoyStatus() },
                            isZoomed: viewModel.isZoomed,
                            showDecoyButton: viewModel.isPoisonPillConfigured,
                            decoyButtonTitle: viewModel.decoyButtonTitle,
                            decoyButtonIcon: viewModel.decoyButtonIcon,
                            isDecoyOperationLoading: viewModel.isDecoyOperationLoading
                        )
                    }
                }
                .opacity(viewModel.isDismissDragging ? 0 : 1)
                .allowsHitTesting(!viewModel.isDismissDragging)
                .animation(.easeInOut(duration: 0.2), value: viewModel.isDismissDragging)
```

3d. Sync the chrome state — add after the `.simultaneousGesture(DragGesture...)` modifier, still inside the `GeometryReader`'s content chain:

```swift
            .onChange(of: viewModel.isDismissDragging) { _, dragging in
                chromeState.isDismissDragging = dragging
            }
```

- [ ] **Step 4: Hide the video controls while dragging**

In `SnapSafe/Screens/PhotoDetail/Components/InlineVideoPlayerView.swift`:

4a. Add the environment read below `onControlsVisibilityChange` (line ~20):

```swift
    /// Pager-level chrome state; nil outside the pager (e.g. previews).
    @Environment(PagerChromeState.self) private var chrome: PagerChromeState?

    private var isChromeSuppressed: Bool { chrome?.isDismissDragging ?? false }
```

4b. Gate both control bars on it. The transport overlay condition (line ~65) becomes:

```swift
                    if viewModel.showControls && !isChromeSuppressed {
```

and the action bar condition (line ~94) becomes:

```swift
                if viewModel.showControls && !isChromeSuppressed {
```

4c. Animate the change locally (a `withAnimation` from the parent does not reliably cross the hosting-controller boundary). Add to the outer `ZStack` (after `Color.black.ignoresSafeArea()`'s sibling `VStack`, i.e. as a modifier on the `ZStack` itself, before `.onChange(of: scrubFraction)`):

```swift
        .animation(.easeInOut(duration: 0.2), value: isChromeSuppressed)
```

- [ ] **Step 5: Build, run the Task 1 tests (overlay test now exercises chrome path)**

Run:
```bash
xcodebuild test -workspace SnapSafe.xcworkspace -scheme SnapSafe -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SnapSafeTests/EnhancedPhotoDetailViewModelDragTests -quiet
```
Expected: **PASS**.

- [ ] **Step 6: Commit**

```bash
git add SnapSafe/Screens/PhotoDetail/PagerChromeState.swift SnapSafe/Screens/PhotoDetail/EnhancedPhotoDetailView.swift SnapSafe/Screens/PhotoDetail/PhotoPageViewController.swift SnapSafe/Screens/PhotoDetail/Components/InlineVideoPlayerView.swift
git commit -m "feat(viewer): fade all chrome during the dismiss drag"
```

---

### Task 3: Pinch-zoom for videos

Reuse `ZoomableScrollView` (the photo zoom container) around the video surface. The video page's tap-to-toggle-controls moves into a new `onSingleTap` callback on `ZoomableScrollView`, wired with `require(toFail:)` against its double-tap recognizer so double-tap zooms without flashing the controls. The video page reports zoom through the same `isZoomed` binding photos use, so paging and the dismiss-drag gate work unchanged.

**Files:**
- Modify: `SnapSafe/Screens/PhotoDetail/ZoomableScrollView.swift` (add `onSingleTap`)
- Modify: `SnapSafe/Screens/PhotoDetail/Components/InlineVideoPlayerView.swift` (wrap surface, accept `isZoomed`)
- Modify: `SnapSafe/Screens/PhotoDetail/PhotoPageViewController.swift` (thread `isZoomed` to video pages)

- [ ] **Step 1: Add `onSingleTap` to `ZoomableScrollView`**

In `SnapSafe/Screens/PhotoDetail/ZoomableScrollView.swift`:

1a. Add the stored property and init parameter (before `content`):

```swift
    private let minZoom: CGFloat
    private let maxZoom: CGFloat
    private let showsIndicators: Bool
    /// Optional single-tap callback. When set, a tap recognizer is installed
    /// that waits for the double-tap (zoom) recognizer to fail, so a double
    /// tap never also fires the single-tap action.
    private let onSingleTap: (() -> Void)?
    private let content: Content
```

```swift
    init(
        minZoom: CGFloat = 1.0,
        maxZoom: CGFloat = 4.0,
        showsIndicators: Bool = false,
        isZoomed: Binding<Bool>,
        onSingleTap: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.showsIndicators = showsIndicators
        self._isZoomed = isZoomed
        self.onSingleTap = onSingleTap
        self.content = content()
    }
```

1b. In `makeUIView`, after the existing `doubleTap` is added (line ~86), install the single-tap:

```swift
        context.coordinator.onSingleTap = onSingleTap
        if onSingleTap != nil {
            let singleTap = UITapGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleSingleTap(_:))
            )
            singleTap.numberOfTapsRequired = 1
            singleTap.require(toFail: doubleTap)
            scrollView.addGestureRecognizer(singleTap)
        }
```

1c. In `updateUIView`, keep the callback current (first line of the method):

```swift
        context.coordinator.onSingleTap = onSingleTap
```

1d. In `Coordinator`, add the property and handler:

```swift
        var onSingleTap: (() -> Void)?
```

```swift
        @objc internal func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            onSingleTap?()
        }
```

- [ ] **Step 2: Wrap the video surface and accept the zoom binding**

In `SnapSafe/Screens/PhotoDetail/Components/InlineVideoPlayerView.swift`:

2a. Add the binding and init parameter:

```swift
    /// Shared with the pager: true while the video is pinch-zoomed, which
    /// disables paging and the dismiss drag (same contract as photo pages).
    @Binding var isZoomed: Bool
```

```swift
    init(
        videoDef: VideoDef,
        encryptionKey: SymmetricKey?,
        isZoomed: Binding<Bool> = .constant(false),
        onRequestDismiss: @escaping () -> Void,
        onControlsVisibilityChange: ((Bool) -> Void)? = nil
    ) {
        self._isZoomed = isZoomed
        self.onRequestDismiss = onRequestDismiss
        self.onControlsVisibilityChange = onControlsVisibilityChange
        _viewModel = StateObject(wrappedValue: VideoPlayerViewModel(videoDef: videoDef, encryptionKey: encryptionKey))
    }
```

2b. Replace the player branch of the `Group` (line ~46) so the surface zooms, and move the controls toggle into `onSingleTap`:

```swift
                    Group {
                        if let player = viewModel.player {
                            ZoomableScrollView(
                                minZoom: 1.0,
                                maxZoom: 6.0,
                                isZoomed: $isZoomed,
                                onSingleTap: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        viewModel.toggleControls()
                                    }
                                }
                            ) {
                                VideoSurfaceView(player: player)
                            }
                        } else if viewModel.isLoading {
```

2c. Remove the now-redundant tap handling from the video-area `ZStack` — delete these two modifiers (lines ~86–91):

```swift
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.toggleControls()
                    }
                }
```

(keep `.ignoresSafeArea(edges: .top)`).

- [ ] **Step 3: Thread `isZoomed` to video pages in the pager**

In `SnapSafe/Screens/PhotoDetail/PhotoPageViewController.swift`:

3a. `viewController(at:)` video branch — pass the binding (final form, including Task 2's `chromeState`):

```swift
            } else if let videoDef = item.videoDef {
                let hostingVC = InlineVideoHostingController(
                    videoDef: videoDef,
                    encryptionKey: item.encryptionKey,
                    isZoomed: isZoomedBinding,
                    chromeState: chromeState,
                    onRequestDismiss: onRequestDismiss,
                    onControlsVisibilityChange: { [weak self] visible in
                        self?.onVideoControlsVisibilityChange(visible)
                    }
                )
                vc = hostingVC
            }
```

3b. `InlineVideoHostingController` (final form):

```swift
class InlineVideoHostingController: UIHostingController<AnyView> {
    init(
        videoDef: VideoDef,
        encryptionKey: SymmetricKey?,
        isZoomed: Binding<Bool>,
        chromeState: PagerChromeState,
        onRequestDismiss: @escaping () -> Void,
        onControlsVisibilityChange: @escaping (Bool) -> Void
    ) {
        let view = InlineVideoPlayerView(
            videoDef: videoDef,
            encryptionKey: encryptionKey,
            isZoomed: isZoomed,
            onRequestDismiss: onRequestDismiss,
            onControlsVisibilityChange: onControlsVisibilityChange
        )
        super.init(rootView: AnyView(view.environment(chromeState)))
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
```

Note: `Binding` captures the view model's storage by reference, so the binding baked in at page-creation time stays live — this is the same pattern `PhotoDetailHostingController` already relies on.

- [ ] **Step 4: Build**

Run:
```bash
xcodebuild build -workspace SnapSafe.xcworkspace -scheme SnapSafe -destination 'platform=iOS Simulator,name=iPhone 17' -quiet
```
Expected: build succeeds, no warnings in the touched files. (Check `VideoPlayerView.swift` line ~16 — if `InlineVideoPlayerView` is constructed anywhere else, the `isZoomed` parameter defaults to `.constant(false)`, so existing call sites still compile. Verify with `grep -rn "InlineVideoPlayerView(" SnapSafe/`.)

- [ ] **Step 5: Commit**

```bash
git add SnapSafe/Screens/PhotoDetail/ZoomableScrollView.swift SnapSafe/Screens/PhotoDetail/Components/InlineVideoPlayerView.swift SnapSafe/Screens/PhotoDetail/PhotoPageViewController.swift
git commit -m "feat(video): pinch-zoom on video pages via ZoomableScrollView"
```

---

### Task 4: Camera preview shows the full capture frame; raise still resolution

The session's `.high` preset delivers 16:9, but the preview aspect-fills a hard-coded 3:4 container, hiding the top/bottom of the frame that captures keep. Derive the container's aspect from the active format. Also raise `maxPhotoDimensions` to the format max (~4032×2268 instead of 1920×1080 stills) — re-applied per device, because a camera switch reuses the already-attached output.

**Files:**
- Create: `SnapSafe/Screens/Camera/Services/CameraPreviewLayout.swift`
- Create: `SnapSafeTests/CameraPreviewLayoutTests.swift`
- Modify: `SnapSafe/Screens/Camera/CameraViewModel.swift` (expose `captureAspectRatio`)
- Modify: `SnapSafe/Screens/Camera/CameraView.swift` (use it in `CameraPreviewView`)
- Modify: `SnapSafe/Screens/Camera/Services/CameraDeviceService.swift` (`maxPhotoDimensions`)
- Modify: `SnapSafe/Screens/Camera/Services/PhotoCaptureService.swift` (settings match output)

- [ ] **Step 1: Write the failing layout tests**

Create `SnapSafeTests/CameraPreviewLayoutTests.swift`:

```swift
//
//  CameraPreviewLayoutTests.swift
//  SnapSafeTests
//
//  The preview container must show exactly the frame that will be captured:
//  its aspect ratio derives from the active capture format (reported in
//  landscape, e.g. 1920×1080) rather than a hard-coded 3:4.
//

import CoreGraphics
import XCTest

@testable import SnapSafe

final class CameraPreviewLayoutTests: XCTestCase {

    // MARK: - portraitAspectRatio

    func test_aspectRatio_1080p_isNineSixteenths() {
        XCTAssertEqual(
            CameraPreviewLayout.portraitAspectRatio(formatWidth: 1920, formatHeight: 1080),
            0.5625,
            accuracy: 1e-9
        )
    }

    func test_aspectRatio_fourByThree_format() {
        XCTAssertEqual(
            CameraPreviewLayout.portraitAspectRatio(formatWidth: 4032, formatHeight: 3024),
            0.75,
            accuracy: 1e-9
        )
    }

    func test_aspectRatio_invalidDimensions_fallsBackToNineSixteenths() {
        XCTAssertEqual(
            CameraPreviewLayout.portraitAspectRatio(formatWidth: 0, formatHeight: 0),
            9.0 / 16.0,
            accuracy: 1e-9
        )
    }

    // MARK: - containerSize

    func test_containerSize_fillsWidth_whenHeightFits() {
        // iPhone-ish portrait screen, 16:9-portrait feed.
        let size = CameraPreviewLayout.containerSize(
            for: CGSize(width: 393, height: 852),
            aspectRatio: 0.5625
        )
        XCTAssertEqual(size.width, 393, accuracy: 1e-9)
        XCTAssertEqual(size.height, 393 / 0.5625, accuracy: 1e-6) // ≈ 698.67
    }

    func test_containerSize_limitsByHeight_whenTooTall() {
        let size = CameraPreviewLayout.containerSize(
            for: CGSize(width: 393, height: 500),
            aspectRatio: 0.5625
        )
        XCTAssertEqual(size.height, 500, accuracy: 1e-9)
        XCTAssertEqual(size.width, 500 * 0.5625, accuracy: 1e-9) // 281.25
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodebuild test -workspace SnapSafe.xcworkspace -scheme SnapSafe -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SnapSafeTests/CameraPreviewLayoutTests -quiet
```
Expected: **compile failure** — `CameraPreviewLayout` doesn't exist.

- [ ] **Step 3: Implement `CameraPreviewLayout`**

Create `SnapSafe/Screens/Camera/Services/CameraPreviewLayout.swift`:

```swift
//
//  CameraPreviewLayout.swift
//  SnapSafe
//
//  Pure layout math for the camera preview container, kept free of UIKit and
//  AVFoundation so it can be unit tested. The container's aspect ratio comes
//  from the ACTIVE CAPTURE FORMAT, so the preview shows exactly the frame
//  that will be captured (WYSIWYG) instead of an aspect-filled crop.
//

import CoreGraphics

enum CameraPreviewLayout {
    /// Portrait width:height ratio for a capture format whose dimensions are
    /// reported in landscape (e.g. 1920×1080 → 1080/1920 = 0.5625).
    /// Falls back to 9:16 (the `.high` preset's ratio) for degenerate input.
    static func portraitAspectRatio(formatWidth: Int32, formatHeight: Int32) -> CGFloat {
        guard formatWidth > 0, formatHeight > 0 else { return 9.0 / 16.0 }
        return CGFloat(formatHeight) / CGFloat(formatWidth)
    }

    /// Largest centered rect of `aspectRatio` (width/height) fitting `size`,
    /// preferring to fill the width.
    static func containerSize(for size: CGSize, aspectRatio: CGFloat) -> CGSize {
        let width = size.width
        let height = width / aspectRatio
        if height > size.height {
            return CGSize(width: size.height * aspectRatio, height: size.height)
        }
        return CGSize(width: width, height: height)
    }
}
```

- [ ] **Step 4: Run the layout tests to verify they pass**

Run:
```bash
xcodebuild test -workspace SnapSafe.xcworkspace -scheme SnapSafe -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SnapSafeTests/CameraPreviewLayoutTests -quiet
```
Expected: **PASS** (5 tests).

- [ ] **Step 5: Expose `captureAspectRatio` on the view model and use it in the preview**

5a. In `SnapSafe/Screens/Camera/CameraViewModel.swift`, next to the other `deviceService` pass-throughs (`var currentDevice: AVCaptureDevice? { deviceService.currentDevice }`, line ~39), add (plus `import CoreMedia` at the top of the file with the other imports):

```swift
    /// Portrait aspect (width/height) of the active capture format. The
    /// preview container uses this so what's on screen is exactly what gets
    /// captured. Falls back to 9:16 (.high preset) before setup completes.
    var captureAspectRatio: CGFloat {
        guard let format = currentDevice?.activeFormat else { return 9.0 / 16.0 }
        let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return CameraPreviewLayout.portraitAspectRatio(
            formatWidth: dims.width,
            formatHeight: dims.height
        )
    }
```

5b. In `SnapSafe/Screens/Camera/CameraView.swift` (`CameraPreviewView`):

Delete the constant (lines ~170–172):

```swift
    // Standard photo aspect ratio is 4:3
    // This is the ratio of most iPhone photos in portrait mode (3:4 actually, as width:height)
    private let photoAspectRatio: CGFloat = 3.0 / 4.0 // width/height in portrait mode
```

Replace `calculatePreviewContainerSize` (lines ~304–320) with:

```swift
    // Container sized to the active capture format so preview == capture.
    private func calculatePreviewContainerSize(for size: CGSize) -> CGSize {
        CameraPreviewLayout.containerSize(for: size, aspectRatio: cameraModel.captureAspectRatio)
    }
```

(Both existing call sites in `makeUIView` and `updateUIView` keep working unchanged. `updateUIView` re-runs when the view model republishes — e.g. when zoom limits update after device setup — and resizes the container/preview layer frames it already manages.)

- [ ] **Step 6: Raise still-photo resolution, re-applied per device**

6a. In `SnapSafe/Screens/Camera/Services/CameraDeviceService.swift`, replace the output-attachment block in `setupCamera` (lines ~136–140) so quality config runs on every (re)setup, not only when the output is first added — a camera switch reuses the attached output but the new device's supported dimensions differ:

```swift
            // Add photo output (first setup only; switchCamera re-runs setup
            // with the output already attached)
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            configurePhotoOutputForMaxQuality(for: device)
```

6b. Replace `configurePhotoOutputForMaxQuality` (lines ~253–255):

```swift
    private func configurePhotoOutputForMaxQuality(for device: AVCaptureDevice) {
        output.maxPhotoQualityPrioritization = .quality
        // Allow the largest stills the active format supports (~4032×2268 on a
        // 16:9 video format) instead of the session preset's video resolution.
        // Same aspect ratio as the format, so preview framing still matches.
        let supported = device.activeFormat.supportedMaxPhotoDimensions
        if let maxDimensions = supported.max(by: {
            Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height)
        }) {
            output.maxPhotoDimensions = maxDimensions
        }
    }
```

6c. In `SnapSafe/Screens/Camera/Services/PhotoCaptureService.swift`, per-capture settings must opt in too. Replace `createAdvancedPhotoSettings` (lines ~169–173):

```swift
    private func createAdvancedPhotoSettings(for output: AVCapturePhotoOutput) -> AVCapturePhotoSettings {
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .quality
        settings.maxPhotoDimensions = output.maxPhotoDimensions
        return settings
    }
```

and its call site in `capturePhoto` (line ~52):

```swift
        let photoSettings = createAdvancedPhotoSettings(for: output)
```

- [ ] **Step 7: Build and run camera-related tests**

Run:
```bash
xcodebuild test -workspace SnapSafe.xcworkspace -scheme SnapSafe -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SnapSafeTests/CameraPreviewLayoutTests -only-testing:SnapSafeTests/CameraZoomMappingTests -quiet
```
Expected: **PASS**.

- [ ] **Step 8: Commit**

```bash
git add SnapSafe/Screens/Camera/Services/CameraPreviewLayout.swift SnapSafeTests/CameraPreviewLayoutTests.swift SnapSafe/Screens/Camera/CameraViewModel.swift SnapSafe/Screens/Camera/CameraView.swift SnapSafe/Screens/Camera/Services/CameraDeviceService.swift SnapSafe/Screens/Camera/Services/PhotoCaptureService.swift
git commit -m "fix(camera): preview container matches capture aspect; max-res stills"
```

---

### Task 5: Full verification

- [ ] **Step 1: Run the complete unit test suite (includes the test-target-membership guard)**

Run:
```bash
bundle exec fastlane test
```
Expected: all tests pass, membership check passes.

- [ ] **Step 2: Manual on-device checklist** (requires a physical device — camera and gestures don't exercise meaningfully in the simulator):

- Photo page: hold and drag the image through all four screen regions, including over the toolbar area — no catching; toolbar and counter fade out on drag start, fade back on cancel; release past ~25% height dismisses.
- Photo page: a drag that starts horizontally pages; a drag that starts vertically never pages mid-dismiss.
- Video page: same drag checks; transport bar and action toolbar fade out during the drag instead of moving with the video.
- Video page: pinch zooms while playing and while paused; pan while zoomed; double-tap zooms in/out without toggling the controls; single tap still toggles controls; paging and dismiss-drag disabled while zoomed.
- Camera: preview shows the full 16:9 frame (corner brackets hug the new container); capture a photo and a video of a scene with reference points at the preview's top/bottom edges — saved media matches the preview edge-for-edge; check a captured photo's dimensions are ~4032×2268 (Info sheet), not 1920×1080.
- Camera: switch front/back, capture again — framing still matches, no crash (per-device `maxPhotoDimensions`).
