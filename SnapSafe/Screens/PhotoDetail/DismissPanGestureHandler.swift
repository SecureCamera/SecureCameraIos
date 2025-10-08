//
//  DismissPanGestureHandler.swift
//  SnapSafe
//
//  Created by Bill Booth on 10/7/25.
//

import UIKit
import SwiftUI

class DismissPanGestureHandler: NSObject, UIGestureRecognizerDelegate {
    private weak var targetView: UIView?
    private let isZoomedCallback: () -> Bool
    private let onDragChanged: (CGFloat, CGFloat) -> Void  // translation, progress
    private let onDragEnded: (CGFloat, CGFloat, @escaping () -> Void) -> Void  // translation, velocity, dismiss callback

    private var panGesture: UIPanGestureRecognizer?

    init(
        targetView: UIView,
        isZoomedCallback: @escaping () -> Bool,
        onDragChanged: @escaping (CGFloat, CGFloat) -> Void,
        onDragEnded: @escaping (CGFloat, CGFloat, @escaping () -> Void) -> Void
    ) {
        self.targetView = targetView
        self.isZoomedCallback = isZoomedCallback
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
        super.init()

        setupGesture()
    }

    private func setupGesture() {
        guard let targetView = targetView else { return }

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        targetView.addGestureRecognizer(pan)
        panGesture = pan
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view else { return }

        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)

        switch gesture.state {
        case .changed:
            // Only respond to downward drags
            guard translation.y > 0 else { return }

            let progress = min(translation.y / (view.bounds.height * 0.4), 1.0)
            onDragChanged(translation.y, progress)

        case .ended, .cancelled:
            onDragEnded(translation.y, velocity.y) {
                // Dismiss callback handled by view model
            }

        default:
            break
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Don't allow dismiss when zoomed
        guard !isZoomedCallback() else { return false }

        // Only begin if this is a downward drag
        if let pan = gestureRecognizer as? UIPanGestureRecognizer,
           let view = gestureRecognizer.view {
            let translation = pan.translation(in: view)
            let velocity = pan.velocity(in: view)

            guard abs(translation.y) > abs(translation.x) ||
                  abs(velocity.y) > abs(velocity.x) else {
                return false
            }

            return translation.y > 0 || velocity.y > 0
        }

        return true
    }

    /// Allow simultaneous recognition with UIScrollView pan gestures
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return otherGestureRecognizer.view is UIScrollView
    }

    /// This gesture should fail if it's a horizontal swipe (let paging handle it)
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // If the other gesture is from a page scroll view, we should wait
        // to see if it's a page transition
        return false
    }
}
