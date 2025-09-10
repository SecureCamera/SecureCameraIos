//
//  EnhancedPhotoDetailViewModel.swift
//  SnapSafe
//
//  Created by Claude on 9/9/25.
//

import SwiftUI
import FactoryKit

@MainActor
class EnhancedPhotoDetailViewModel: ObservableObject {
    // MARK: - Dependencies
    
    @Injected(\.secureImageRepository)
    private var secureImageRepository: SecureImageRepository
    
    // MARK: - Published Properties
    
    @Published var photoFiles: [PhotoDef] = []
    @Published var currentIndex: Int = 0
    @Published var dragOffset: CGSize = .zero
    @Published var dismissProgress: CGFloat = 0
    @Published var isTabViewTransitioning: Bool = false
    @Published var lastIndexChangeTime: Date = Date()
    
    // MARK: - Configuration
    
    let showFaceDetection: Bool
    var onDelete: ((PhotoDef) -> Void)?
    var onDismiss: (() -> Void)?
    
    // MARK: - Initialization
    
    init(allPhotos: [SecurePhoto], initialIndex: Int, showFaceDetection: Bool, onDelete: ((PhotoDef) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.photoFiles = mapToPhotoDefs(allPhotos)
        self.currentIndex = initialIndex
        self.showFaceDetection = showFaceDetection
        self.onDelete = onDelete
        self.onDismiss = onDismiss
    }
    
    // MARK: - Computed Properties
    
    var photoCount: Int {
        photoFiles.count
    }
    
    var currentPhotoDisplayText: String {
        "\(currentIndex + 1) of \(photoCount)"
    }
    
    var backgroundOpacity: Double {
        1.0 - dismissProgress * 0.8
    }
    
    var photoScaleEffect: Double {
        1.0 - dismissProgress * 0.2
    }
    
    var overlayOpacity: Double {
        1.0 - dismissProgress
    }
    
    // MARK: - Index Management
    
    func handleIndexChange(newIndex: Int) {
        print("🟣 EnhancedPhotoDetailViewModel: currentIndex changed from \(currentIndex) to \(newIndex)")
        
        // Track when TabView transitions occur
        isTabViewTransitioning = true
        lastIndexChangeTime = Date()
        
        // Reset any dismiss progress during navigation
        withAnimation(.easeOut(duration: 0.2)) {
            dragOffset = .zero
            dismissProgress = 0
        }
        
        // Preload adjacent photos when index changes
        preloadAdjacentPhotos(currentIndex: newIndex)
        
        // Clear transition state after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.isTabViewTransitioning = false
        }
    }
    
    // MARK: - Preloading
    
    func preloadAdjacentPhotos(currentIndex: Int) {
        guard !photoFiles.isEmpty else { return }
        
        // Preload previous photo thumbnail
        if currentIndex > 0 {
            let previousPhotoDef = photoFiles[currentIndex - 1]
            Task(priority: .userInitiated) {
                _ = try? await secureImageRepository.readThumbnail(previousPhotoDef)
            }
        }
        
        // Preload next photo thumbnail
        if currentIndex < photoFiles.count - 1 {
            let nextPhotoDef = photoFiles[currentIndex + 1]
            Task(priority: .userInitiated) {
                _ = try? await secureImageRepository.readThumbnail(nextPhotoDef)
            }
        }
    }
    
    // MARK: - Gesture Handling
    
    func handleDragChanged(_ value: DragGesture.Value, geometryHeight: CGFloat) {
        // Bail out until the drag is clearly vertical
        guard abs(value.translation.height) > abs(value.translation.width) else { return }
        
        dragOffset = CGSize(width: 0, height: value.translation.height)
        dismissProgress = min(value.translation.height / (geometryHeight * 0.4), 1.0)
    }
    
    func handleDragEnded(_ value: DragGesture.Value, geometryHeight: CGFloat, dismiss: @escaping () -> Void) {
        // Same dominant-axis guard here *before* any threshold checks
        guard abs(value.translation.height) > abs(value.translation.width) else { return }
        
        let dismissThreshold = geometryHeight * 0.25
        let isQuickDownSwipe = value.velocity.height > 2000
        
        if value.translation.height > dismissThreshold || isQuickDownSwipe {
            // Dismiss the view
            withAnimation(.easeOut(duration: 0.3)) {
                dragOffset = CGSize(width: 0, height: geometryHeight)
                dismissProgress = 1
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.onDismiss?()
                dismiss()
            }
        } else {
            // Return to original position
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                dragOffset = .zero
                dismissProgress = 0
            }
        }
    }
    
    // MARK: - View Lifecycle
    
    func onAppear() {
        preloadAdjacentPhotos(currentIndex: currentIndex)
    }
    
    // MARK: - Photo Management
    
    func deletePhoto(at index: Int) {
        guard index < photoFiles.count else { return }
        
        let photoDefToDelete = photoFiles[index]
        
        // Notify delegate
        onDelete?(photoDefToDelete)
        
        // Remove from local array
        photoFiles.remove(at: index)
        
        if photoFiles.isEmpty {
            // No photos left, dismiss the view
            onDismiss?()
        } else {
            // Adjust current index if necessary
            if currentIndex >= photoFiles.count {
                currentIndex = photoFiles.count - 1
            }
        }
    }
}
