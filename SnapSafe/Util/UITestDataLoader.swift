// Development/testing tool — compiled in Debug builds only, never ships.
#if DEBUG
//
//  UITestDataLoader.swift
//  SnapSafe
//
//  Created by Claude on 10/14/25.
//

import UIKit
import CoreLocation

/// Loads test data for UI testing and screenshots
@MainActor
class UITestDataLoader {

    /// Load sample images into the gallery for UI testing
    static func loadSampleImages(repository: SecureImageRepository) async {
        guard UITestingHelper.isUITesting else { return }

        print("Loading sample images for UI testing...")

        // Check if we already have photos (don't reload if gallery already has images)
        let existing = repository.getPhotos()
        if !existing.isEmpty {
            print("Gallery already has \(existing.count) photos, skipping sample data load")
            return
        }

        // Generate and save 5 sample images with different characteristics
        let sampleImages = [
            (image: generateSampleImage(color: .systemBlue, text: "Mountain", size: CGSize(width: 1200, height: 1600)),
             location: CLLocation(latitude: 40.7128, longitude: -74.0060), // New York
             title: "Mountain Vista"),

            (image: generateSampleImage(color: .systemGreen, text: "Forest", size: CGSize(width: 1600, height: 1200)),
             location: CLLocation(latitude: 34.0522, longitude: -118.2437), // Los Angeles
             title: "Forest Path"),

            (image: generateSampleImage(color: .systemOrange, text: "Sunset", size: CGSize(width: 1600, height: 1200)),
             location: CLLocation(latitude: 51.5074, longitude: -0.1278), // London
             title: "Sunset Beach"),

            (image: generateSampleImage(color: .systemPurple, text: "City", size: CGSize(width: 1200, height: 1600)),
             location: CLLocation(latitude: 35.6762, longitude: 139.6503), // Tokyo
             title: "City Lights"),

            (image: generateSampleImage(color: .systemTeal, text: "Ocean", size: CGSize(width: 1600, height: 1600)),
             location: CLLocation(latitude: -33.8688, longitude: 151.2093), // Sydney
             title: "Ocean View")
        ]

        // Save each image with a staggered timestamp for realistic ordering
        let baseDate = Date().addingTimeInterval(-86400 * 5) // Start 5 days ago

        for (index, sample) in sampleImages.enumerated() {
            // Each photo is 1 day newer than the previous
            let timestamp = baseDate.addingTimeInterval(TimeInterval(index) * 86400)

            let capturedImage = CapturedImage(
                sensorBitmap: sample.image,
                timestamp: timestamp,
                rotationDegrees: 0
            )

            do {
                let photoDef = try await repository.saveImage(
                    capturedImage,
                    location: sample.location,
                    applyRotation: false,
                    quality: 0.85
                )
                print("Saved sample image: \(photoDef.photoName) - \(sample.title)")
            } catch {
                print("Failed to save sample image \(sample.title): \(error)")
            }
        }

        print("Finished loading \(sampleImages.count) sample images")
    }

    /// Generate a colored placeholder image with text overlay
    private static func generateSampleImage(color: UIColor, text: String, size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)

        let image = renderer.image { context in
            // Fill background with gradient
            drawGradient(in: context.cgContext, size: size, color: color)

            // Add some decorative elements for visual interest
            addDecorativeShapes(context: context.cgContext, size: size, color: color)

            // Add text overlay
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center

            let font = UIFont.systemFont(ofSize: min(size.width, size.height) / 8, weight: .bold)

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle,
                .strokeColor: UIColor.black.withAlphaComponent(0.3),
                .strokeWidth: -3.0
            ]

            let textRect = CGRect(
                x: 0,
                y: (size.height - font.lineHeight) / 2,
                width: size.width,
                height: font.lineHeight
            )

            text.draw(in: textRect, withAttributes: attributes)
        }

        return image
    }

    /// Draw a gradient for the background
    private static func drawGradient(in context: CGContext, size: CGSize, color: UIColor) {
        let darkColor = color.withAlphaComponent(0.8)
        let lightColor = color.withAlphaComponent(0.4)

        let colors = [darkColor.cgColor, lightColor.cgColor] as CFArray
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0])!

        // Draw diagonal gradient from top-left to bottom-right
        let startPoint = CGPoint(x: 0, y: 0)
        let endPoint = CGPoint(x: size.width, y: size.height)

        context.drawLinearGradient(gradient, start: startPoint, end: endPoint, options: [])
    }

    /// Add decorative shapes to make the image more interesting
    private static func addDecorativeShapes(context: CGContext, size: CGSize, color: UIColor) {
        context.saveGState()

        // Add some semi-transparent circles for visual interest
        let accentColor = color.withAlphaComponent(0.2)
        context.setFillColor(accentColor.cgColor)

        // Large circle in top-right
        let circle1 = CGRect(
            x: size.width * 0.6,
            y: -size.height * 0.1,
            width: size.height * 0.6,
            height: size.height * 0.6
        )
        context.fillEllipse(in: circle1)

        // Medium circle in bottom-left
        let circle2 = CGRect(
            x: -size.width * 0.1,
            y: size.height * 0.5,
            width: size.width * 0.5,
            height: size.width * 0.5
        )
        context.fillEllipse(in: circle2)

        context.restoreGState()
    }
}
#endif
