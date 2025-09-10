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
    @StateObject private var viewModel: ImageInfoViewModel
    @Environment(\.dismiss) private var dismiss
    
    init(photoDef: PhotoDef) {
        _viewModel = StateObject(wrappedValue: ImageInfoViewModel(photoDef: photoDef))
    }
    
    var body: some View {
        NavigationView {
            if viewModel.isLoading {
                ProgressView("Loading image information...")
                    .navigationTitle("Image Information")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                dismiss()
                            }
                        }
                    }
            } else {
                Form {
                    Section(header: Text("Basic Information")) {
                        HStack {
                            Text("Filename")
                            Spacer()
                            Text(viewModel.filename)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Resolution")
                            Spacer()
                            Text(viewModel.resolution)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("File Size")
                            Spacer()
                            Text(viewModel.fileSize)
                                .foregroundColor(.secondary)
                        }
                    }
                
                    Section(header: Text("Date Information")) {
                        HStack {
                            Text("Date Taken")
                            Spacer()
                            Text(viewModel.dateTaken)
                                .foregroundColor(.secondary)
                        }
                        
                        if viewModel.originalDateString != "Not available" {
                            HStack {
                                Text("Original Date")
                                Spacer()
                                Text(viewModel.originalDateString)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                
                    Section(header: Text("Orientation")) {
                        HStack {
                            Text("Orientation")
                            Spacer()
                            Text(viewModel.orientationString)
                                .foregroundColor(.secondary)
                        }
                    }
                
                    Section(header: Text("Location")) {
                        Text(viewModel.locationString)
                            .foregroundColor(.secondary)
                    }
                
                    Section(header: Text("Camera Information")) {
                        let cameraInfo = viewModel.cameraInfo
                        
                        if cameraInfo.hasData {
                            if cameraInfo.cameraName != "Unknown" {
                                HStack {
                                    Text("Camera")
                                    Spacer()
                                    Text(cameraInfo.cameraName)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if cameraInfo.apertureString != "Unknown" {
                                HStack {
                                    Text("Aperture")
                                    Spacer()
                                    Text(cameraInfo.apertureString)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if cameraInfo.shutterSpeedString != "Unknown" {
                                HStack {
                                    Text("Shutter Speed")
                                    Spacer()
                                    Text(cameraInfo.shutterSpeedString)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if cameraInfo.isoString != "Unknown" {
                                HStack {
                                    Text("ISO")
                                    Spacer()
                                    Text(cameraInfo.isoString)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if cameraInfo.focalLengthString != "Unknown" {
                                HStack {
                                    Text("Focal Length")
                                    Spacer()
                                    Text(cameraInfo.focalLengthString)
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else {
                            Text("No camera information available")
                                .foregroundColor(.secondary)
                        }
                    }
                
                    // Display all raw metadata for debugging
                    if !viewModel.rawMetadata.isEmpty {
                        Section(header: Text("All Metadata")) {
                            DisclosureGroup("Raw Metadata") {
                                ForEach(viewModel.rawMetadata.keys.sorted(), id: \.self) { key in
                                    VStack(alignment: .leading) {
                                        Text(key)
                                            .font(.headline)
                                            .foregroundColor(.blue)
                                        Text("\(String(describing: viewModel.rawMetadata[key]!))")
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
}
