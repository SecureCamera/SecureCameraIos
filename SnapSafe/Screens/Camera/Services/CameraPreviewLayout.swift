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

    /// The largest candidate (by pixel area) whose aspect ratio matches the
    /// reference dimensions within `tolerance`. Falls back to the largest
    /// candidate overall when none match, so callers always get usable
    /// dimensions. Returns nil only for an empty candidate list.
    ///
    /// Used to pick `maxPhotoDimensions`: stills must keep the SAME aspect as
    /// the active video format, otherwise captures would show more of the
    /// scene than the preview (breaking preview == capture).
    internal static func largestDimensions(
        matchingAspectOfWidth referenceWidth: Int32,
        height referenceHeight: Int32,
        in candidates: [(width: Int32, height: Int32)],
        tolerance: CGFloat = 0.01
    ) -> (width: Int32, height: Int32)? {
        let byArea: ((width: Int32, height: Int32), (width: Int32, height: Int32)) -> Bool = {
            Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height)
        }
        guard referenceWidth > 0, referenceHeight > 0 else { return candidates.max(by: byArea) }

        let referenceAspect = CGFloat(referenceWidth) / CGFloat(referenceHeight)
        let matching = candidates.filter { candidate in
            guard candidate.width > 0, candidate.height > 0 else { return false }
            let aspect = CGFloat(candidate.width) / CGFloat(candidate.height)
            return abs(aspect - referenceAspect) / referenceAspect <= tolerance
        }
        return (matching.isEmpty ? candidates : matching).max(by: byArea)
    }
}
