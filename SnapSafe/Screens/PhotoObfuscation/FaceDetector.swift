//
//  FaceDetector.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/3/25.
//

import Accelerate
import CoreImage
import Security
import UIKit
import Vision
import Logging


class FaceDetector {
    // Detect faces and return as DetectedFace objects
    func detectFaces(in image: UIImage, completion: @escaping ([DetectedFace]) -> Void) {
        guard let cgImage = image.cgImage else {
            completion([])
            return
        }

        // Use VNDetectFaceLandmarksRequest to get both face bounds and eye positions
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])

            guard let observations = request.results else {
                completion([])
                return
            }

            // Convert normalized coordinates to image coordinates
            let detectedFaces = observations.map { observation -> DetectedFace in
                let boundingBox = observation.boundingBox

                // Vision coordinates are normalized (0,0 is bottom left)
                // UIKit coordinates have (0,0) at top left
                let x = boundingBox.origin.x * image.size.width
                let height = boundingBox.height * image.size.height
                let y = (1 - boundingBox.origin.y - boundingBox.height) * image.size.height
                let width = boundingBox.width * image.size.width

                // Extract eye positions if available
                var leftEye: CGPoint?
                var rightEye: CGPoint?

                if let landmarks = observation.landmarks {
                    // Get left eye position (from the perspective of the face, not the viewer)
                    if let leftEyePoints = landmarks.leftEye?.normalizedPoints, !leftEyePoints.isEmpty {
                        // Calculate centroid of left eye points
                        let avgX = leftEyePoints.map { $0.x }.reduce(0, +) / CGFloat(leftEyePoints.count)
                        let avgY = leftEyePoints.map { $0.y }.reduce(0, +) / CGFloat(leftEyePoints.count)

                        // Convert to image coordinates
                        leftEye = CGPoint(
                            x: boundingBox.origin.x * image.size.width + avgX * width,
                            y: (1 - boundingBox.origin.y - avgY * boundingBox.height) * image.size.height
                        )
                    }

                    // Get right eye position (from the perspective of the face, not the viewer)
                    if let rightEyePoints = landmarks.rightEye?.normalizedPoints, !rightEyePoints.isEmpty {
                        // Calculate centroid of right eye points
                        let avgX = rightEyePoints.map { $0.x }.reduce(0, +) / CGFloat(rightEyePoints.count)
                        let avgY = rightEyePoints.map { $0.y }.reduce(0, +) / CGFloat(rightEyePoints.count)

                        // Convert to image coordinates
                        rightEye = CGPoint(
                            x: boundingBox.origin.x * image.size.width + avgX * width,
                            y: (1 - boundingBox.origin.y - avgY * boundingBox.height) * image.size.height
                        )
                    }
                }

                return DetectedFace(bounds: CGRect(x: x, y: y, width: width, height: height), isSelected: true, leftEye: leftEye, rightEye: rightEye)
            }

            completion(detectedFaces)
        } catch {
            Logger.app.error("Face detection error: \(error.localizedDescription)")
            completion([])
        }
    }

    // Helper function to ensure a rect is within the bounds of a UIImage
    private func coerceRectToImage(rect: CGRect, image: UIImage) -> CGRect {
        let imageWidth = image.size.width
        let imageHeight = image.size.height

        // For completely outside image cases, create a small valid rect at the edge
        if rect.minX >= imageWidth || rect.maxX <= 0 || rect.minY >= imageHeight || rect.maxY <= 0 {
            let left = max(imageWidth - 1, 0)
            let top = max(imageHeight - 1, 0)
            return CGRect(x: left, y: top, width: 1, height: 1)
        }

        // For normal cases, constrain the coordinates
        let left = max(min(rect.minX, imageWidth - 1), 0)
        let top = max(min(rect.minY, imageHeight - 1), 0)

        // Ensure minimum width of 1
        var right = max(min(rect.maxX, imageWidth), left + 1)
        if right <= left { right = left + 1 }

        // Ensure minimum height of 1
        var bottom = max(min(rect.maxY, imageHeight), top + 1)
        if bottom <= top { bottom = top + 1 }

        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    // Process faces with specified masking modes with memory optimizations
    func maskFaces(in image: UIImage, faces: [DetectedFace], modes: [MaskMode]) -> UIImage? {
        // Only process selected faces
        let selectedFaces = faces.filter { $0.isSelected }

        if selectedFaces.isEmpty || modes.isEmpty {
            return image
        }

        // Get the primary masking mode (using only one to avoid creating multiple image copies)
        let primaryMode = modes.first ?? .pixelate

        // Create a context with the image size (reused for all operations)
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        defer { UIGraphicsEndImageContext() }

        // Draw the original image
        image.draw(at: .zero)
        guard let workingImage = UIGraphicsGetImageFromCurrentImageContext() else { return nil }

        // Get the current graphics context
        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        // Apply the selected mask mode to all selected faces
        // Instead of creating a new image for each face, we'll update the same context
        for face in selectedFaces {
            let safeRect = coerceRectToImage(rect: face.bounds, image: workingImage)

            // Save the graphics state before modifications
            context.saveGState()

            // Clip to the face rectangle to limit the effect
            context.clip(to: safeRect)

            // Clear the face area
            context.clear(safeRect)

            // Apply pixelation effect
            switch primaryMode {
            case .pixelate:
                // For pixelation, extract the face, pixelate it, and draw it back
                if let faceCGImage = workingImage.cgImage?.cropping(to: safeRect),
                   let faceImage = pixelateImage(UIImage(cgImage: faceCGImage), face: face, targetBlockSize: 8)
                {
                    faceImage.draw(in: safeRect)
                }
            }

            // Restore the graphics state
            context.restoreGState()
        }

        // Get the final image from the context
        let finalImage = UIGraphicsGetImageFromCurrentImageContext()
        return finalImage
    }

    // Enhanced pixelate method following the specific algorithm:
    // 1. Scale down to 8x8
    // 2. Add noise (25% probability of black/white pixels)
    // 3. Draw eye blackout line if eyes are detected
    // 4. Scale back up to original size
    private func pixelateImage(_ image: UIImage, face: DetectedFace, targetBlockSize: Int = 8) -> UIImage? {
        // Step 1: Scale down to 8x8
        let smallSize = CGSize(width: targetBlockSize, height: targetBlockSize)

        UIGraphicsBeginImageContextWithOptions(smallSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        // Draw the image scaled down
        image.draw(in: CGRect(origin: .zero, size: smallSize))
        guard let smallImage = UIGraphicsGetImageFromCurrentImageContext() else { return nil }

        // Step 2: Add noise - create a new context to modify the small image
        UIGraphicsBeginImageContextWithOptions(smallSize, false, 1.0)
        guard let noiseContext = UIGraphicsGetCurrentContext() else { return nil }
        defer { UIGraphicsEndImageContext() }

        // Draw the scaled down image first
        smallImage.draw(at: .zero)

        // Add random noise (50% probability)
        let noiseProbability: Float = 0.50

        for y in 0..<targetBlockSize {
            for x in 0..<targetBlockSize {
                if Float.random(in: 0...1) <= noiseProbability {
                    let color = Bool.random() ? UIColor.black : UIColor.white
                    color.setFill()
                    noiseContext.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }

        // Step 3: Draw eye blackout line if eyes are detected
        if let leftEye = face.leftEye, let rightEye = face.rightEye {
            // Convert eye positions from original face coordinates to 8x8 coordinates
            let faceRect = face.bounds
            let leftEyeInFace = CGPoint(
                x: leftEye.x - faceRect.origin.x,
                y: leftEye.y - faceRect.origin.y
            )
            let rightEyeInFace = CGPoint(
                x: rightEye.x - faceRect.origin.x,
                y: rightEye.y - faceRect.origin.y
            )

            let leftEyeInSmall = CGPoint(
                x: leftEyeInFace.x * CGFloat(targetBlockSize) / faceRect.width,
                y: leftEyeInFace.y * CGFloat(targetBlockSize) / faceRect.height
            )
            let rightEyeInSmall = CGPoint(
                x: rightEyeInFace.x * CGFloat(targetBlockSize) / faceRect.width,
                y: rightEyeInFace.y * CGFloat(targetBlockSize) / faceRect.height
            )

            // Draw black line from edge to edge at eye level
            UIColor.black.setStroke()
            noiseContext.setLineWidth(1.0)

            if leftEyeInSmall.x >= 0 && leftEyeInSmall.x < CGFloat(targetBlockSize) &&
               leftEyeInSmall.y >= 0 && leftEyeInSmall.y < CGFloat(targetBlockSize) &&
               rightEyeInSmall.x >= 0 && rightEyeInSmall.x < CGFloat(targetBlockSize) &&
               rightEyeInSmall.y >= 0 && rightEyeInSmall.y < CGFloat(targetBlockSize) {
                // Draw line from left edge to right edge at the eye level
                noiseContext.move(to: CGPoint(x: 0, y: leftEyeInSmall.y))
                noiseContext.addLine(to: CGPoint(x: CGFloat(targetBlockSize - 1), y: rightEyeInSmall.y))
                noiseContext.strokePath()
            } else {
                // If both eyes aren't in bounds, draw individual points
                if leftEyeInSmall.x >= 0 && leftEyeInSmall.x < CGFloat(targetBlockSize) &&
                   leftEyeInSmall.y >= 0 && leftEyeInSmall.y < CGFloat(targetBlockSize) {
                    UIColor.black.setFill()
                    noiseContext.fill(CGRect(x: Int(leftEyeInSmall.x), y: Int(leftEyeInSmall.y), width: 1, height: 1))
                }

                if rightEyeInSmall.x >= 0 && rightEyeInSmall.x < CGFloat(targetBlockSize) &&
                   rightEyeInSmall.y >= 0 && rightEyeInSmall.y < CGFloat(targetBlockSize) {
                    UIColor.black.setFill()
                    noiseContext.fill(CGRect(x: Int(rightEyeInSmall.x), y: Int(rightEyeInSmall.y), width: 1, height: 1))
                }
            }
        }

        guard let noisySmallImage = UIGraphicsGetImageFromCurrentImageContext() else { return nil }

        // Step 4: Scale back up to original size
        UIGraphicsBeginImageContextWithOptions(image.size, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        noisySmallImage.draw(in: CGRect(origin: .zero, size: image.size))

        return UIGraphicsGetImageFromCurrentImageContext()
    }

}
