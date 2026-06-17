//
//  VideoSurfaceView.swift
//  SnapSafe
//
//  A bare video rendering surface backed by AVPlayerLayer — no transport
//  controls. We provide our own glass controls, so AVKit's built-in controls
//  (which can't be repositioned) are not used.
//

import SwiftUI
import UIKit
import AVKit

struct VideoSurfaceView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .clear
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }

    final class PlayerLayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer {
            // `layerClass` guarantees the backing layer is an AVPlayerLayer; this
            // cast can only fail if that override is removed.
            guard let playerLayer = layer as? AVPlayerLayer else {
                fatalError("Backing layer must be an AVPlayerLayer; check layerClass")
            }
            return playerLayer
        }
    }
}
