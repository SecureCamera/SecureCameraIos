//
//  VideoInfoViewModel.swift
//  SnapSafe
//
//  Loads VideoMetaData for a video and exposes display strings for VideoInfoView.
//  Mirrors ImageInfoViewModel.
//

import SwiftUI
import FactoryKit
import Logging

@MainActor
final class VideoInfoViewModel: ObservableObject {
    private let videoDef: VideoDef

    @Injected(\.secureImageRepository)
    private var secureImageRepository: SecureImageRepository

    @Published var metadata: VideoMetaData?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    init(videoDef: VideoDef) {
        self.videoDef = videoDef
        Task { await loadMetadata() }
    }

    // MARK: - Display strings

    var filename: String { videoDef.videoName }

    var resolution: String { metadata?.resolutionString ?? VideoMetaData.unavailable }
    var fileSize: String { metadata?.fileSizeString ?? VideoMetaData.unavailable }
    var dateTaken: String { metadata?.dateTakenString ?? VideoMetaData.unavailable }
    var isDateFromFilename: Bool { metadata?.isDateFromFilename ?? false }
    var orientation: String { metadata?.orientationString ?? VideoMetaData.unavailable }
    var location: String { metadata?.locationString ?? VideoMetaData.unavailable }
    var duration: String { metadata?.durationString ?? VideoMetaData.unavailable }
    var codec: String { metadata?.codecString ?? VideoMetaData.unavailable }
    var frameRate: String { metadata?.frameRateString ?? VideoMetaData.unavailable }
    var bitrate: String { metadata?.bitrateString ?? VideoMetaData.unavailable }

    // MARK: - Loading

    private func loadMetadata() async {
        isLoading = true
        do {
            metadata = try await secureImageRepository.getVideoMetaData(videoDef)
            errorMessage = nil
        } catch {
            Logger.storage.error("Error loading video metadata: \(error)")
            errorMessage = "Could not load video information."
        }
        isLoading = false
    }
}
