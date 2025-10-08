//
//  ZoomableScrollView.swift
//  SnapSafe
//
//  Created by Bill Booth on 10/6/25.
//

import Foundation
import SwiftUI
import UIKit

public struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    // MARK: – Inputs
    private let minZoom: CGFloat
    private let maxZoom: CGFloat
    private let showsIndicators: Bool
    private let content: Content

    // MARK: – Zoom surfaced to SwiftUI
    @Binding private var isZoomed: Bool

    // MARK: – Init
    public init(
        minZoom: CGFloat = 1.0,
        maxZoom: CGFloat = 4.0,
        showsIndicators: Bool = false,
        isZoomed: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.showsIndicators = showsIndicators
        self._isZoomed = isZoomed
        self.content = content()
    }

    // MARK: – UIViewRepresentable
    public func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = showsIndicators
        scrollView.showsHorizontalScrollIndicator = showsIndicators
        scrollView.bounces = true
        scrollView.bouncesZoom = true
        scrollView.clipsToBounds = true
        scrollView.decelerationRate = .fast
        scrollView.minimumZoomScale = minZoom
        scrollView.maximumZoomScale = maxZoom
        scrollView.delegate = context.coordinator
        scrollView.backgroundColor = .clear

        // Enable simultaneous pan and pinch gestures (allows 2-finger pan during/after pinch)
        scrollView.panGestureRecognizer.maximumNumberOfTouches = 2

        let hosted = context.coordinator.hostingController
        hosted.view.backgroundColor = .clear
        hosted.view.translatesAutoresizingMaskIntoConstraints = false

        scrollView.addSubview(hosted.view)

        NSLayoutConstraint.activate([
            hosted.view.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor
            ),
            hosted.view.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor
            ),
            hosted.view.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor
            ),
            hosted.view.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor
            ),
            hosted.view.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor
            ),
            hosted.view.heightAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.heightAnchor
            )
        ])

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    public func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.hostingController.rootView = content

        let atMin = abs(uiView.zoomScale - uiView.minimumZoomScale) < 0.01
        if isZoomed && atMin {
            DispatchQueue.main.async {
                self.isZoomed = false
            }
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(isZoomed: _isZoomed, content: content)
    }

    // MARK: – Coordinator
    public final class Coordinator: NSObject, UIScrollViewDelegate {
        fileprivate let hostingController: UIHostingController<Content>
        private var isZoomedBinding: Binding<Bool>
        private var isZooming: Bool = false

        internal init(isZoomed: Binding<Bool>, content: Content) {
            self.hostingController = UIHostingController(rootView: content)
            self.isZoomedBinding = isZoomed
        }

        public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostingController.view
        }

        public func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            isZooming = true
        }

        public func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let atMin = abs(scrollView.zoomScale - scrollView.minimumZoomScale) < 0.01
            let newZoomState = !atMin

            if isZoomedBinding.wrappedValue != newZoomState {
                DispatchQueue.main.async {
                    self.isZoomedBinding.wrappedValue = newZoomState
                }
            }
            // Don't adjust content insets during zoom - let UIKit handle the anchor point
        }

        public func scrollViewDidEndZooming(
            _ scrollView: UIScrollView,
            with view: UIView?,
            atScale scale: CGFloat
        ) {
            isZooming = false
            centerContentIfNeeded(scrollView)
        }

        public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            centerContentIfNeeded(scrollView)
        }

        public func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // Only adjust centering when not actively zooming
            if !isZooming {
                centerContentIfNeeded(scrollView)
            }
        }

        // MARK: – Double Tap Zoom
        @objc internal func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            let point = gesture.location(in: hostingController.view)
            let min = scrollView.minimumZoomScale
            let target: CGFloat =
                (abs(scrollView.zoomScale - min) < 0.01) ? min * 2.0 : min

            let size = CGSize(
                width: scrollView.bounds.size.width / target,
                height: scrollView.bounds.size.height / target
            )
            let origin = CGPoint(x: point.x - size.width / 2.0,
                                 y: point.y - size.height / 2.0)
            let rect = CGRect(origin: origin, size: size)
            scrollView.zoom(to: rect, animated: true)
        }

        // Center the content when it's smaller than the bounds (Photos-like)
        private func centerContentIfNeeded(_ scrollView: UIScrollView) {
            guard let view = hostingController.view else { return }
            let boundsSize = scrollView.bounds.size
            let contentSize = view.frame.size

            // Calculate the required insets to center the content
            let horizontalInset = max(0, (boundsSize.width - contentSize.width) / 2.0)
            let verticalInset = max(0, (boundsSize.height - contentSize.height) / 2.0)

            // Use content insets to center, which doesn't interfere with zoom anchoring
            scrollView.contentInset = UIEdgeInsets(
                top: verticalInset,
                left: horizontalInset,
                bottom: verticalInset,
                right: horizontalInset
            )
        }
    }
}
