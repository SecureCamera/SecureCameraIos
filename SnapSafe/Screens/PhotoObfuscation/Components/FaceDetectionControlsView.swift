//
//  FaceDetectionControlsView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/20/25.
//

import SwiftUI

struct FaceDetectionControlsView: View {
    var onCancel: () -> Void
    var onAddBox: () -> Void
    var onMask: () -> Void
    var isAddingBox: Bool
    var hasFacesSelected: Bool
    var faceCount: Int
    var selectedCount: Int
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: onCancel) {
                    Label("Cancel", systemImage: "xmark")
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Color.gray)
                        .clipShape(.rect(cornerRadius: 8))
                }
                
                Spacer()
                
                Button(action: onAddBox) {
                    Label("Add Box", systemImage: "plus.rectangle")
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(isAddingBox ? Color.green : Color.blue)
                        .clipShape(.rect(cornerRadius: 8))
                }
                
                Spacer()
                
                Button(action: onMask) {
                    Label("Mask Faces", systemImage: "eye.slash")
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(hasFacesSelected ? Color.blue : Color.gray)
                        .clipShape(.rect(cornerRadius: 8))
                }
                .disabled(!hasFacesSelected)
            }
            .padding(.horizontal)
            
            if isAddingBox {
                Text("Tap anywhere on the image to add a custom box")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.horizontal)
            } else {
                Text("Tap faces to select them for masking. Pinch to resize boxes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            
            if faceCount == 0 {
                Text("No faces detected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(faceCount) faces detected, \(selectedCount) selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 10)
    }
}

struct FaceDetectionControlsView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray
            FaceDetectionControlsView(
                onCancel: {},
                onAddBox: {},
                onMask: {},
                isAddingBox: false,
                hasFacesSelected: true,
                faceCount: 3,
                selectedCount: 1
            )
        }
    }
}