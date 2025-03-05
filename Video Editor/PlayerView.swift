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
                CustomVideoPlayer(viewModel: viewModel)
                .aspectRatio(contentMode: .fit)
                .frame(width: proxy.size.width, height: proxy.size.height * 0.5)
                .clipped()
                .shadow(color: Color.black.opacity(0.3), radius: 10, x: 10, y: 10)
                Spacer()
                VStack {
                    HStack {
                        Text(formatTime(seconds: viewModel.elapsedTime))
                        Spacer()
                        Text(formatTime(seconds: viewModel.totalTime))
                    }
                    .padding(.horizontal, 16)

                    Slider(
                        value: $viewModel.elapsedTime,
                        in: 0...viewModel.totalTime,
                        onEditingChanged: onEditingChanged
                    )
                    .padding(.horizontal, 16)
                }

                ControllButton(viewModel: viewModel)
                   // .padding(.bottom, safeArea.bottom)
            }
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func formatTime(seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let seconds = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
extension PlayerView {
    func onEditingChanged(editingStarted: Bool) {
        if editingStarted {
            VideoPlayer.shared.shouldObserveElapsedTime = false
        } else {
            VideoPlayer.shared.seek(to: viewModel.elapsedTime)
        }
    }
}

struct ControllButton: View {
    @ObservedObject var viewModel: PlayerViewModel

    var body: some View {
        VStack {
            HStack(spacing: 25) {
                Button {
                    viewModel.seekFifteenBackward()
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.blue.opacity(0.8))
                }
                .frame(width: 40, height: 40)

                Button {
                    viewModel.handlePlayButton()
                } label: {
                    Image(systemName: viewModel.playerStatus == .playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(Color.blue)
                }
                .frame(width: 60, height: 60)

                Button {
                    viewModel.seekFifteenForward()
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.blue.opacity(0.8))
                }
                .frame(width: 40, height: 40)
            }
            .padding(.vertical, 10)
        }
    }
}
