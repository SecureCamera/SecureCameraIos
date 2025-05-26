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
        let primaryMode = modes.first ?? .blur

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

            // Apply the appropriate masking effect
            switch primaryMode {
            case .blackout:
                // For blackout, just fill with black
                context.setFillColor(UIColor.black.cgColor)
                context.fill(safeRect)

            case .pixelate:
                // For pixelation, extract the face, pixelate it, and draw it back
                if let faceCGImage = workingImage.cgImage?.cropping(to: safeRect),
                   let faceImage = pixelateImage(UIImage(cgImage: faceCGImage), targetBlockSize: 8)
                {
                    faceImage.draw(in: safeRect)
                }

            case .blur:
                // For blur, apply a CIFilter directly
                if let faceCGImage = workingImage.cgImage?.cropping(to: safeRect),
                   let blurredFace = applyBlur(to: UIImage(cgImage: faceCGImage), radius: 25.0)
                {
                    blurredFace.draw(in: safeRect)
                }

            case .noise:
                // For noise, generate noise directly in the area
                applyNoiseDirectly(to: context, in: safeRect)
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

    // Helper to apply blur without multiple intermediate images
    private func applyBlur(to image: UIImage, radius: Float) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }

        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)

        guard let outputCIImage = filter.outputImage else { return nil }

        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(outputCIImage, from: outputCIImage.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }

    // Apply noise directly to a context
    private func applyNoiseDirectly(to context: CGContext, in rect: CGRect) {
        let width = Int(rect.width)
        let height = Int(rect.height)

        // Define noise density
        let noiseDensity = 0.3

        // Generate noise points directly on the context
        for y in 0 ..< height {
            for x in 0 ..< width {
                var randomByte: UInt8 = 0
                _ = SecRandomCopyBytes(kSecRandomDefault, 1, &randomByte)

                if Double(randomByte) / 255.0 < noiseDensity {
                    let randomColor = randomByte > 127 ? UIColor.black : UIColor.white
                    context.setFillColor(randomColor.cgColor)
                    context.fill(CGRect(x: rect.minX + CGFloat(x), y: rect.minY + CGFloat(y), width: 1, height: 1))
                }
            }
        }
    }

    // Blur faces with default blur mode
    func blurFaces(in image: UIImage, faces: [DetectedFace]) -> UIImage? {
        return maskFaces(in: image, faces: faces, modes: [.blur])
    }

    // MARK: - Face Masking Implementations

    // Blackout a region of the image
    private func blackout(image: UIImage, rect: CGRect) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        defer { UIGraphicsEndImageContext() }

        image.draw(at: .zero)

        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }

        // Fill the rect with black
        context.setFillColor(UIColor.black.cgColor)
        context.fill(rect)

        return UIGraphicsGetImageFromCurrentImageContext()
    }

    // Pixelate a region of the image
    private func pixelate(image: UIImage, rect: CGRect, targetBlockSize: Int = 8, addNoise: Bool = true) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        defer { UIGraphicsEndImageContext() }

        image.draw(at: .zero)

        guard let context = UIGraphicsGetCurrentContext(),
              let cgImage = image.cgImage,
              let croppedCGImage = cgImage.cropping(to: rect)
        else {
            return nil
        }

        // Create a face image
        let faceImage = UIImage(cgImage: croppedCGImage)

        // Step 1: Create a small pixelated version
        let scale = CGFloat(targetBlockSize) / max(rect.width, rect.height)
        let smallSize = CGSize(width: rect.width * scale, height: rect.height * scale)

        UIGraphicsBeginImageContextWithOptions(smallSize, false, 1.0)
        faceImage.draw(in: CGRect(origin: .zero, size: smallSize))
        let smallImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard var smallImage = smallImage else { return nil }

        // Step 2: Optionally add noise to the small image
        if addNoise {
            UIGraphicsBeginImageContextWithOptions(smallSize, false, 1.0)
            smallImage.draw(at: .zero)
            let noiseContext = UIGraphicsGetCurrentContext()!

            // Use SecRandomCopyBytes for cryptographically secure random numbers
            let noiseProbability = 0.25
            var randomBytes = [UInt8](repeating: 0, count: 1)

            for y in 0 ..< Int(smallSize.height) {
                for x in 0 ..< Int(smallSize.width) {
                    // Get random byte for probability check
                    _ = SecRandomCopyBytes(kSecRandomDefault, 1, &randomBytes)
                    let randValue = Float(randomBytes[0]) / 255.0

                    if randValue <= Float(noiseProbability) {
                        // Get another random byte for color determination
                        _ = SecRandomCopyBytes(kSecRandomDefault, 1, &randomBytes)

                        let color = (randomBytes[0] > 127) ? UIColor.black : UIColor.white
                        noiseContext.setFillColor(color.cgColor)
                        noiseContext.fill(CGRect(x: x, y: y, width: 1, height: 1))
                    }
                }
            }

            smallImage = UIGraphicsGetImageFromCurrentImageContext() ?? smallImage
            UIGraphicsEndImageContext()
        }

        // Step 3: Scale back up to original size
        UIGraphicsBeginImageContextWithOptions(rect.size, false, 1.0)
        smallImage.draw(in: CGRect(origin: .zero, size: rect.size))
        let pixelatedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        // Step 4: Draw pixelated image on original
        context.saveGState()
        context.clip(to: rect)
        pixelatedImage?.draw(at: rect.origin)
        context.restoreGState()

        return UIGraphicsGetImageFromCurrentImageContext()
    }

    // Apply a Gaussian blur to a region of the image
    private func blur(image: UIImage, rect: CGRect, radius: Float = 25.0, rounds: Int = 10) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        defer { UIGraphicsEndImageContext() }

        image.draw(at: .zero)

        guard let currentContext = UIGraphicsGetCurrentContext(),
              let cgImage = image.cgImage,
              let croppedCGImage = cgImage.cropping(to: rect)
        else {
            return nil
        }

        // Create a CIImage from the cropped CGImage
        var ciImage = CIImage(cgImage: croppedCGImage)
        let ciContext = CIContext()

        // Create a blur filter
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else {
            return nil
        }

        // Apply blur multiple times for stronger effect
        let safeRadius = min(max(radius, 0), 100) // Clamp radius between 0 and 100

        for _ in 0 ..< max(rounds, 1) {
            blurFilter.setValue(ciImage, forKey: kCIInputImageKey)
            blurFilter.setValue(safeRadius, forKey: kCIInputRadiusKey)

            if let outputImage = blurFilter.outputImage {
                // For subsequent rounds, we use the output as the next input
                ciImage = outputImage
            }
        }

        // Convert back to CGImage
        if let outputCGImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
            // Draw the blurred image onto the original
            currentContext.saveGState()
            currentContext.clip(to: rect)
            UIImage(cgImage: outputCGImage).draw(in: rect)
            currentContext.restoreGState()
        }

        return UIGraphicsGetImageFromCurrentImageContext()
    }

    // Apply random noise to a region of the image
    private func noise(image: UIImage, rect: CGRect) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        defer { UIGraphicsEndImageContext() }

        image.draw(at: .zero)

        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }

        // Fill the area with noise
        context.saveGState()
        context.clip(to: rect)

        let safeRect = coerceRectToImage(rect: rect, image: image)
        let width = Int(safeRect.width)
        let height = Int(safeRect.height)

        // Create a buffer to hold random color data
        var randomData = [UInt8](repeating: 0, count: width * height * 4) // 4 bytes per pixel (RGBA)

        // Fill buffer with random values
        for i in stride(from: 0, to: randomData.count, by: 4) {
            var randomBytes = [UInt8](repeating: 0, count: 4)
            _ = SecRandomCopyBytes(kSecRandomDefault, 4, &randomBytes)

            randomData[i] = randomBytes[0] // R
            randomData[i + 1] = randomBytes[1] // G
            randomData[i + 2] = randomBytes[2] // B
            randomData[i + 3] = 255 // A (full opacity)
        }

        // Create a CGImage from the random data
        if let provider = CGDataProvider(data: Data(randomData) as CFData),
           let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
           let noiseImage = CGImage(
               width: width,
               height: height,
               bitsPerComponent: 8,
               bitsPerPixel: 32,
               bytesPerRow: width * 4,
               space: colorSpace,
               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
               provider: provider,
               decode: nil,
               shouldInterpolate: false,
               intent: .defaultIntent
           )
        {
            context.draw(noiseImage, in: safeRect)
        }

        context.restoreGState()

        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
