//
//  CustomVideoPlayer.swift
//  Video Editor
//
//  Created by Raidan on 2025. 03. 03..
//

import SwiftUI
import Combine
import AVKit

// MARK: - Custom Player View
struct CustomPlayerView: View {
    @ObservedObject var playerVM: PlayerViewModel
    @State var videoURL: URL
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero
    @State private var videoSize = CGSize.zero

    init(playerVM: PlayerViewModel, videoURL: URL) {
        self.playerVM = playerVM
        self.videoURL = videoURL
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
        } catch {
            print("Failed to set audio session category: \(error)")
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CustomVideoPlayer(playerVM: playerVM, videoSize: $videoSize)
                    .aspectRatio(videoSize != .zero ? videoSize.width / videoSize.height : nil, contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                withAnimation(.interactiveSpring()) {
                                    scale = lastScale * value.magnification
                                }
                            }
                            .onEnded { value in
                                withAnimation(.spring()) {
                                    scale = max(1.0, min(scale, 3.0))
                                    lastScale = scale
                                    adjustOffsetForBounds(geometry: geometry)
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                if scale > 1.0 {
                                    offset = constrainOffset(
                                        CGSize(width: lastOffset.width + value.translation.width,
                                               height: lastOffset.height + value.translation.height),
                                        geometry: geometry
                                    )
                                }
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                    .simultaneousGesture(
                        TapGesture(count: 2)
                            .onEnded {
                                withAnimation(.spring()) {
                                    scale = scale > 1.0 ? 1.0 : 2.0
                                    lastScale = scale
                                    offset = scale == 1.0 ? .zero : offset
                                    lastOffset = offset
                                }
                            }
                    )
                    .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)

                VStack {
                    Spacer()
                    CustomControlsView(playerVM: playerVM)
                        .frame(maxWidth: .infinity)
                }
                .overlay(alignment: .bottomLeading, content: {
                    SeekerThumbnailView(.init(width: geometry.size.width, height: (geometry.size.height * 3.5)))
                        .offset(y: -60)
                })
            }
            .background(Color.black)
            .ignoresSafeArea(.container)
        }
        .onAppear {
            playerVM.setCurrentItem(AVPlayerItem(url: videoURL))
        }
        .onDisappear {
            playerVM.player.pause()
        }
    }

    @ViewBuilder
    func SeekerThumbnailView(_ videoSize: CGSize) -> some View {
        let thumbSize: CGSize = .init(width: 175, height: 100)
        ZStack {
            if let image = playerVM.draggingImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: thumbSize.width, height: thumbSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .bottom, content: {
                        if let currentItem = playerVM.player.currentItem {
                            Text(CMTime(seconds: playerVM.currentTime * currentItem.duration.seconds, preferredTimescale: 600).toTimeString())
                                .font(.callout)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .offset(y: 25)
                        }
                    })
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(.white, lineWidth: 2)
                    }
            } else {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(.black)
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(.white, lineWidth: 2)
                    }
            }
        }
        .frame(width: thumbSize.width, height: thumbSize.height)
        .opacity(playerVM.isEditingCurrentTime ? 1 : 0)
        /// Moving Along side with Gesture
        /// Adding Some Padding at Start and End
//        .offset(x: playerVM.isEditingCurrentTime * (videoSize.width - thumbSize.width - 20))
        .offset(x: 10)
    }
    private func constrainOffset(_ offset: CGSize, geometry: GeometryProxy) -> CGSize {
        let containerSize = geometry.size
        let scaledWidth = videoSize.width * scale
        let scaledHeight = videoSize.height * scale
        let maxX = max(0, (scaledWidth - containerSize.width) / 2)
        let maxY = max(0, (scaledHeight - containerSize.height) / 2)

        return CGSize(
            width: max(-maxX, min(maxX, offset.width)),
            height: max(-maxY, min(maxY, offset.height))
        )
    }

    private func adjustOffsetForBounds(geometry: GeometryProxy) {
        offset = constrainOffset(lastOffset, geometry: geometry)
        lastOffset = offset
    }
}

// MARK: - Custom Video Player
struct CustomVideoPlayer: UIViewRepresentable {
    @ObservedObject var playerVM: PlayerViewModel
    @Binding var videoSize: CGSize

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        Task {
            view.player = playerVM.player
            DispatchQueue.main.async {
                context.coordinator.setupPipController(for: view.playerLayer)
            }
            try await updateVideoSize(from: playerVM.player.currentItem)
        }
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.player = playerVM.player
        Task {
            try await updateVideoSize(from: playerVM.player.currentItem)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    private func updateVideoSize(from playerItem: AVPlayerItem?) async throws {
        guard let item = playerItem,
              let track = try await item.asset.loadTracks(withMediaType: .video).first else {
            videoSize = .zero
            return
        }
        let size = try await track.load(.naturalSize).applying(track.load(.preferredTransform))
        videoSize = CGSize(width: abs(size.width), height: abs(size.height))
    }

    class Coordinator: NSObject, AVPictureInPictureControllerDelegate {
        private let parent: CustomVideoPlayer
        private var pipController: AVPictureInPictureController?
        private var cancellable: AnyCancellable?

        init(_ parent: CustomVideoPlayer) {
            self.parent = parent
            super.init()

            cancellable = parent.playerVM.$isInPipMode
                .sink { [weak self] isInPipMode in
                    guard let self, let controller = self.pipController else { return }
                    if isInPipMode && !controller.isPictureInPictureActive {
                        controller.startPictureInPicture()
                    } else if !isInPipMode && controller.isPictureInPictureActive {
                        controller.stopPictureInPicture()
                    }
                }
        }

        func setupPipController(for playerLayer: AVPlayerLayer) {
            guard AVPictureInPictureController.isPictureInPictureSupported(),
                  pipController == nil,
                  let controller = AVPictureInPictureController(playerLayer: playerLayer) else {
                print("PiP not supported or already initialized")
                return
            }
            pipController = controller
            controller.delegate = self
            controller.canStartPictureInPictureAutomaticallyFromInline = true
        }

        func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.playerVM.isInPipMode = true
            }
        }

        func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.playerVM.isInPipMode = false
            }
        }
    }
}

extension CMTime {
    func toTimeString() -> String {
        let roundedSeconds = seconds.rounded()
        let hours: Int = Int(roundedSeconds / 3600)
        let min: Int = Int(roundedSeconds.truncatingRemainder(dividingBy: 3600) / 60)
        let sec: Int = Int(roundedSeconds.truncatingRemainder(dividingBy: 60))
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, min, sec)
        }
        
        return String(format: "%02d:%02d", min, sec)
    }
}
