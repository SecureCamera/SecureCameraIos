//
//  CameraView.swift
//  SnapSafe
//
//  Created by Bill Booth on 6/10/25.
//

import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

// SwiftUI wrapper for the camera preview
struct CameraView: View {
    @ObservedObject var cameraModel: CameraModel

    // Add a slightly darker background to emphasize the capture area
    let backgroundOpacity: Double = 0.2

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background color to emphasize the capture area
                Color.black
                    .ignoresSafeArea()

                // Camera preview represented by UIViewRepresentable
                CameraPreviewView(cameraModel: cameraModel, viewSize: geometry.size)
                    .ignoresSafeArea()

                // Focus indicator overlay with proper coordinates
                if cameraModel.showingFocusIndicator, let point = cameraModel.focusIndicatorPoint {
                    FocusIndicatorView()
                        .position(x: point.x, y: point.y)
                        .transition(.scale.combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.2), value: cameraModel.showingFocusIndicator)
                }
            }
            .onAppear {
                print("Camera view size: \(geometry.size.width)x\(geometry.size.height)")
            }
        }
    }
}

// UIViewRepresentable for camera preview
struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraModel: CameraModel
    var viewSize: CGSize // Store the parent view's size for coordinate conversion

    // Standard photo aspect ratio is 4:3
    // This is the ratio of most iPhone photos in portrait mode (3:4 actually, as width:height)
    private let photoAspectRatio: CGFloat = 3.0 / 4.0 // width/height in portrait mode

    // Store the view reference to help with coordinate mapping
    class CameraPreviewHolder {
        weak var view: UIView?
        var previewLayer: AVCaptureVideoPreviewLayer?
        var previewContainer: UIView? // Container with correct aspect ratio
    }

    // Shared holder to maintain a reference to the view and preview layer
    private let viewHolder = CameraPreviewHolder()

    func makeUIView(context: Context) -> UIView {
        // Create a view with the exact size passed from parent
        let view = UIView(frame: CGRect(origin: .zero, size: viewSize))
        print("Creating camera preview with size: \(viewSize.width)x\(viewSize.height)")

        // Store the view reference
        viewHolder.view = view

        // Calculate the container size to match photo aspect ratio
        let containerSize = calculatePreviewContainerSize(for: viewSize)
        let containerOrigin = CGPoint(
            x: (viewSize.width - containerSize.width) / 2,
            y: (viewSize.height - containerSize.height) / 2
        )

        // Create the container view with proper aspect ratio
        let containerView = UIView(frame: CGRect(origin: containerOrigin, size: containerSize))
        containerView.backgroundColor = .clear
        containerView.clipsToBounds = true
        view.addSubview(containerView)
        viewHolder.previewContainer = containerView

        // Add visual guides for the capture area

        // 1. Add a border to visualize the capture area
        let borderLayer = CALayer()
        borderLayer.frame = containerView.bounds
        borderLayer.borderColor = UIColor.white.withAlphaComponent(0.7).cgColor
        borderLayer.borderWidth = 2.0
        containerView.layer.addSublayer(borderLayer)

        // 2. Add corner brackets for a more camera-like appearance
        let cornerSize: CGFloat = 20.0
        let cornerThickness: CGFloat = 3.0
        let cornerColor = UIColor.white.withAlphaComponent(0.8).cgColor

        // Top-left corner
        let topLeftCornerH = CALayer()
        topLeftCornerH.frame = CGRect(x: 0, y: 0, width: cornerSize, height: cornerThickness)
        topLeftCornerH.backgroundColor = cornerColor
        containerView.layer.addSublayer(topLeftCornerH)

        let topLeftCornerV = CALayer()
        topLeftCornerV.frame = CGRect(x: 0, y: 0, width: cornerThickness, height: cornerSize)
        topLeftCornerV.backgroundColor = cornerColor
        containerView.layer.addSublayer(topLeftCornerV)

        // Top-right corner
        let topRightCornerH = CALayer()
        topRightCornerH.frame = CGRect(x: containerSize.width - cornerSize, y: 0, width: cornerSize, height: cornerThickness)
        topRightCornerH.backgroundColor = cornerColor
        containerView.layer.addSublayer(topRightCornerH)

        let topRightCornerV = CALayer()
        topRightCornerV.frame = CGRect(x: containerSize.width - cornerThickness, y: 0, width: cornerThickness, height: cornerSize)
        topRightCornerV.backgroundColor = cornerColor
        containerView.layer.addSublayer(topRightCornerV)

        // Bottom-left corner
        let bottomLeftCornerH = CALayer()
        bottomLeftCornerH.frame = CGRect(x: 0, y: containerSize.height - cornerThickness, width: cornerSize, height: cornerThickness)
        bottomLeftCornerH.backgroundColor = cornerColor
        containerView.layer.addSublayer(bottomLeftCornerH)

        let bottomLeftCornerV = CALayer()
        bottomLeftCornerV.frame = CGRect(x: 0, y: containerSize.height - cornerSize, width: cornerThickness, height: cornerSize)
        bottomLeftCornerV.backgroundColor = cornerColor
        containerView.layer.addSublayer(bottomLeftCornerV)

        // Bottom-right corner
        let bottomRightCornerH = CALayer()
        bottomRightCornerH.frame = CGRect(x: containerSize.width - cornerSize, y: containerSize.height - cornerThickness, width: cornerSize, height: cornerThickness)
        bottomRightCornerH.backgroundColor = cornerColor
        containerView.layer.addSublayer(bottomRightCornerH)

        let bottomRightCornerV = CALayer()
        bottomRightCornerV.frame = CGRect(x: containerSize.width - cornerThickness, y: containerSize.height - cornerSize, width: cornerThickness, height: cornerSize)
        bottomRightCornerV.backgroundColor = cornerColor
        containerView.layer.addSublayer(bottomRightCornerV)

        // Add a label to indicate that this is the capture area
        let captureLabel = UILabel()
        captureLabel.text = "CAPTURE AREA"
        captureLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        captureLabel.font = UIFont.systemFont(ofSize: 10, weight: .bold)
        captureLabel.sizeToFit()
        captureLabel.frame = CGRect(
            x: (containerSize.width - captureLabel.frame.width) / 2,
            y: 10,
            width: captureLabel.frame.width,
            height: captureLabel.frame.height
        )
        containerView.addSubview(captureLabel)

        // Create and configure the preview layer
        let previewLayer = AVCaptureVideoPreviewLayer()
        previewLayer.session = cameraModel.session
        previewLayer.frame = containerView.bounds
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.connection?.videoRotationAngle = 90 // Force portrait orientation

        // Store the preview layer in our holder instead of directly in the cameraModel
        viewHolder.previewLayer = previewLayer

        // Ensure the layer is added to the container view
        containerView.layer.addSublayer(previewLayer)

        // Add gesture recognizers
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handlePinchGesture(_:)))
        view.addGestureRecognizer(pinchGesture)

        let doubleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleDoubleTapGesture(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTapGesture)

        // Add single tap gesture for quick focus
        let singleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleSingleTapGesture(_:)))
        singleTapGesture.requiresExclusiveTouchType = true

        // Ensure single tap doesn't conflict with double tap
        singleTapGesture.require(toFail: doubleTapGesture)
        view.addGestureRecognizer(singleTapGesture)

        // Note: We DO NOT start the session here anymore - it's handled below after configuration is committed

        // Store exact view dimensions in the model for coordinate mapping
        cameraModel.viewSize = viewSize

        // Assign the preview layer to cameraModel after the view is created
        // This needs to be done on the main thread since it modifies @Published property
        DispatchQueue.main.async {
            cameraModel.preview = previewLayer
        }

        return view
    }

    // Calculate the container size based on the photo aspect ratio
    private func calculatePreviewContainerSize(for size: CGSize) -> CGSize {
        // Calculate the container size to match photo aspect ratio
        // In portrait mode, we're comparing width:height
        // We prioritize fitting the width to match the device's screen width
        let width = size.width
        let height = width / photoAspectRatio

        // If height exceeds the available space, adjust both dimensions
        if height > size.height {
            // Use the available height
            let adjustedHeight = size.height
            let adjustedWidth = adjustedHeight * photoAspectRatio
            return CGSize(width: adjustedWidth, height: adjustedHeight)
        } else {
            return CGSize(width: width, height: height)
        }
    }

    func updateUIView(_ uiView: UIView, context _: Context) {
        // Update the preview layer frame when the view updates
        DispatchQueue.main.async {
            // Update frame with the latest size
            uiView.frame = CGRect(origin: .zero, size: viewSize)

            // Calculate the container size to match photo aspect ratio
            let containerSize = calculatePreviewContainerSize(for: viewSize)
            let containerOrigin = CGPoint(
                x: (viewSize.width - containerSize.width) / 2,
                y: (viewSize.height - containerSize.height) / 2
            )

            // Update the container view frame
            if let containerView = viewHolder.previewContainer {
                containerView.frame = CGRect(origin: containerOrigin, size: containerSize)

                // Update the preview layer frame to match container
                if let layer = viewHolder.previewLayer {
                    layer.frame = containerView.bounds

                    // Ensure we're using the correct layer in the camera model
                    // Only update if necessary to avoid excessive property changes
                    if cameraModel.preview !== layer {
                        cameraModel.preview = layer
                    }
                }

                // Update all visual indicators
                if containerView.layer.sublayers?.count ?? 0 > 0 {
                    // Update border
                    if let borderLayer = containerView.layer.sublayers?.first(where: { $0.borderWidth > 0 }) {
                        borderLayer.frame = containerView.bounds
                    }

                    // Update corner guides
                    let cornerSize: CGFloat = 20.0
                    let cornerThickness: CGFloat = 3.0

                    // Find corner guides by their size and position
                    for layer in containerView.layer.sublayers ?? [] {
                        // Skip the border layer
                        if layer.borderWidth > 0 { continue }

                        // Update corner layers based on their position
                        if layer.frame.origin.x == 0, layer.frame.origin.y == 0 {
                            // Top-left horizontal
                            if layer.frame.height == cornerThickness {
                                layer.frame = CGRect(x: 0, y: 0, width: cornerSize, height: cornerThickness)
                            }
                            // Top-left vertical
                            else if layer.frame.width == cornerThickness {
                                layer.frame = CGRect(x: 0, y: 0, width: cornerThickness, height: cornerSize)
                            }
                        } else if layer.frame.origin.y == 0, layer.frame.origin.x > 0 {
                            // Top-right horizontal
                            if layer.frame.height == cornerThickness {
                                layer.frame = CGRect(x: containerSize.width - cornerSize, y: 0, width: cornerSize, height: cornerThickness)
                            }
                            // Top-right vertical
                            else if layer.frame.width == cornerThickness {
                                layer.frame = CGRect(x: containerSize.width - cornerThickness, y: 0, width: cornerThickness, height: cornerSize)
                            }
                        } else if layer.frame.origin.x == 0, layer.frame.origin.y > 0 {
                            // Bottom-left horizontal
                            if layer.frame.height == cornerThickness {
                                layer.frame = CGRect(x: 0, y: containerSize.height - cornerThickness, width: cornerSize, height: cornerThickness)
                            }
                            // Bottom-left vertical
                            else if layer.frame.width == cornerThickness {
                                layer.frame = CGRect(x: 0, y: containerSize.height - cornerSize, width: cornerThickness, height: cornerSize)
                            }
                        } else if layer.frame.origin.x > 0, layer.frame.origin.y > 0 {
                            // Bottom-right horizontal
                            if layer.frame.height == cornerThickness {
                                layer.frame = CGRect(x: containerSize.width - cornerSize, y: containerSize.height - cornerThickness, width: cornerSize, height: cornerThickness)
                            }
                            // Bottom-right vertical
                            else if layer.frame.width == cornerThickness {
                                layer.frame = CGRect(x: containerSize.width - cornerThickness, y: containerSize.height - cornerSize, width: cornerThickness, height: cornerSize)
                            }
                        }
                    }

                    // Update the capture area label position
                    for subview in containerView.subviews {
                        if let label = subview as? UILabel, label.text == "CAPTURE AREA" {
                            label.frame = CGRect(
                                x: (containerSize.width - label.frame.width) / 2,
                                y: 10,
                                width: label.frame.width,
                                height: label.frame.height
                            )
                        }
                    }
                }
            }

            // Update the size in the model
            cameraModel.viewSize = containerSize // Store the actual photo preview size
            // print("📐 Updated camera preview to size: \(containerSize.width)x\(containerSize.height)")
        }
    }

    // This method is called once after makeUIView
    func makeCoordinator() -> Coordinator {
        // Create coordinator first - this shouldn't trigger camera operations
        let coordinator = Coordinator(self)

        // Capture cameraModel to avoid potential reference issues
        let capturedCameraModel = cameraModel

        // Give a slight delay before starting the camera session
        // This ensures all UI setup is complete and configuration has been committed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Start camera on background thread after delay
            DispatchQueue.global(qos: .userInitiated).async {
                if !capturedCameraModel.session.isRunning {
                    print("Starting camera session from makeCoordinator after delay")
                    capturedCameraModel.session.startRunning()
                }
            }
        }

        return coordinator
    }

    // Coordinator for handling UIKit gestures
    class Coordinator: NSObject {
        var parent: CameraPreviewView
        private var initialScale: CGFloat = 1.0

        init(_ parent: CameraPreviewView) {
            self.parent = parent
        }

        // Handle pinch gesture for zoom with continuous updates
        @objc func handlePinchGesture(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                // Store initial scale when gesture begins
                initialScale = gesture.scale
                parent.cameraModel.handlePinchGesture(scale: gesture.scale, initialScale: initialScale)

            case .changed:
                // Apply continuous updates for smoother zooming experience
                // The continuous timer helps ensure smoother transitions
                parent.cameraModel.handlePinchGesture(scale: gesture.scale)

            case .ended, .cancelled, .failed:
                // Ensure final value is applied when gesture completes
                parent.cameraModel.handlePinchGesture(scale: gesture.scale)

            default:
                break
            }
        }

        // Handle double tap gesture for focus and white balance
        @objc func handleDoubleTapGesture(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            let location = gesture.location(in: view)
            print("Double tap detected at \(location.x), \(location.y)")

            // Get the container view for proper coordinate conversion
            guard let containerView = parent.viewHolder.previewContainer else { return }

            // Check if the tap is within the container bounds
            let locationInContainer = view.convert(location, to: containerView)
            if !containerView.bounds.contains(locationInContainer) {
                print("Tap outside of capture area, ignoring")
                return
            }

            // Convert touch point to camera coordinate
            if let layer = parent.viewHolder.previewLayer {
                // Convert the point from the container's coordinate space to the preview layer's coordinate space
                let pointInPreviewLayer = layer.captureDevicePointConverted(fromLayerPoint: locationInContainer)
                let devicePoint = layer.devicePoint(from: location)
                print("Converted to device coordinates (2x tap): \(devicePoint.x), \(devicePoint.y)")

//                print("Converted to camera coordinates (2x tap): \(pointInPreviewLayer.x), \(pointInPreviewLayer.y)")

                // Lock both focus and white balance
                // We set locked=true to indicate we want to lock white balance too
                parent.cameraModel.adjustCameraSettings(at: pointInPreviewLayer, lockWhiteBalance: true)
                parent.cameraModel.showFocusIndicator(on: location)
            }
        }

        // Handle single tap gesture for quick focus
        @objc func handleSingleTapGesture(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            let location = gesture.location(in: view)
            print("Single tap detected at \(location.x), \(location.y)")

            // Get the container view for proper coordinate conversion
            guard let containerView = parent.viewHolder.previewContainer else { return }

            // Check if the tap is within the container bounds
            let locationInContainer = view.convert(location, to: containerView)
            if !containerView.bounds.contains(locationInContainer) {
                print("👆 Tap outside of capture area, ignoring")
                return
            }

            // Convert touch point to camera coordinate
            if let layer = parent.viewHolder.previewLayer {
                // Convert the point from the container's coordinate space to the preview layer's coordinate space
                let pointInPreviewLayer = layer.captureDevicePointConverted(fromLayerPoint: locationInContainer)
                print("Converted to camera coordinates (1x tap): \(pointInPreviewLayer.x), \(pointInPreviewLayer.y)")

                // Adjust focus and exposure but not white balance
                parent.cameraModel.adjustCameraSettings(at: pointInPreviewLayer, lockWhiteBalance: false)
                parent.cameraModel.showFocusIndicator(on: location)
            }
        }
    }
}

// MARK: - Conversion helpers

extension AVCaptureVideoPreviewLayer {
    func devicePoint(from viewPoint: CGPoint) -> CGPoint {
        captureDevicePointConverted(fromLayerPoint: viewPoint)
    }

    func viewPoint(from devicePoint: CGPoint) -> CGPoint {
        layerPointConverted(fromCaptureDevicePoint: devicePoint)
    }
}
