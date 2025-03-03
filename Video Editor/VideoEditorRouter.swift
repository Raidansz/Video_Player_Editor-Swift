//
//  VideoEditorRouter.swift
//  Video Editor
//
//  Created by Raidan on 2025. 03. 03..
//

import SwiftUI

// MARK: - Video Editor View
struct VideoEditorRouter: View {
    @Binding var loadState: LoadState
    @StateObject private var playerVM = PlayerViewModel()

    var body: some View {
        switch loadState {
        case .loaded(let video):
            CustomPlayerView(playerVM: playerVM, videoURL: video.url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unknown:
            Text("Select a video to start")
        case .loading:
            ProgressView("Loading...")
        case .failed:
            Text("Failed to load video")
        }
    }
}
