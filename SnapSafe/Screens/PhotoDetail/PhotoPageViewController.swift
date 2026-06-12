//
//  PhotoPageViewController.swift
//  SnapSafe
//
//  Created by Bill Booth on 10/7/25.
//

import SwiftUI
import UIKit
import AVKit
import CryptoKit
import Logging


struct PhotoPageViewController: UIViewControllerRepresentable {
    // MARK: - Inputs
    let allMedia: [GalleryMediaItem]
    @Binding var currentIndex: Int
    @Binding var isZoomed: Bool
    /// Shared chrome state injected into hosted pages so they can fade their
    /// controls during a dismiss drag.
    let chromeState: PagerChromeState
    /// True while a dismiss drag is engaged; horizontal paging is disabled so
    /// the pager can't start a page transition mid-dismiss.
    let isDismissDragging: Bool
    /// Invoked when a video page deletes its video, so the detail view can pop.
    let onRequestDismiss: () -> Void
    /// Invoked by inline video pages when their glass controls show/hide, so
    /// the photo counter chip overlay can fade together with them.
    let onVideoControlsVisibilityChange: (Bool) -> Void

    // MARK: - Init
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

    // MARK: - UIViewControllerRepresentable
    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageVC = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 20]
        )

        pageVC.dataSource = context.coordinator
        pageVC.delegate = context.coordinator
        pageVC.view.backgroundColor = .clear

        if currentIndex < allMedia.count {
            let initialVC = context.coordinator.viewController(at: currentIndex)
            pageVC.setViewControllers(
                [initialVC],
                direction: .forward,
                animated: false
            )
        }

        if let scrollView = pageVC.view.subviews.compactMap({ $0 as? UIScrollView }).first {
            context.coordinator.pageScrollView = scrollView
        }

        return pageVC
    }

    func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {
        context.coordinator.allMedia = allMedia
        context.coordinator.currentIndexBinding = _currentIndex
        context.coordinator.isZoomedBinding = _isZoomed
        context.coordinator.isDismissDragging = isDismissDragging
        context.coordinator.onRequestDismiss = onRequestDismiss
        context.coordinator.onVideoControlsVisibilityChange = onVideoControlsVisibilityChange
        context.coordinator.updatePagingEnabled()
    }

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

    // MARK: - Coordinator
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var allMedia: [GalleryMediaItem]
        var currentIndexBinding: Binding<Int>
        var isZoomedBinding: Binding<Bool>
        var isDismissDragging = false
        let chromeState: PagerChromeState
        var onRequestDismiss: () -> Void
        var onVideoControlsVisibilityChange: (Bool) -> Void
        weak var pageScrollView: UIScrollView?
        private var viewControllerCache: [Int: UIViewController] = [:]

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

        // MARK: - View Controller Management
        func viewController(at index: Int) -> UIViewController {
            if let cached = viewControllerCache[index] {
                return cached
            }

            let item = allMedia[index]
            let vc: UIViewController

            if let photoDef = item.photoDef {
                let hostingVC = PhotoDetailHostingController(
                    photo: photoDef,
                    isZoomed: isZoomedBinding
                )
                vc = hostingVC
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
            } else {
                // Fallback: empty black page
                let fallback = UIViewController()
                fallback.view.backgroundColor = .black
                vc = fallback
            }

            vc.view.backgroundColor = .clear
            viewControllerCache[index] = vc
            return vc
        }

        // MARK: - Paging Control
        func updatePagingEnabled() {
            pageScrollView?.isScrollEnabled = !isZoomedBinding.wrappedValue && !isDismissDragging
        }

        // MARK: - UIPageViewControllerDataSource
        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let index = viewControllerCache.first(where: { $0.value === viewController })?.key,
                  index > 0 else {
                return nil
            }
            return self.viewController(at: index - 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let index = viewControllerCache.first(where: { $0.value === viewController })?.key,
                  index < allMedia.count - 1 else {
                return nil
            }
            return self.viewController(at: index + 1)
        }

        // MARK: - UIPageViewControllerDelegate
        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard completed,
                  let visibleVC = pageViewController.viewControllers?.first,
                  let newIndex = viewControllerCache.first(where: { $0.value === visibleVC })?.key else {
                return
            }

            DispatchQueue.main.async {
                self.isZoomedBinding.wrappedValue = false
                self.currentIndexBinding.wrappedValue = newIndex
            }

            Logger.ui.debug("Page changed to index \(newIndex)")
        }
    }
}

// MARK: - Hosting Controller for a single photo page

class PhotoDetailHostingController: UIHostingController<AnyView> {
    init(photo: PhotoDef, isZoomed: Binding<Bool>) {
        let view = PhotoDetailView(
            photo: photo,
            onDelete: nil,
            onDismiss: nil,
            isZoomed: isZoomed
        )
        super.init(rootView: AnyView(view))
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Hosting Controller for an inline video page

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
