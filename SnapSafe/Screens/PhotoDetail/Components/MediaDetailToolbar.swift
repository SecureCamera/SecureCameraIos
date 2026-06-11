//
//  MediaDetailToolbar.swift
//  SnapSafe
//
//  Liquid Glass floating toolbars for the photo/video detail pager.
//  Photo toolbar: Info · Obfuscate · Share · Decoy · Delete
//  Video toolbar: Share · Decoy · Delete  (Obfuscate doesn't apply to video)
//

import SwiftUI

// MARK: - Photo toolbar

struct PhotoDetailToolbar: View {
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
        toolbar
            .opacity(isZoomed ? 0 : 1)
            .animation(.easeInOut(duration: 0.2), value: isZoomed)
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            MediaToolbarButton(icon: "info.circle", label: "Info", action: onInfo)
            MediaToolbarButton(icon: "face.dashed", label: "Obfuscate", action: onObfuscate)
            MediaToolbarButton(icon: "square.and.arrow.up", label: "Share", action: onShare)

            if showDecoyButton {
                if isDecoyOperationLoading {
                    MediaToolbarButton(icon: nil, label: decoyButtonTitle, action: {}) {
                        ProgressView()
                            .controlSize(.small)
                    }
                    .disabled(true)
                } else {
                    MediaToolbarButton(icon: decoyButtonIcon, label: decoyButtonTitle,
                                       action: { onToggleDecoy?() })
                }
            }

            MediaToolbarButton(icon: "trash", label: "Delete", tint: .red, action: onDelete)
        }
        .glassToolbarBackground()
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }
}

// MARK: - Video toolbar

struct VideoDetailToolbar: View {
    var onShare: () -> Void
    var onDelete: () -> Void
    var onToggleDecoy: (() -> Void)?
    var showDecoyButton: Bool
    var decoyButtonTitle: String
    var decoyButtonIcon: String
    var isDecoyOperationLoading: Bool

    var body: some View {
        HStack(spacing: 0) {
            MediaToolbarButton(icon: "square.and.arrow.up", label: "Share", action: onShare)

            if showDecoyButton {
                if isDecoyOperationLoading {
                    MediaToolbarButton(icon: nil, label: decoyButtonTitle, action: {}) {
                        ProgressView()
                            .controlSize(.small)
                    }
                    .disabled(true)
                } else {
                    MediaToolbarButton(icon: decoyButtonIcon, label: decoyButtonTitle,
                                       action: { onToggleDecoy?() })
                }
            }

            MediaToolbarButton(icon: "trash", label: "Delete", tint: .red, action: onDelete)
        }
        .glassToolbarBackground()
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }
}

// MARK: - Shared button component

/// A single toolbar item: icon above label, minimum 44 × 44 tap target.
struct MediaToolbarButton<Indicator: View>: View {
    let icon: String?
    let label: String
    var tint: Color = .primary
    let action: () -> Void
    var indicator: (() -> Indicator)?

    @State private var tapTrigger = 0

    init(icon: String?, label: String, tint: Color = .primary,
         action: @escaping () -> Void,
         @ViewBuilder _ indicator: @escaping () -> Indicator) {
        self.icon = icon; self.label = label; self.tint = tint
        self.action = action; self.indicator = indicator
    }

    var body: some View {
        Button {
            tapTrigger &+= 1
            action()
        } label: {
            VStack(spacing: 4) {
                if let indicator {
                    indicator()
                        .frame(height: 24)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.title3)
                        .frame(height: 24)
                }
                Text(label)
                    .font(.caption)
                    // Keep every item one line tall so a longer label (e.g.
                    // "Remove Decoy" vs "Add Decoy") can't wrap and change the
                    // toolbar's height when toggled.
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .sensoryFeedback(.impact(weight: .light), trigger: tapTrigger)
    }
}

extension MediaToolbarButton where Indicator == EmptyView {
    init(icon: String?, label: String, tint: Color = .primary,
         action: @escaping () -> Void) {
        self.icon = icon; self.label = label; self.tint = tint
        self.action = action; self.indicator = nil
    }
}

// MARK: - Glass background

extension View {
    /// Liquid Glass on iOS 26+; `.ultraThinMaterial` on earlier versions.
    /// Always rendered in dark mode: the toolbar floats over an immersive
    /// black/photo background, so controls must always be light regardless
    /// of the system appearance setting.
    @ViewBuilder
    func glassToolbarBackground() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .capsule)
                .environment(\.colorScheme, .dark)
        } else {
            self.padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: .capsule)
                .environment(\.colorScheme, .dark)
        }
    }
}
