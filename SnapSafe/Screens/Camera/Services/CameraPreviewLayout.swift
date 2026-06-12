//
//  CameraPreviewLayout.swift
//  SnapSafe
//

import CoreGraphics

internal enum CameraPreviewLayout {
    /// Portrait width:height ratio for a capture format whose dimensions are
    /// reported in landscape (e.g. 1920×1080 → 1080/1920 = 0.5625).
    /// Falls back to 9:16 (the `.high` preset's ratio) for degenerate input.
    internal static func portraitAspectRatio(formatWidth: Int32, formatHeight: Int32) -> CGFloat {
        guard formatWidth > 0, formatHeight > 0 else { return 9.0 / 16.0 }
        return CGFloat(formatHeight) / CGFloat(formatWidth)
    }

    /// Largest centered rect of `aspectRatio` (width/height) fitting `size`,
    /// preferring to fill the width.
    internal static func containerSize(for size: CGSize, aspectRatio: CGFloat) -> CGSize {
        let width = size.width
        let height = width / aspectRatio
        if height > size.height {
            return CGSize(width: size.height * aspectRatio, height: size.height)
        }
        return CGSize(width: width, height: height)
    }
}
