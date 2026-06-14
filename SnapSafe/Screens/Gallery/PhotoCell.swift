//
//  GalleryView.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/6/25.
//

import SwiftUI


// Photo cell view for gallery items
struct PhotoCell: View {
    let photo: PhotoDef
    let isSelected: Bool
    let isSelecting: Bool
    let onTap: () -> Void
    @ObservedObject var galleryViewModel: MixedMediaGalleryViewModel

    // Track whether this cell is visible in the viewport
    @State private var isVisible: Bool = false
    @State private var isDecoy: Bool = false

    // Cell size
    private let cellSize: CGFloat = 100

    private var thumbnail: UIImage? { galleryViewModel.photoThumbnails[photo.photoName] }

    var body: some View {

        ZStack {
            // Photo image that fills the entire cell
            Image(uiImage: thumbnail ?? UIImage())
                .resizable()
                .aspectRatio(contentMode: .fill) // Use .fill to cover the entire cell
                .frame(width: cellSize, height: cellSize)
                .clipped() // Clip any overflow
                .clipShape(.rect(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                )
                // Track appearance/disappearance for memory management
                .onAppear {
                    // This cell is now visible
                    isVisible = true
                }
                .onDisappear {
                    // This cell is no longer visible
                    isVisible = false
                }

            // Selection checkmark overlay (bottom-trailing) — kept identical to
            // VideoCellView so photos and videos show the affordance in the same
            // place, with an empty circle when unselected.
            if isSelecting {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? .blue : .white)
                            .font(.title2)
                            .shadow(radius: 2)
                            .padding(6)
                    }
                }
            }

            // Decoy indicator (bottom-left)
            if isDecoy {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "shield.fill")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(5)
                        Spacer()
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Photo: \(photo.photoName)")
        .accessibilityHint(isSelecting ? "Double-tap to \(isSelected ? "deselect" : "select")" : "Double-tap to open")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
        .accessibilityActivationPoint(.center)
        .onTapGesture(perform: onTap)
        .task(id: photo.photoName) {
            await galleryViewModel.loadThumbnail(for: photo)
            isDecoy = await galleryViewModel.isDecoyPhoto(photo)
        }
    }
}
