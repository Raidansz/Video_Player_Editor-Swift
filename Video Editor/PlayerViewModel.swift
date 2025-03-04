//
//  PlayerViewModel.swift
//  Video Editor
//
//  Created by Raidan on 2025. 03. 03..
//

import AVFoundation
import Combine
import CoreTransferable
import UIKit

// MARK: - Player View Model
final class PlayerViewModel: ObservableObject {
    let player = AVPlayer()
    @Published var isInPipMode = false
    @Published var isPlaying = false
    @Published var isEditingCurrentTime = false
    @Published var isSeeking = false
    @Published var currentTime: Double = 0
    @Published var duration: Double?
    @Published private var thumbnailFrames: [UIImage] = []
    @Published var draggingImage: UIImage?

    private var subscriptions = Set<AnyCancellable>()
    private var timeObserver: Any?

    deinit {
        removeTimeObserver()
        subscriptions.forEach { $0.cancel() }
    }

    init() {
        setupBindings()
    }

    private func removeTimeObserver() {
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    private func setupBindings() {
        $isEditingCurrentTime
            .dropFirst()
            .sink { [weak self] isEditing in
                guard let self else { return }
                self.isSeeking = isEditing
                if !isEditing {
                    let time = CMTime(seconds: self.currentTime, preferredTimescale: 600)
                    self.player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                        if self.isPlaying {
                            self.player.playImmediately(atRate: 1.0)
                        }
                    }
                }
            }
            .store(in: &subscriptions)

        // Real-time seeking observer
        $currentTime
            .combineLatest($isSeeking)
            .filter { $1 } // Only when seeking
            .sink { [weak self] time, _ in
                guard let self, !self.thumbnailFrames.isEmpty else { return }
                let totalDuration = self.duration ?? 0
                guard totalDuration > 0 else { return }
                
                // Calculate frame index based on current time
                let progress = time / totalDuration
                let frameIndex = min(
                    max(Int(progress * Double(self.thumbnailFrames.count)), 0),
                    self.thumbnailFrames.count - 1
                )
                
                Task { @MainActor in
                    self.draggingImage = self.thumbnailFrames[frameIndex]
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
        draggingImage = nil
        thumbnailFrames.removeAll()
        player.replaceCurrentItem(with: item)
        player.playImmediately(atRate: 1.0)

        item.publisher(for: \.status)
            .filter { $0 == .readyToPlay }
            .sink { [weak self] _ in
                guard let self else { return }
                Task {
                    do {
                        let duration = try await item.asset.load(.duration).seconds
                        await MainActor.run {
                            self.duration = duration
                        }
                    } catch {
                        print("Failed to load duration: \(error.localizedDescription)")
                    }
                }
            }
            .store(in: &subscriptions)
        generateThumbnailFrames()
    }

    @MainActor
    func togglePipMode() {
        isInPipMode.toggle()
    }

    func generateThumbnailFrames() {
        Task.detached { [weak self] in
            guard let self, let asset = await self.player.currentItem?.asset else { return }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = .init(width: 250, height: 250)
            
            do {
                let totalDuration = try await asset.load(.duration).seconds
                let frameCount = min(100, Int(totalDuration / 0.01))
                var frameTimes: [CMTime] = []
                
                let step = totalDuration / Double(frameCount)
                for i in 0..<frameCount {
                    let time = CMTime(seconds: Double(i) * step, preferredTimescale: 600)
                    frameTimes.append(time)
                }
                
                for await result in generator.images(for: frameTimes) {
                    let cgImage = try result.image
                    await MainActor.run(body: {
                        self.thumbnailFrames.append(UIImage(cgImage: cgImage))
                    })
                }
            } catch {
                print("Thumbnail generation failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Video Transferable
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
