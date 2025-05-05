//
//  FaceDetector.swift
//  Snap Safe
//
//  Created by Bill Booth on 5/3/25.
//

import UIKit
import Vision

class FaceDetector {
    func detectFaces(in image: UIImage, completion: @escaping ([CGRect]) -> Void) {
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
            let faceRects = observations.map { observation -> CGRect in
                let boundingBox = observation.boundingBox
                
                // Vision coordinates are normalized (0,0 is bottom left)
                // UIKit coordinates have (0,0) at top left
                let x = boundingBox.origin.x * image.size.width
                let height = boundingBox.height * image.size.height
                let y = (1 - boundingBox.origin.y - boundingBox.height) * image.size.height
                let width = boundingBox.width * image.size.width
                
                return CGRect(x: x, y: y, width: width, height: height)
            }
            
            completion(faceRects)
        } catch {
            completion([])
        }
    }
    
//    func blurFaces(in image: UIImage, faceRects: [CGRect]) -> UIImage? {
//        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
//        defer { UIGraphicsEndImageContext() }
//        
//        // Draw the original image
//        image.draw(at: .zero)
//        
//        // Get the current context
//        guard let context = UIGraphicsGetCurrentContext() else {
//            return nil
//        }
//        
//        // Create a blur filter
//        let blurFilter = CIFilter(name: "CIPixellate")
//        blurFilter?.setValue(20.0, forKey: "inputScale") // Adjust pixelation level
//        
//        // Apply blur to each face
//        for faceRect in faceRects {
//            // Create a CIImage from the portion of the original image
//            if let cgImage = image.cgImage?.cropping(to: faceRect),
//               let ciImage = CIImage(cgImage: cgImage) {
//                
//                blurFilter?.setValue(ciImage, forKey: kCIInputImageKey)
//                
//                if let outputImage = blurFilter?.outputImage,
//                   let cgBlurredFace = CIContext().createCGImage(outputImage, from: outputImage.extent) {
//                    
//                    // Draw the blurred face on top of the original image
//                    context.saveGState()
//                    context.clip(to: faceRect)
//                    UIImage(cgImage: cgBlurredFace).draw(in: faceRect)
//                    context.restoreGState()
//                }
//            }
//        }
//        
//        // Get the modified image
//        return UIGraphicsGetImageFromCurrentImageContext()
//    }
}
