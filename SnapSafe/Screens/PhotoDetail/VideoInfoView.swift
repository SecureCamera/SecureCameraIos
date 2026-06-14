//
//  VideoInfoView.swift
//  SnapSafe
//
//  Displays metadata for a video. Mirrors ImageInfoView, with a Video technical
//  section (duration, codec, frame rate, bitrate) in place of the Camera section.
//

import SwiftUI

struct VideoInfoView: View {
    @StateObject private var viewModel: VideoInfoViewModel
    @Environment(\.dismiss) private var dismiss

    init(videoDef: VideoDef) {
        _viewModel = StateObject(wrappedValue: VideoInfoViewModel(videoDef: videoDef))
    }

    var body: some View {
        if viewModel.isLoading {
            ProgressView("Loading video information...")
                .navigationTitle("Video Information")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { doneButton }
        } else {
            Form {
                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section(header: Text("Basic Information")) {
                        infoRow("Filename", viewModel.filename)
                        infoRow("Resolution", viewModel.resolution)
                        infoRow("File Size", viewModel.fileSize)
                    }

                    Section(header: Text("Date Information")) {
                        infoRow("Date Taken", viewModel.dateTaken)
                        if viewModel.isDateFromFilename {
                            Text("(from filename)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section(header: Text("Orientation")) {
                        infoRow("Orientation", viewModel.orientation)
                    }

                    Section(header: Text("Location")) {
                        Text(viewModel.location)
                            .foregroundStyle(.secondary)
                    }

                    Section(header: Text("Video Information")) {
                        infoRow("Duration", viewModel.duration)
                        infoRow("Codec", viewModel.codec)
                        infoRow("Frame Rate", viewModel.frameRate)
                        infoRow("Bitrate", viewModel.bitrate)
                    }
                }
            }
            .navigationTitle("Video Information")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { doneButton }
        }
    }

    @ToolbarContentBuilder
    private var doneButton: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
        }
    }

    private func infoRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
