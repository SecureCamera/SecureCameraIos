//
//  EnhancedPhotoDetailView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/26/25.
//

import SwiftUI

struct EnhancedPhotoDetailView: View {
    @StateObject private var viewModel: EnhancedPhotoDetailViewModel
    @Environment(\.dismiss) private var dismiss
    
    init(allPhotos: [PhotoDef], initialIndex: Int, showFaceDetection: Bool, onDelete: ((PhotoDef) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: EnhancedPhotoDetailViewModel(
            allPhotos: allPhotos,
            initialIndex: initialIndex,
            showFaceDetection: showFaceDetection,
            onDelete: onDelete,
            onDismiss: onDismiss
        ))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background that fades during dismiss
                Color.black
                    .opacity(viewModel.backgroundOpacity)
                    .edgesIgnoringSafeArea(.all)
                
                TabView(selection: $viewModel.currentIndex) {
                    ForEach(Array(viewModel.photoFiles.enumerated()), id: \.offset) { index, photoDef in
                        PhotoDetailView(
                            photo: photoDef,
                            showFaceDetection: viewModel.showFaceDetection,
                            onDelete: { photoDef in
                                viewModel.onDelete?(photoDef)
                            },
                            onDismiss: {}
                        )
                        .tag(index)
                        .scaleEffect(viewModel.photoScaleEffect)
                        .offset(y: viewModel.dragOffset.height)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .onChange(of: viewModel.currentIndex) { _, newIndex in
                    viewModel.handleIndexChange(newIndex: newIndex)
                }
                
                // Photo counter overlay
                VStack {
                    HStack {
                        Spacer()
                        Text(viewModel.currentPhotoDisplayText)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(12)
                            .opacity(viewModel.overlayOpacity)
                        Spacer()
                    }
                    .padding(.top, 50)
                    
                    Spacer()
                }
            }
            .securityManaged()
            .gesture(
                DragGesture()
                    .onChanged { value in
                        viewModel.handleDragChanged(value, geometryHeight: geometry.size.height)
                    }
                    .onEnded { value in
                        viewModel.handleDragEnded(value, geometryHeight: geometry.size.height) {
                            dismiss()
                        }
                    }
            )
        }
        .navigationBarHidden(true)
        .onAppear {
            viewModel.onAppear()
        }
    }
}
