//
//  CustomVideoPlayer.swift
//  Video Editor
//
//  Created by Raidan on 2025. 03. 03..
//

import SwiftUI
import Combine
import _AVKit_SwiftUI

struct CustomVideoPlayer: UIViewRepresentable {
    @ObservedObject var viewModel: PlayerViewModel

    func makeUIView(context: Context) -> PlayerSceneView {
        let view = PlayerSceneView()
        view.player = VideoPlayer.shared.player
        context.coordinator.setController(view.playerLayer)
        return view
    }

    func updateUIView(_ uiView: PlayerSceneView, context: Context) { }

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    class Coordinator: NSObject, AVPictureInPictureControllerDelegate {
        private let parent: CustomVideoPlayer
        private var controller: AVPictureInPictureController?
        private var cancellable: AnyCancellable?

        init(_ parent: CustomVideoPlayer) {
            self.parent = parent
            super.init()

            cancellable = parent.viewModel.$isInPipMode
                .sink { [weak self] in
                    guard let self = self,
                          let controller = self.controller else { return }
                    if $0 {
                        if controller.isPictureInPictureActive == false {
                            controller.startPictureInPicture()
                        }
                    } else if controller.isPictureInPictureActive {
                        controller.stopPictureInPicture()
                    }
                }
        }

        func setController(_ playerLayer: AVPlayerLayer) {
            controller = AVPictureInPictureController(playerLayer: playerLayer)
            controller?.canStartPictureInPictureAutomaticallyFromInline = true
            controller?.delegate = self
        }

        func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            parent.viewModel.isInPipMode = true
        }

        func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            parent.viewModel.isInPipMode = false
        }
    }
}

final class PlayerSceneView: UIView {
    override static var layerClass: AnyClass {
        return AVPlayerLayer.self
    }
    
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    
    var player: AVPlayer? {
        get {
            playerLayer.player
        }
        set {
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.player = newValue
        }
    }
}
