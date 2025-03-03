//
//  PlayerViewModel.swift
//  Video Editor
//
//  Created by Raidan on 2025. 03. 03..
//

import AVFoundation
import Combine
import CoreTransferable

// MARK: - Player View Model
final class PlayerViewModel: ObservableObject {
    let player = AVPlayer()
    @Published var isInPipMode = false
    @Published var isPlaying = false
    @Published var isEditingCurrentTime = false
    @Published var currentTime: Double = 0
    @Published var duration: Double?

    private var subscriptions = Set<AnyCancellable>()
    private var timeObserver: Any?

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        subscriptions.forEach { $0.cancel() }
    }

    init() {
        setupBindings()
    }

    private func setupBindings() {
        $isEditingCurrentTime
            .dropFirst()
            .filter { !$0 }
            .sink { [weak self] _ in
                guard let self else { return }
                let time = CMTime(seconds: self.currentTime, preferredTimescale: 600)
                self.player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    if self.isPlaying {
                        self.player.playImmediately(atRate: 1.0)
                    }
                }
            }
            .store(in: &subscriptions)

        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                Task { @MainActor in
                    self.isPlaying = status == .playing
                }
            }
            .store(in: &subscriptions)

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self, !self.isEditingCurrentTime else { return }
            Task { @MainActor in
                self.currentTime = time.seconds
            }
        }
    }

    @MainActor
    func setCurrentItem(_ item: AVPlayerItem) {
        currentTime = 0
        duration = nil
        player.replaceCurrentItem(with: item)
        player.playImmediately(atRate: 1.0)

        item.publisher(for: \.status)
            .filter { $0 == .readyToPlay }
            .sink { [weak self] _ in
                guard let self else { return }
                Task {
                    let duration = try? await item.asset.load(.duration).seconds
                    await MainActor.run {
                        self.duration = duration
                    }
                }
            }
            .store(in: &subscriptions)
    }

    @MainActor
    func togglePipMode() {
        isInPipMode.toggle()
    }
}

// MARK: - video Transferable
public struct VideoItem: Transferable {
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
