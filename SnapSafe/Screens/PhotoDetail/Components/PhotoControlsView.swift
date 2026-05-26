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
    var onToggleDecoy: (() -> Void)?
    var isZoomed: Bool
    var showDecoyButton: Bool
    var decoyButtonTitle: String
    var decoyButtonIcon: String
    var isDecoyOperationLoading: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Separator line
            Divider()
                .background(Color.gray.opacity(0.3))

            HStack {
                // Delete button
                Button(action: onDelete) {
                    VStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.title3)
                            .frame(height: 22)
                        Text("Delete")
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                }
                
                // Info button
                Button(action: onInfo) {
                    VStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.title3)
                            .frame(height: 22)
                        Text("Info")
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                }

                // Obfuscate faces button
                Button(action: onObfuscate) {
                    VStack(spacing: 4) {
                        Image(systemName: "face.dashed")
                            .font(.title3)
                            .frame(height: 22)
                        Text("Obfuscate")
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                }

                // Decoy button (conditional)
                if showDecoyButton {
                    Button(action: {
                        onToggleDecoy?()
                    }) {
                        VStack(spacing: 4) {
                            if isDecoyOperationLoading {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(height: 22)
                            } else {
                                Image(systemName: decoyButtonIcon)
                                    .font(.title3)
                                    .frame(height: 22)
                            }
                            Text(decoyButtonTitle)
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    }
                    .disabled(isDecoyOperationLoading)
                    .opacity(isDecoyOperationLoading ? 0.6 : 1.0)
                }

                // Share button
                Button(action: onShare) {
                    VStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3)
                            .frame(height: 22)
                        Text("Share")
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                }


            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(UIColor.systemBackground))
        }
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
                onToggleDecoy: {},
                isZoomed: false,
                showDecoyButton: true,
                decoyButtonTitle: "Add Decoy",
                decoyButtonIcon: "shield",
                isDecoyOperationLoading: false
            )
        }
    }
}
