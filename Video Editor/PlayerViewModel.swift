//
//  PlayerViewModel.swift
//  Video Editor
//
//  Created by Raidan on 2025. 03. 03..
//

import Foundation
import Combine
import CoreTransferable

class PlayerViewModel: ObservableObject {
    @ObservationIgnored private let sharedStateManager = PlaybackQueue.shared
    @Published var totalTime: Double = 0
    @Published var elapsedTime: Double = 0
    @Published var playerStatus: PlaybackState = .waitingForSelection
    @Published var isPlaying: Bool = false
    @Published var isInPipMode: Bool = false

    private var cancellables: Set<AnyCancellable> = []

    var currentItem: VideoItem? {
        return sharedStateManager.currentItem
    }

    init(videoURL: URL) {
        sharedStateManager.setPlaybackQueue(for: "video", items: [.init(url: videoURL)])
        play()
    }

    deinit {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        PODLogInfo("PlayerViewModel deinitialized")
    }

    func play() {
        guard let currentItem = currentItem else {
            PODLogError("No current Video to play")
            return
        }
        cleanupSubscriptions()
        subscribe()
        VideoPlayer.shared.play(item: currentItem)
    }

    func stop() {
        cleanupSubscriptions()
        VideoPlayer.shared.stop()
        sharedStateManager.cleanupQueue()
    }

    func pause() {
        VideoPlayer.shared.pause()
    }

    func resume() {
        VideoPlayer.shared.resume()
    }

    func handlePlayButton() {
        guard let item = self.currentItem else {
            return
        }
        switch playerStatus {
        case .playing:
            if let beingPlayedItem = VideoPlayer.shared.currentItem {
                if beingPlayedItem  == item {
                    VideoPlayer.shared.pause()
                } else {
                    VideoPlayer.shared.play(item: item)
                }
            }
        case .paused:
            if let beingPlayedItem = VideoPlayer.shared.currentItem {
                if beingPlayedItem == item {
                    VideoPlayer.shared.resume()
                } else {
                    VideoPlayer.shared.play(item: item)
                }
            } else {
                VideoPlayer.shared.play(item: item)
            }
        case .stopped:
            VideoPlayer.shared.play(item: item)
        default:
            break
        }
    }

    func subscribe() {
        guard let item = self.currentItem else {
            return
        }

        VideoPlayer.shared.elapsedTimeObserver
            .sink { [weak self] value in
                guard let self = self,
                      VideoPlayer.shared.currentItem == item else { return }
                self.elapsedTime = value
            }
            .store(in: &cancellables)

        VideoPlayer.shared.playbackStatePublisher
            .sink { [weak self] status in
                guard let self = self else { return }
                if let item = VideoPlayer.shared.currentItem {
                    if item == item {
                        self.playerStatus = status
                        self.isPlaying = (status == .playing)
                    } else {
                        self.playerStatus = .stopped
                        self.isPlaying = false
                    }
                } else {
                    self.playerStatus = status
                    self.isPlaying = (status == .playing)
                }
            }
            .store(in: &cancellables)

        VideoPlayer.shared.totalItemTimeObserver
            .sink { [weak self] value in
                guard let self = self,
                      VideoPlayer.shared.currentItem == item else { return }
                self.totalTime = value
            }
            .store(in: &cancellables)
    }

    private func cleanupSubscriptions() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    // MARK: - Protocol Methods
    func seek() {}

    func seekFifteenForward() {
        VideoPlayer.shared.seekFifteenForward()
    }

    func seekFifteenBackward() {
        VideoPlayer.shared.seekFifteenBackward()
    }
}

// MARK: - Video Transferable
public struct VideoItem: Transferable, Equatable {
    let url: URL

    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let copy = URL.documentsDirectory.appendingPathComponent("video.mp4")
            try? FileManager.default.removeItem(at: copy)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}

// MARK: - Load State
public enum LoadState {
    case unknown, loading, loaded(VideoItem), failed
}
