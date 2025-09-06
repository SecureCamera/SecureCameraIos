//
//  PhotoControlsView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/20/25.
//

import SwiftUI

struct PhotoControlsView: View {
    var onInfo: () -> Void
    var onObfuscate: () -> Void
    var onShare: () -> Void
    var onDelete: () -> Void
    var isZoomed: Bool
    
    var body: some View {
        HStack(spacing: 30) {
            // Info button
            Button(action: onInfo) {
                VStack {
                    Image(systemName: "info.circle")
                        .font(.system(size: 24))
                    Text("Info")
                        .font(.caption)
                }
                .foregroundColor(.blue)
            }
            
            // Obfuscate faces button
            Button(action: onObfuscate) {
                VStack {
                    Image(systemName: "face.dashed")
                        .font(.system(size: 24))
                    Text("Obfuscate")
                        .font(.caption)
                }
                .foregroundColor(.blue)
            }
            
            // Share button
            Button(action: onShare) {
                VStack {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 24))
                    Text("Share")
                        .font(.caption)
                }
                .foregroundColor(.blue)
            }
            
            // Delete button
            Button(action: onDelete) {
                VStack {
                    Image(systemName: "trash")
                        .font(.system(size: 24))
                    Text("Delete")
                        .font(.caption)
                }
                .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color.white.opacity(0.8))
        .cornerRadius(12)
        .padding(.bottom, 20)
        .opacity(isZoomed ? 0 : 1) // Hide controls when zoomed
        .animation(.easeInOut(duration: 0.2), value: isZoomed)
    }
}

struct PhotoControlsView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray
            PhotoControlsView(
                onInfo: {},
                onObfuscate: {},
                onShare: {},
                onDelete: {},
                isZoomed: false
            )
        }
    }
}