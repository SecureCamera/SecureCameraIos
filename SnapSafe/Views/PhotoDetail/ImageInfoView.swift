//
//  ImageInfoView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/20/25.
//

import CoreGraphics
import ImageIO
import SwiftUI

// View for displaying image metadata
struct ImageInfoView: View {
    let photo: SecurePhoto
    @Environment(\.dismiss) private var dismiss

    // Helper function to format bytes to readable size
    private func formatFileSize(bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    // Helper to format date
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    // Helper to interpret orientation
    private func orientationString(from value: Int) -> String {
        switch value {
        case 1: "Normal"
        case 3: "Rotated 180°"
        case 6: "Rotated 90° CW"
        case 8: "Rotated 90° CCW"
        default: "Unknown (\(value))"
        }
    }

    // Extract location data from EXIF
    private func locationString(from metadata: [String: Any]) -> String {
        if let gpsData = metadata[String(kCGImagePropertyGPSDictionary)] as? [String: Any] {
            var locationParts: [String] = []

            // Extract latitude
            if let latitudeRef = gpsData[String(kCGImagePropertyGPSLatitudeRef)] as? String,
               let latitude = gpsData[String(kCGImagePropertyGPSLatitude)] as? Double
            {
                let latDirection = latitudeRef == "N" ? "N" : "S"
                locationParts.append(String(format: "%.6f°%@", latitude, latDirection))
            }

            // Extract longitude
            if let longitudeRef = gpsData[String(kCGImagePropertyGPSLongitudeRef)] as? String,
               let longitude = gpsData[String(kCGImagePropertyGPSLongitude)] as? Double
            {
                let longDirection = longitudeRef == "E" ? "E" : "W"
                locationParts.append(String(format: "%.6f°%@", longitude, longDirection))
            }

            // Include altitude if available
            if let altitude = gpsData[String(kCGImagePropertyGPSAltitude)] as? Double {
                locationParts.append(String(format: "Alt: %.1fm", altitude))
            }

            return locationParts.isEmpty ? "Not available" : locationParts.joined(separator: ", ")
        }

        return "Not available"
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Basic Information")) {
                    HStack {
                        Text("ID")
                        Spacer()
                        Text(photo.id)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Resolution")
                        Spacer()
                        Text("\(Int(photo.fullImage.size.width)) × \(Int(photo.fullImage.size.height))")
                            .foregroundColor(.secondary)
                    }

                    if let imageData = photo.fullImage.jpegData(compressionQuality: 1.0) {
                        HStack {
                            Text("File Size")
                            Spacer()
                            Text(formatFileSize(bytes: imageData.count))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("Date Information")) {
                    HStack {
                        Text("Date Taken")
                        Spacer()
                        Text(formatDate(photo.metadata.creationDate))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Date Modified")
                        Spacer()
                        Text(formatDate(photo.metadata.modificationDate))
                            .foregroundColor(.secondary)
                    }
                    // TODO: Add EXIF data support to PhotoMetadata if needed
                }

                Section(header: Text("Photo Details")) {
                    HStack {
                        Text("File Size")
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: Int64(photo.metadata.fileSize), countStyle: .file))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Faces Detected")
                        Spacer()
                        Text("\(photo.metadata.faces.count)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Mask Mode")
                        Spacer()
                        Text(photo.metadata.maskMode.displayName)
                            .foregroundColor(.secondary)
                    }
                }
                // TODO: Add camera information section when EXIF support is added to PhotoMetadata
            }
            .navigationTitle("Image Information")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
