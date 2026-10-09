//
//  PagerChromeState.swift
//  SnapSafe
//
//  Shared chrome state for the media detail pager. Owned by
//  EnhancedPhotoDetailView and injected into each hosted page (via
//  .environment) so pages rendered inside UIHostingControllers — like the
//  inline video player — can fade their controls while a dismiss drag is in
//  flight, matching the page-level photo toolbar.
//

import Observation

@MainActor
@Observable
final class PagerChromeState {
    var isDismissDragging = false
}
