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


class FaceDetector {
    // Detect faces and return as DetectedFace objects
    func detectFaces(in image: UIImage, completion: @escaping ([DetectedFace]) -> Void) {
        guard let cgImage = image.cgImage else {
            completion([])
            return
        }

        let request = VNDetectFaceRectanglesRequest()
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

                // Use the bounds parameter of our new DetectedFace class
                return DetectedFace(bounds: CGRect(x: x, y: y, width: width, height: height))
            }

            completion(detectedFaces)
        } catch {
            print("Face detection error: \(error.localizedDescription)")
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
                   let faceImage = pixelateImage(UIImage(cgImage: faceCGImage), targetBlockSize: 8)
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

    // Helper method to pixelate an image without creating multiple copies
    private func pixelateImage(_ image: UIImage, targetBlockSize: Int = 8) -> UIImage? {
        let scale = CGFloat(targetBlockSize) / max(image.size.width, image.size.height)
        let smallSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        // Downscale
        UIGraphicsBeginImageContextWithOptions(smallSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        image.draw(in: CGRect(origin: .zero, size: smallSize))
        guard let smallImage = UIGraphicsGetImageFromCurrentImageContext() else { return nil }

        // Upscale
        UIGraphicsBeginImageContextWithOptions(image.size, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        smallImage.draw(in: CGRect(origin: .zero, size: image.size), blendMode: .normal, alpha: 1.0)

        return UIGraphicsGetImageFromCurrentImageContext()
    }


    // Pixelate faces with default pixelate mode
    func pixelateFaces(in image: UIImage, faces: [DetectedFace]) -> UIImage? {
        return maskFaces(in: image, faces: faces, modes: [.pixelate])
    }

}
