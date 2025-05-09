//
//  FaceDetector.swift
//  Snap Safe
//
//  Created by Bill Booth on 5/3/25.
//

import UIKit
import Vision
import CoreImage

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
    
    // Blur selected faces in an image
    func blurFaces(in image: UIImage, faces: [DetectedFace]) -> UIImage? {
        // Only process selected faces
        let selectedFaces = faces.filter { $0.isSelected }
        
        if selectedFaces.isEmpty {
            return image
        }
        
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        defer { UIGraphicsEndImageContext() }
        
        // Draw the original image
        image.draw(at: .zero)
        
        // Get the current context
        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }
        
        // Create a blur filter
        let blurFilter = CIFilter(name: "CIPixellate")
        blurFilter?.setValue(20.0, forKey: "inputScale") // Adjust pixelation level
        
        // Apply blur to each selected face
        for face in selectedFaces {
            // Create a CIImage from the portion of the original image
            if let cgImage = image.cgImage?.cropping(to: face.rect) {
                let ciImage = CIImage(cgImage: cgImage)
                
                blurFilter?.setValue(ciImage, forKey: kCIInputImageKey)
                
                if let outputImage = blurFilter?.outputImage,
                   let cgBlurredFace = CIContext().createCGImage(outputImage, from: outputImage.extent) {
                    
                    // Draw the blurred face on top of the original image
                    context.saveGState()
                    context.clip(to: face.rect)
                    UIImage(cgImage: cgBlurredFace).draw(in: face.rect)
                    context.restoreGState()
                }
            }
        }
        
        // Get the modified image
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
