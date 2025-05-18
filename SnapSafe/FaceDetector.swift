//
//  FaceDetector.swift
//  Snap Safe
//
//  Created by Bill Booth on 5/3/25.
//

import UIKit
import Vision
import CoreImage
import Accelerate
import Security

// Enum to represent different face masking modes
enum MaskMode {
    case blackout
    case pixelate
    case blur
    case noise
}

// Struct to represent a detected face with selection state
struct DetectedFace: Identifiable {
    let id = UUID()
    let rect: CGRect
    var isSelected: Bool = false
    
    // Scale the rect to match the view's display size
    func scaledRect(originalSize: CGSize, displaySize: CGSize) -> CGRect {
        let scaleX = displaySize.width / originalSize.width
        let scaleY = displaySize.height / originalSize.height
        
        return CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
    }
}

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
                
                return DetectedFace(rect: CGRect(x: x, y: y, width: width, height: height))
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
    
    // Process faces with specified masking modes
    func maskFaces(in image: UIImage, faces: [DetectedFace], modes: [MaskMode]) -> UIImage? {
        // Only process selected faces
        let selectedFaces = faces.filter { $0.isSelected }
        
        if selectedFaces.isEmpty || modes.isEmpty {
            return image
        }
        
        // Create a copy of the image to work with
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        defer { UIGraphicsEndImageContext() }
        
        // Draw the original image
        image.draw(at: .zero)
        guard var workingImage = UIGraphicsGetImageFromCurrentImageContext() else { return nil }
        
        // Apply each selected mask mode to each selected face
        for face in selectedFaces {
            let safeRect = coerceRectToImage(rect: face.rect, image: workingImage)
            
            for mode in modes {
                switch mode {
                case .blackout:
                    workingImage = blackout(image: workingImage, rect: safeRect) ?? workingImage
                case .pixelate:
                    workingImage = pixelate(image: workingImage, rect: safeRect, targetBlockSize: 8, addNoise: true) ?? workingImage
                case .blur:
                    workingImage = blur(image: workingImage, rect: safeRect, radius: 25.0, rounds: 10) ?? workingImage
                case .noise:
                    workingImage = noise(image: workingImage, rect: safeRect) ?? workingImage
                }
            }
        }
        
        return workingImage
    }
    
    // Blur faces with default blur mode
    func blurFaces(in image: UIImage, faces: [DetectedFace]) -> UIImage? {
        return maskFaces(in: image, faces: faces, modes: [.blur ])
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
              let croppedCGImage = cgImage.cropping(to: rect) else {
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
            
            for y in 0..<Int(smallSize.height) {
                for x in 0..<Int(smallSize.width) {
                    // Get random byte for probability check
                    SecRandomCopyBytes(kSecRandomDefault, 1, &randomBytes)
                    let randValue = Float(randomBytes[0]) / 255.0
                    
                    if randValue <= Float(noiseProbability) {
                        // Get another random byte for color determination
                        SecRandomCopyBytes(kSecRandomDefault, 1, &randomBytes)
                        
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
              let croppedCGImage = cgImage.cropping(to: rect) else {
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
        
        for _ in 0..<max(rounds, 1) {
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
            SecRandomCopyBytes(kSecRandomDefault, 4, &randomBytes)
            
            randomData[i] = randomBytes[0]     // R
            randomData[i + 1] = randomBytes[1] // G
            randomData[i + 2] = randomBytes[2] // B
            randomData[i + 3] = 255           // A (full opacity)
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
           ) {
            context.draw(noiseImage, in: safeRect)
        }
        
        context.restoreGState()
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
