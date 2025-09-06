//
//  ImageInfoView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/20/25.
//

import SwiftUI
import CoreGraphics
import ImageIO

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
        case 1: return "Normal"
        case 3: return "Rotated 180°"
        case 6: return "Rotated 90° CW"
        case 8: return "Rotated 90° CCW"
        default: return "Unknown (\(value))"
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
                        Text("Filename")
                        Spacer()
                        Text(photo.filename)
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
                    if let creationDate = photo.metadata["creationDate"] as? Double {
                        HStack {
                            Text("Date Taken")
                            Spacer()
                            Text(formatDate(Date(timeIntervalSince1970: creationDate)))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("No date information available")
                            .foregroundColor(.secondary)
                    }
                    
                    if let exifDict = photo.metadata[String(kCGImagePropertyExifDictionary)] as? [String: Any],
                       let dateTimeOriginal = exifDict[String(kCGImagePropertyExifDateTimeOriginal)] as? String
                    {
                        HStack {
                            Text("Original Date")
                            Spacer()
                            Text(dateTimeOriginal)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section(header: Text("Orientation")) {
                    if let tiffDict = photo.metadata[String(kCGImagePropertyTIFFDictionary)] as? [String: Any],
                       let orientation = tiffDict[String(kCGImagePropertyTIFFOrientation)] as? Int
                    {
                        HStack {
                            Text("Orientation")
                            Spacer()
                            Text(orientationString(from: orientation))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Normal")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Location")) {
                    Text(locationString(from: photo.metadata))
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Camera Information")) {
                    if let exifDict = photo.metadata[String(kCGImagePropertyExifDictionary)] as? [String: Any] {
                        if let make = (photo.metadata[String(kCGImagePropertyTIFFDictionary)] as? [String: Any])?[String(kCGImagePropertyTIFFMake)] as? String,
                           let model = (photo.metadata[String(kCGImagePropertyTIFFDictionary)] as? [String: Any])?[String(kCGImagePropertyTIFFModel)] as? String
                        {
                            HStack {
                                Text("Camera")
                                Spacer()
                                Text("\(make) \(model)")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if let fNumber = exifDict[String(kCGImagePropertyExifFNumber)] as? Double {
                            HStack {
                                Text("Aperture")
                                Spacer()
                                Text(String(format: "f/%.1f", fNumber))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if let exposureTime = exifDict[String(kCGImagePropertyExifExposureTime)] as? Double {
                            HStack {
                                Text("Shutter Speed")
                                Spacer()
                                Text("\(exposureTime < 1 ? "1/\(Int(1 / exposureTime))" : String(format: "%.1f", exposureTime))s")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if let isoValue = exifDict[String(kCGImagePropertyExifISOSpeedRatings)] as? [Int],
                           let iso = isoValue.first
                        {
                            HStack {
                                Text("ISO")
                                Spacer()
                                Text("\(iso)")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if let focalLength = exifDict[String(kCGImagePropertyExifFocalLength)] as? Double {
                            HStack {
                                Text("Focal Length")
                                Spacer()
                                Text("\(Int(focalLength))mm")
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("No camera information available")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Display all raw metadata for debugging
                if photo.metadata.count > 0 {
                    Section(header: Text("All Metadata")) {
                        DisclosureGroup("Raw Metadata") {
                            ForEach(photo.metadata.keys.sorted(), id: \.self) { key in
                                VStack(alignment: .leading) {
                                    Text(key)
                                        .font(.headline)
                                        .foregroundColor(.blue)
                                    Text("\(String(describing: photo.metadata[key]!))")
                                        .font(.caption)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
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