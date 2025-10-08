//
//  PhotoPageViewController.swift
//  SnapSafe
//
//  Created by Bill Booth on 10/7/25.
//

import SwiftUI
import UIKit
import Logging


struct PhotoPageViewController: UIViewControllerRepresentable {
    // MARK: - Inputs
    let photos: [PhotoDef]
    @Binding var currentIndex: Int
    @Binding var isZoomed: Bool

    // MARK: - Init
    init(
        photos: [PhotoDef],
        currentIndex: Binding<Int>,
        isZoomed: Binding<Bool>
    ) {
        self.photos = photos
        self._currentIndex = currentIndex
        self._isZoomed = isZoomed
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

        if currentIndex < photos.count {
            let initialVC = context.coordinator.viewController(at: currentIndex)
            pageVC.setViewControllers(
                [initialVC],
                direction: .forward,
                animated: false
            )
        }

        if let scrollView = pageVC.view.subviews.compactMap({ $0 as? UIScrollView }).first {
            context.coordinator.pageScrollView = scrollView
            context.coordinator.setupGestureCoordination(scrollView: scrollView)
        }

        return pageVC
    }

    func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {
        context.coordinator.photos = photos
        context.coordinator.currentIndexBinding = _currentIndex
        context.coordinator.isZoomedBinding = _isZoomed
        context.coordinator.updatePagingEnabled()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            photos: photos,
            currentIndexBinding: _currentIndex,
            isZoomedBinding: _isZoomed
        )
    }

    // MARK: - Coordinator
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var photos: [PhotoDef]
        var currentIndexBinding: Binding<Int>
        var isZoomedBinding: Binding<Bool>
        weak var pageScrollView: UIScrollView?
        private var viewControllerCache: [Int: PhotoDetailHostingController] = [:]

        init(photos: [PhotoDef], currentIndexBinding: Binding<Int>, isZoomedBinding: Binding<Bool>) {
            self.photos = photos
            self.currentIndexBinding = currentIndexBinding
            self.isZoomedBinding = isZoomedBinding
        }

        // MARK: - View Controller Management
        func viewController(at index: Int) -> PhotoDetailHostingController {
            if let cached = viewControllerCache[index] {
                return cached
            }

            let photo = photos[index]
            let vc = PhotoDetailHostingController(
                photo: photo,
                isZoomed: isZoomedBinding
            )
            vc.view.backgroundColor = .clear

            viewControllerCache[index] = vc

            return vc
        }

        // MARK: - Gesture Coordination
        func setupGestureCoordination(scrollView: UIScrollView) {
            // The page scroll view's pan gesture will automatically be coordinated
            // with the zoom scroll view's pan gesture by UIKit's gesture system
            // We're doing this all in UIkit
        }

        // MARK: - Paging Control
        func updatePagingEnabled() {
            // Disable paging when zoomed to allow free panning in all directions
            pageScrollView?.isScrollEnabled = !isZoomedBinding.wrappedValue
        }

        // MARK: - UIPageViewControllerDataSource
        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let vc = viewController as? PhotoDetailHostingController,
                  let index = viewControllerCache.first(where: { $0.value === vc })?.key,
                  index > 0 else {
                return nil
            }
            return self.viewController(at: index - 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let vc = viewController as? PhotoDetailHostingController,
                  let index = viewControllerCache.first(where: { $0.value === vc })?.key,
                  index < photos.count - 1 else {
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
                  let visibleVC = pageViewController.viewControllers?.first as? PhotoDetailHostingController,
                  let newIndex = viewControllerCache.first(where: { $0.value === visibleVC })?.key else {
                return
            }

            // Update binding on main thread
            DispatchQueue.main.async {
                self.isZoomedBinding.wrappedValue = false
                self.currentIndexBinding.wrappedValue = newIndex
            }

            Logger.ui.debug("Page changed to index \(newIndex)")
        }
    }
}

// MARK: - Hosting Controller for PhotoDetailView
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
