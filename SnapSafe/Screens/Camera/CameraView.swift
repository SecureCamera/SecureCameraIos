//
//  CameraView.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/6/25.
//

@preconcurrency import AVFoundation
import CoreGraphics
import ImageIO
import PhotosUI
import SwiftUI
import FactoryKit
import Logging


// SwiftUI wrapper for the camera preview
struct CameraView: View {
    @ObservedObject var cameraModel: CameraViewModel
    var onPinchStarted: (() -> Void)?
    var onPinchChanged: (() -> Void)?
    var onPinchEnded: (() -> Void)?

    // Add a slightly darker background to emphasize the capture area
    let backgroundOpacity: Double = 0.2

    @State private var showBlackOverlay = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background color to emphasize the capture area
                Color.black
                    .edgesIgnoringSafeArea(.all)

                if cameraModel.isPermissionGranted {
                    // Camera preview represented by UIViewRepresentable
                    CameraPreviewView(cameraModel: cameraModel, viewSize: geometry.size, onPinchStarted: onPinchStarted, onPinchChanged: onPinchChanged, onPinchEnded: onPinchEnded)
                        .edgesIgnoringSafeArea(.all)

                    // Black overlay when returning from background
                    if showBlackOverlay {
                        Color.black
                            .edgesIgnoringSafeArea(.all)
                            .transition(.opacity)
                    }

                    // Focus indicator overlay with proper coordinates
                    if cameraModel.showingFocusIndicator, let point = cameraModel.focusIndicatorPoint {
                        FocusIndicatorView()
                            .position(x: point.x, y: point.y)
                            .transition(.scale.combined(with: .opacity))
                            .animation(.easeInOut(duration: 0.2), value: cameraModel.showingFocusIndicator)
                    }
                } else {
                    // Camera permission denied message
                    VStack(spacing: 20) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Text("Camera Access Disabled")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        Text("Camera access is required to take photos. Please enable camera access in Settings.")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        Button(action: {
                            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(settingsUrl)
                            }
                        }) {
                            HStack {
                                Image(systemName: "gear")
                                Text("Open Settings")
                            }
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .cornerRadius(8)
                        }
                    }
                }
            }
            .onAppear {
                // Re-check camera permissions when camera view appears
                Task {
                    await cameraModel.checkAndSetupCamera()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                withAnimation {
                    showBlackOverlay = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                // Keep black overlay for a brief moment, then fade out
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    withAnimation(.easeOut(duration: 0.3)) {
                        showBlackOverlay = false
                    }
                }
            }
        }
    }
}

// Focus square indicator
struct FocusIndicatorView: View {
    // Animation state
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Outer square with animation
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.yellow, lineWidth: 2)
                .frame(width: isAnimating ? 70 : 80, height: isAnimating ? 70 : 80)
                .animation(Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isAnimating)

            // Inner square
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: 50, height: 50)

            // Center crosshair
            ZStack {
                // Horizontal line
                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: 20, height: 1)

                // Vertical line
                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: 1, height: 20)
            }
        }
        .shadow(color: Color.black.opacity(0.5), radius: 2, x: 1, y: 1)
        .onAppear {
            isAnimating = true
        }
    }
}

// Persistent camera preview state; lives on the Coordinator so it survives struct re-renders
class CameraPreviewHolder {
    weak var view: UIView?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var previewContainer: UIView?
}

// UIViewRepresentable for camera preview
struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraModel: CameraViewModel
    var viewSize: CGSize // Store the parent view's size for coordinate conversion
    var onPinchStarted: (() -> Void)?
    var onPinchChanged: (() -> Void)?
    var onPinchEnded: (() -> Void)?

    // Standard photo aspect ratio is 4:3
    // This is the ratio of most iPhone photos in portrait mode (3:4 actually, as width:height)
    private let photoAspectRatio: CGFloat = 3.0 / 4.0 // width/height in portrait mode

    func makeUIView(context: Context) -> UIView {
        let holder = context.coordinator.viewHolder

        // Create a view with the exact size passed from parent
        let view = UIView(frame: CGRect(origin: .zero, size: viewSize))
        Logger.camera.debug("Creating camera preview", metadata: [
            "width": .stringConvertible(viewSize.width),
            "height": .stringConvertible(viewSize.height)
        ])

        // Store the view reference
        holder.view = view

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
        holder.previewContainer = containerView
        
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
        holder.previewLayer = previewLayer

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
        Task { @MainActor in
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
    
    func updateUIView(_ uiView: UIView, context: Context) {
        let holder = context.coordinator.viewHolder
        uiView.frame = CGRect(origin: .zero, size: viewSize)

        let containerSize = calculatePreviewContainerSize(for: viewSize)
        let containerOrigin = CGPoint(
            x: (viewSize.width - containerSize.width) / 2,
            y: (viewSize.height - containerSize.height) / 2
        )

        if let containerView = holder.previewContainer {
            containerView.frame = CGRect(origin: containerOrigin, size: containerSize)

            if let layer = holder.previewLayer {
                layer.frame = containerView.bounds
                if cameraModel.preview !== layer {
                    cameraModel.preview = layer
                }
            }

            if containerView.layer.sublayers?.count ?? 0 > 0 {
                if let borderLayer = containerView.layer.sublayers?.first(where: { $0.borderWidth > 0 }) {
                    borderLayer.frame = containerView.bounds
                }

                let cornerSize: CGFloat = 20.0
                let cornerThickness: CGFloat = 3.0

                for layer in containerView.layer.sublayers ?? [] {
                    if layer.borderWidth > 0 { continue }
                    if layer.frame.origin.x == 0 && layer.frame.origin.y == 0 {
                        if layer.frame.height == cornerThickness {
                            layer.frame = CGRect(x: 0, y: 0, width: cornerSize, height: cornerThickness)
                        } else if layer.frame.width == cornerThickness {
                            layer.frame = CGRect(x: 0, y: 0, width: cornerThickness, height: cornerSize)
                        }
                    } else if layer.frame.origin.y == 0 && layer.frame.origin.x > 0 {
                        if layer.frame.height == cornerThickness {
                            layer.frame = CGRect(x: containerSize.width - cornerSize, y: 0, width: cornerSize, height: cornerThickness)
                        } else if layer.frame.width == cornerThickness {
                            layer.frame = CGRect(x: containerSize.width - cornerThickness, y: 0, width: cornerThickness, height: cornerSize)
                        }
                    } else if layer.frame.origin.x == 0 && layer.frame.origin.y > 0 {
                        if layer.frame.height == cornerThickness {
                            layer.frame = CGRect(x: 0, y: containerSize.height - cornerThickness, width: cornerSize, height: cornerThickness)
                        } else if layer.frame.width == cornerThickness {
                            layer.frame = CGRect(x: 0, y: containerSize.height - cornerSize, width: cornerThickness, height: cornerSize)
                        }
                    } else if layer.frame.origin.x > 0 && layer.frame.origin.y > 0 {
                        if layer.frame.height == cornerThickness {
                            layer.frame = CGRect(x: containerSize.width - cornerSize, y: containerSize.height - cornerThickness, width: cornerSize, height: cornerThickness)
                        } else if layer.frame.width == cornerThickness {
                            layer.frame = CGRect(x: containerSize.width - cornerThickness, y: containerSize.height - cornerSize, width: cornerThickness, height: cornerSize)
                        }
                    }
                }

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

        if cameraModel.viewSize != containerSize {
            cameraModel.viewSize = containerSize
        }
    }
    
    // This method is called once after makeUIView
    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(self)

        let capturedCameraModel = cameraModel
        Task(priority: .userInitiated) {
            try await Task.sleep(for: .milliseconds(500))
            let session = capturedCameraModel.session
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                coordinator.sessionQueue.async {
                    if !session.isRunning {
                        Logger.camera.debug("Starting camera session off-main after delay")
                        session.startRunning()
                    }
                    cont.resume()
                }
            }
        }

        return coordinator
    }

    // Coordinator for handling UIKit gestures
    @MainActor
    class Coordinator: NSObject {
        var parent: CameraPreviewView
        private var initialScale: CGFloat = 1.0

        // Persistent state across re-renders (struct properties are recreated each render)
        let sessionQueue = DispatchQueue(label: "camera.session.queue")
        let viewHolder = CameraPreviewHolder()

        init(_ parent: CameraPreviewView) {
            self.parent = parent
        }

        // Handle pinch gesture for zoom with continuous updates
        @objc func handlePinchGesture(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                // Store initial scale when gesture begins
                initialScale = gesture.scale
                parent.onPinchStarted?()
                parent.cameraModel.handlePinchGesture(scale: gesture.scale, initialScale: initialScale)

            case .changed:
                // Apply continuous updates for smoother zooming experience
                // The continuous timer helps ensure smoother transitions
                parent.onPinchChanged?()
                parent.cameraModel.handlePinchGesture(scale: gesture.scale)

            case .ended, .cancelled, .failed:
                // Ensure final value is applied when gesture completes
                parent.cameraModel.handlePinchGesture(scale: gesture.scale)
                parent.onPinchEnded?()

            default:
                break
            }
        }

        // Handle double tap gesture for focus and white balance
        @objc func handleDoubleTapGesture(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            let location = gesture.location(in: view)
            Logger.camera.debug("Double tap detected", metadata: [
                "x": .stringConvertible(location.x),
                "y": .stringConvertible(location.y)
            ])
            
            // Get the container view for proper coordinate conversion
            guard let containerView = viewHolder.previewContainer else { return }
            
            // Check if the tap is within the container bounds
            let locationInContainer = view.convert(location, to: containerView)
            if !containerView.bounds.contains(locationInContainer) {
                Logger.camera.debug("Tap outside of capture area, ignoring")
                return
            }
            

            // Convert touch point to camera coordinate
            if let layer = viewHolder.previewLayer {
                // Convert the point from the container's coordinate space to the preview layer's coordinate space
                let pointInPreviewLayer = layer.captureDevicePointConverted(fromLayerPoint: locationInContainer)
                let devicePoint = layer.devicePoint(from: location)
                Logger.camera.debug("Converted to device coordinates (2x tap)", metadata: [
                    "x": .stringConvertible(devicePoint.x),
                    "y": .stringConvertible(devicePoint.y)
                ])
                

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
            Logger.camera.debug("Single tap detected", metadata: [
                "x": .stringConvertible(location.x),
                "y": .stringConvertible(location.y)
            ])
            
            // Get the container view for proper coordinate conversion
            guard let containerView = viewHolder.previewContainer else { return }
            
            // Check if the tap is within the container bounds
            let locationInContainer = view.convert(location, to: containerView)
            if !containerView.bounds.contains(locationInContainer) {
                Logger.camera.debug("Tap outside of capture area, ignoring")
                return
            }

            // Convert touch point to camera coordinate
            if let layer = viewHolder.previewLayer {
                // Convert the point from the container's coordinate space to the preview layer's coordinate space
                let pointInPreviewLayer = layer.captureDevicePointConverted(fromLayerPoint: locationInContainer)
                Logger.camera.debug("Converted to camera coordinates (1x tap)", metadata: [
                    "x": .stringConvertible(pointInPreviewLayer.x),
                    "y": .stringConvertible(pointInPreviewLayer.y)
                ])

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
        return self.captureDevicePointConverted(fromLayerPoint: viewPoint)
    }

    func viewPoint(from devicePoint: CGPoint) -> CGPoint {
        return self.layerPointConverted(fromCaptureDevicePoint: devicePoint)
    }
}
