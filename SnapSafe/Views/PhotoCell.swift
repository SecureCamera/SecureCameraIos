//
//  PhotoCell.swift
//  SnapSafe
//
//  Created by Bill Booth on 6/10/25.
//

import SwiftUI

// Photo cell view for gallery items
struct PhotoCell: View {
    let photo: SecurePhoto
    let isSelected: Bool
    let isSelecting: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    // Track whether this cell is visible in the viewport
    @State private var isVisible: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Photo image that fills the available space
            Image(uiImage: photo.thumbnail)
                .resizable()
                .aspectRatio(1.0, contentMode: .fill) // Square aspect ratio, fill to avoid gaps
                .clipped()
                .cornerRadius(10)
                .onTapGesture(perform: onTap)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                )
                // Track appearance/disappearance for memory management
                .onAppear {
                    // This cell is now visible
                    isVisible = true
                    photo.isVisible = true
                    MemoryManager.shared.reportThumbnailLoaded()
                }
                .onDisappear {
                    // This cell is no longer visible
                    isVisible = false
                    photo.markAsInvisible()
                    // Let the memory manager know it can clean up if needed
                    MemoryManager.shared.checkMemoryUsage()
                }

            // Selection checkmark when in selection mode and selected
            if isSelecting, isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                    .background(Circle().fill(Color.white))
                    .padding(5)
            }
        }
    }
}
