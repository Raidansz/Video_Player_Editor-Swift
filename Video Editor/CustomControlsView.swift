//
//  CustomControlsView.swift
//  Video Editor
//
//  Created by Raidan on 2025. 03. 03..
//

import SwiftUI

// MARK: - Custom Controls View
struct CustomControlsView: View {
    @ObservedObject var playerVM: PlayerViewModel

    var body: some View {
        HStack {
            Button(action: {
                playerVM.isPlaying ? playerVM.player.pause() : playerVM.player.playImmediately(atRate: 1.0)
            }) {
                Image(systemName: playerVM.isPlaying ? "pause.circle" : "play.circle")
                    .imageScale(.large)
            }

            if let duration = playerVM.duration {
                Slider(value: $playerVM.currentTime, in: 0...duration, onEditingChanged: { editing in
                    playerVM.isEditingCurrentTime = editing
                })
            } else {
                Spacer()
            }
        }
        .padding()
        .background(.thinMaterial)
    }
}
