//
//  CustomVideoPlayer.swift
//  Video Editor
//
//  Created by Raidan on 2025. 03. 03..
//

import SwiftUI
import Combine
import AVKit

struct FlexibleVideoPlayerView: View {
    @ObservedObject var viewModel: PlayerViewModel
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isInteracting: Bool = false

    var body: some View {
        GeometryReader { geometry in
            CustomVideoPlayer(viewModel: viewModel)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(scale * (isInteracting ? 1.02 : 1.0))
                .offset(offset)
                .shadow(radius: isInteracting ? 10 : 0)
                .animation(.interactiveSpring(), value: scale)
                .animation(.interactiveSpring(), value: offset)
                .animation(.easeInOut(duration: 0.2), value: isInteracting)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            isInteracting = true
                            let delta = value / lastScale
                            lastScale = value
                            let newScale = scale * delta
                            scale = max(1.0, min(newScale, 3.0))
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                            isInteracting = false
                        }
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isInteracting = true
                            withAnimation(.interactiveSpring()) {
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                        }
                        .onEnded { _ in
                            lastOffset = offset
                            isInteracting = false
                        }
                )
                .gesture(
                    TapGesture(count: 2)
                        .onEnded {
                            withAnimation(.spring()) {
                                scale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                )
                .clipped()
        }
    }
}

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
            playerLayer.videoGravity = .resizeAspect
            playerLayer.player = newValue
        }
    }
}
