//
//  PlayerView.swift
//  Video Editor
//
//  Created by Raidan on 2025. 03. 05..
//

import SwiftUI

struct PlayerView: View {
    @ObservedObject var viewModel: PlayerViewModel
    
    var body: some View {
        GeometryReader { proxy in
            VStack {
                FlexibleVideoPlayerView(viewModel: viewModel)
                    .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                VStack {
                    HStack {
                        Text(formatTime(seconds: viewModel.elapsedTime))
                        Spacer()
                        Text(formatTime(seconds: viewModel.totalTime))
                    }
                    .padding(.horizontal, 16)
                    HStack(spacing: 8) {
                        Button {
                            viewModel.handlePlayButton()
                        } label: {
                            Image(systemName: viewModel.playerStatus == .playing ? "pause.circle" : "play.circle")
                                .font(.system(size: 25))
                                .foregroundStyle(Color.blue)
                        }
                        Slider(
                            value: Binding(
                                get: { viewModel.elapsedTime },
                                set: { newValue in
                                    viewModel.elapsedTime = newValue
                                    updateThumbnail()
                                }
                            ),
                            in: 0...viewModel.totalTime,
                            onEditingChanged: onEditingChanged
                        )
                        .overlay(alignment: .bottomLeading) {
                            SeekerThumbnailView(.init(width: proxy.size.width, height: proxy.size.height))
                                .offset(y: -60)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem {
                    Button {
                        
                    } label: {
                        Text("Edit")
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    func SeekerThumbnailView(_ videoSize: CGSize) -> some View {
        let thumbSize: CGSize = .init(width: 175, height: 100)
        ZStack {
            if let draggingImage = viewModel.frameImage {
                Image(uiImage: draggingImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: thumbSize.width, height: thumbSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.white, lineWidth: 2))
            } else {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(.black)
                    .frame(width: thumbSize.width, height: thumbSize.height)
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.white, lineWidth: 2))
            }
        }
        .frame(width: thumbSize.width, height: thumbSize.height)
        .opacity(viewModel.isSeeking ? 1 : 0)
        .offset(x: (viewModel.elapsedTime / viewModel.totalTime) * (videoSize.width - thumbSize.width) + 10)
    }
    
    private func formatTime(seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let seconds = Int(seconds) % 60
        return hours > 0 ? String(format: "%02d:%02d:%02d", hours, minutes, seconds) : String(format: "%02d:%02d", minutes, seconds)
    }
    
    func onEditingChanged(editingStarted: Bool) {
        if editingStarted {
            viewModel.isSeeking = true
            VideoPlayer.shared.shouldObserveElapsedTime = false
            updateThumbnail()
        } else {
            viewModel.isSeeking = false
            VideoPlayer.shared.seek(to: viewModel.elapsedTime)
        }
    }

    private func updateThumbnail() {
        guard viewModel.totalTime > 0, !VideoPlayer.shared.thumbnailFrames.isEmpty else { return }
        let progress = max(min(viewModel.elapsedTime / viewModel.totalTime, 1), 0)
        let dragIndex = Int(progress * Double(VideoPlayer.shared.thumbnailFrames.count - 1))
        if VideoPlayer.shared.thumbnailFrames.indices.contains(dragIndex) {
            viewModel.frameImage = VideoPlayer.shared.thumbnailFrames[dragIndex]
        } else {
            print("Thumbnail frame not found for index: \(dragIndex)")
        }
    }
}
