//
//  GalleryView.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/6/25.
//

import SwiftUI
import FactoryKit


// Photo cell view for gallery items
struct PhotoCell: View {
    let photo: PhotoDef
    let isSelected: Bool
    let isSelecting: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    @Injected(\.secureImageRepository)
    private var secureImageRepository: SecureImageRepository
    
    // Track whether this cell is visible in the viewport
    @State private var isVisible: Bool = false
    @State private var thumbnail: UIImage? = nil
    @State private var isDecoy: Bool = false
    
    // Cell size
    private let cellSize: CGFloat = 100
    
    var body: some View {
        
        ZStack {
            // Photo image that fills the entire cell
            Image(uiImage: thumbnail ?? UIImage())
                .resizable()
                .aspectRatio(contentMode: .fill) // Use .fill to cover the entire cell
                .frame(width: cellSize, height: cellSize)
                .clipped() // Clip any overflow
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
                }
                .onDisappear {
                    // This cell is no longer visible
                    isVisible = false
                }

            // Selection checkmark when in selection mode and selected (top-right)
            if isSelecting && isSelected {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                            .background(Circle().fill(Color.white))
                            .padding(5)
                    }
                    Spacer()
                }
            }
            
            // Decoy indicator (bottom-left)
            if isDecoy {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "shield.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.75))
                            .padding(5)
                        Spacer()
                    }
                }
            }
        }.task {
            thumbnail = await self.secureImageRepository.readThumbnail(photo)
            isDecoy = secureImageRepository.isDecoyPhoto(photo)
        }
    }
}
