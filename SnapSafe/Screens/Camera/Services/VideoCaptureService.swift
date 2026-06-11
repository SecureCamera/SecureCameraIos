//
//  VideoCaptureService.swift
//  SnapSafe
//
//  Created by Claude on 1/26/26.
//

import Foundation
import AVFoundation
import Combine
import Logging

// periphery:ignore all
@MainActor
protocol VideoCapturing: ObservableObject {
    // periphery:ignore
    var isRecording: Bool { get }
    // periphery:ignore
    var recordingDurationMs: Int64 { get }
    // periphery:ignore
    func startRecording(session: AVCaptureSession, movieOutput: AVCaptureMovieFileOutput, preview: AVCaptureVideoPreviewLayer?) -> URL?
    // periphery:ignore
    func stopRecording()
}

// periphery:ignore all
@MainActor
final class VideoCaptureService: NSObject, ObservableObject, VideoCapturing {

    // MARK: - Published Properties

    @Published var isRecording: Bool = false
    @Published var recordingDurationMs: Int64 = 0

    /// Called when a recording finishes successfully, with the output file URL.
    var onRecordingFinished: ((URL) -> Void)?

    /// Called once a recording has fully finalized (success or failure), after
    /// the file output is done writing. Use this to release resources tied to
    /// the recording, e.g. detaching the microphone input.
    var onRecordingStopped: (() -> Void)?

    // MARK: - Properties

    private var activeMovieOutput: AVCaptureMovieFileOutput?
    private var durationTimer: Timer?
    private var recordingStartTime: Date?

    // MARK: - Directory Management

    private func getVideosDirectory() -> URL {
        let appSupportPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var videosDir = appSupportPath.appendingPathComponent("videos")

        // Create directory and exclude from backup
        do {
            try FileManager.default.createDirectory(at: videosDir, withIntermediateDirectories: true, attributes: nil)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try videosDir.setResourceValues(resourceValues)
        } catch {
            Logger.camera.error("Failed to setup videos directory: \(error)")
        }

        return videosDir
    }

    // MARK: - Public Methods

    func startRecording(session: AVCaptureSession, movieOutput: AVCaptureMovieFileOutput, preview: AVCaptureVideoPreviewLayer?) -> URL? {
        guard !isRecording else {
            Logger.camera.warning("Recording already in progress")
            return nil
        }

        // Ensure movie output is added to session
        if !session.outputs.contains(movieOutput) {
            Logger.camera.error("Movie output not added to session")
            return nil
        }

        // Store reference to the movie output for stopRecording
        activeMovieOutput = movieOutput

        // Create output file
        let videosDir = getVideosDirectory()
        let timestamp = DateFormatter.videoTimestamp.string(from: Date())
        let filename = "video_\(timestamp).mov"
        let outputURL = videosDir.appendingPathComponent(filename)

        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL)

        // Configure video orientation
        if let connection = movieOutput.connection(with: .video) {
            // Get proper rotation for video
            if let deviceInput = session.inputs
                .compactMap({ $0 as? AVCaptureDeviceInput })
                .first(where: { $0.device.hasMediaType(.video) }) {

                let rotationCoordinator = AVCaptureDevice.RotationCoordinator(
                    device: deviceInput.device,
                    previewLayer: preview
                )
                connection.videoRotationAngle = rotationCoordinator.videoRotationAngleForHorizonLevelCapture
            }
        }

        // Start recording
        movieOutput.startRecording(to: outputURL, recordingDelegate: self)

        Logger.camera.info("Starting video recording to: \(filename)")
        return outputURL
    }

    func stopRecording() {
        guard isRecording, let movieOutput = activeMovieOutput else {
            Logger.camera.warning("No recording in progress to stop")
            return
        }

        movieOutput.stopRecording()
        Logger.camera.info("Stopping video recording")
    }

    // MARK: - Private Methods

    private func startDurationTimer() {
        recordingDurationMs = 0
        recordingStartTime = Date()

        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                let elapsed = Date().timeIntervalSince(startTime)
                self.recordingDurationMs = Int64(elapsed * 1000)
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
        recordingStartTime = nil
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension VideoCaptureService: AVCaptureFileOutputRecordingDelegate {

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        Task { @MainActor in
            self.isRecording = true
            self.startDurationTimer()
            Logger.camera.info("Video recording started")
        }
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor in
            self.isRecording = false
            self.stopDurationTimer()
            self.activeMovieOutput = nil

            if let error = error {
                Logger.camera.error("Video recording error: \(error.localizedDescription)")
                // Clean up failed recording
                try? FileManager.default.removeItem(at: outputFileURL)
            } else {
                Logger.camera.info("Video recording completed successfully", metadata: [
                    "file": .string(outputFileURL.lastPathComponent),
                    "durationMs": .stringConvertible(self.recordingDurationMs)
                ])
                self.onRecordingFinished?(outputFileURL)
            }

            // File output has finished writing; safe to release the mic now.
            self.onRecordingStopped?()
        }
    }
}

// MARK: - DateFormatter Extension

private extension DateFormatter {
    static let videoTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
