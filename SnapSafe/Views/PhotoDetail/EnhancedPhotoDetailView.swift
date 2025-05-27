//
//  EnhancedPhotoDetailView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/26/25.
//

import SwiftUI

struct EnhancedPhotoDetailView: View {
    let allPhotos: [SecurePhoto]
    @State private var currentIndex: Int
    let showFaceDetection: Bool
    let onDelete: ((SecurePhoto) -> Void)?
    let onDismiss: (() -> Void)?
    
    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset: CGSize = .zero
    @State private var dismissProgress: CGFloat = 0
    @State private var isTabViewTransitioning: Bool = false
    @State private var lastIndexChangeTime: Date = Date()
    
    init(allPhotos: [SecurePhoto], initialIndex: Int, showFaceDetection: Bool, onDelete: ((SecurePhoto) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.allPhotos = allPhotos
        self._currentIndex = State(initialValue: initialIndex)
        self.showFaceDetection = showFaceDetection
        self.onDelete = onDelete
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background that fades during dismiss
                Color.black
                    .opacity(1.0 - dismissProgress * 0.8)
                    .edgesIgnoringSafeArea(.all)
                
                TabView(selection: $currentIndex) {
                    ForEach(Array(allPhotos.enumerated()), id: \.element.id) { index, photo in
                        PhotoDetailView_Impl(
                            photo: photo,
                            showFaceDetection: showFaceDetection,
                            onDelete: onDelete,
                            onDismiss: {}
                        )
                        .tag(index)
                        .scaleEffect(1.0 - dismissProgress * 0.2)
                        .offset(y: dragOffset.height)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
//                .onChange(of: currentIndex) { _, newIndex in
//                    print("🟣 EnhancedPhotoDetailView: TabView currentIndex changed from \(currentIndex) to \(newIndex)")
//                    // Track when TabView transitions occur
//                    isTabViewTransitioning = true
//                    lastIndexChangeTime = Date()
//                    
//                    // Reset any dismiss progress during navigation
//                    withAnimation(.easeOut(duration: 0.2)) {
//                        dragOffset = .zero
//                        dismissProgress = 0
//                    }
//                    
//                    // Preload adjacent photos when index changes
//                    preloadAdjacentPhotos(currentIndex: newIndex)
//                    
//                     Clear transition state after a delay
//                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
//                        isTabViewTransitioning = false
//                    }
//                }
                
                // Photo counter overlay
                VStack {
                    HStack {
                        Spacer()
                        Text("\(currentIndex + 1) of \(allPhotos.count)")
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(12)
                            .opacity(1.0 - dismissProgress)
                        Spacer()
                    }
                    .padding(.top, 50)
                    
                    Spacer()
                }
            }
            .obscuredWhenInactive()
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Bail out until the drag is clearly vertical
//                        guard abs(value.translation.height) >
//                              abs(value.translation.width) else { return }
//
//                        dragOffset = CGSize(width: 0, height: value.translation.height)
//                        dismissProgress = min(value.translation.height /
//                                              (geometry.size.height * 0.4), 1.0)
                    }
                    .onEnded { value in
                        // Same dominant-axis guard here *before* any threshold checks
//                        guard abs(value.translation.height) >
//                              abs(value.translation.width) else { return }
//
//                        let dismissThreshold = geometry.size.height * 0.25
//                        let isQuickDownSwipe = value.velocity.height > 2000
//                        if value.translation.height > dismissThreshold || isQuickDownSwipe {
//                            withAnimation(.easeOut(duration: 0.3)) {
//                                dragOffset = CGSize(width: 0, height: geometry.size.height)
//                                dismissProgress = 1
//                            }
//                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                                onDismiss?()
//                                dismiss()
//                            }
//                        } else {
//                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
//                                dragOffset = .zero
//                                dismissProgress = 0
//                            }
//                        }
                    }
            )
        }
        .navigationBarHidden(true)
        .onAppear {
            preloadAdjacentPhotos(currentIndex: currentIndex)
        }
    }
    
    private func preloadAdjacentPhotos(currentIndex: Int) {
        // Preload previous photo
        if currentIndex > 0 {
            let previousPhoto = allPhotos[currentIndex - 1]
            DispatchQueue.global(qos: .userInitiated).async {
                _ = previousPhoto.thumbnail
            }
        }
        
        // Preload next photo
        if currentIndex < allPhotos.count - 1 {
            let nextPhoto = allPhotos[currentIndex + 1]
            DispatchQueue.global(qos: .userInitiated).async {
                _ = nextPhoto.thumbnail
            }
        }
    }
}
