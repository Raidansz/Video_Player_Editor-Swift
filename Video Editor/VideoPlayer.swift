//
//  VideoPlayer.swift
//  Video Editor
//
//  Created by Raidan on 2025. 03. 04..
//

import Foundation
import AVFoundation
import MediaPlayer
import Combine

final class VideoPlayer: NSObject {
    /// Shared singleton instance.
    static let shared = VideoPlayer()

    /// The AVQueuePlayer instance used for playback.
    var player: AVQueuePlayer?

    /// Currently playing Video.
    private(set) var currentItem: VideoItem?

    /// Token for the periodic time observer.
    private var timeObserver: Any?

    var shouldObserveElapsedTime: Bool = true
    var totalItemTimeObserver = PassthroughSubject<TimeInterval, Never>()
    var elapsedTimeObserver = PassthroughSubject<TimeInterval, Never>()

    /// Counter for auto-retry attempts.
    private var retryAttempt: Int = 0
    /// Maximum number of retry attempts.
    private let maxRetryAttempts = 3

    /// Closure to update UI or other components about playback status changes.
    var onPlaybackStatusChanged: ((Bool) -> Void)?

    /// Closure to report playback errors.
    var onPlaybackError: ((Error) -> Void)?

    /// Combine subscriptions that live as long as the PodcastPlayer.
    private var cancellables: Set<AnyCancellable> = []
    /// Combine subscriptions tied to the current AVPlayerItem.
    private var playerItemCancellables: Set<AnyCancellable> = []

    var playbackStatePublisher = CurrentValueSubject<PlaybackState, Never>(.waitingForSelection)

    @Published var thumbnailFrames: [UIImage] = []

    @Published var elapsedTime: Double = .zero
    @Published var totalTime: Double = .zero

    private var artworkTask: Task<Void, Never>?

    /// Cached now playing info dictionary.
    private var nowPlayingInfoDict: [String: Any] = [:]

    // MARK: - Initialization

    /// Private initializer to enforce singleton usage.
    private override init() {
        super.init()
        setupPlayer()
        setupAudioSession()
    }

    // MARK: - Player Setup

    /// Initializes the AVQueuePlayer and registers necessary observers.
    private func setupPlayer() {
        player = AVQueuePlayer()

        // Setup periodic time observers.
        setupElapsedTimeObserver()
        setupTotalItemTimeObserver()
        observingElapsedTime()

        // Configure remote command center.
        configureRemoteCommandCenter()

        // Observe when a player item finishes playing.
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .sink { [weak self] notification in
                self?.playerItemDidFinish(notification)
            }
            .store(in: &cancellables)

        // Observe audio session interruptions.
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification,
                                             object: AVAudioSession.sharedInstance())
            .sink { [weak self] notification in
                self?.handleAudioSessionInterruption(notification)
            }
            .store(in: &cancellables)
    }

    /// Configures the AVAudioSession for background audio playback.
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("Error setting up audio session: \(error)")
            onPlaybackError?(error)
        }
    }

    /// Call this method frequently (or on a timer) to update the dynamic fields.
    func updateDynamicNowPlayingInfo(elapsedTime: TimeInterval, playbackRate: Float) {
        nowPlayingInfoDict[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedTime
        nowPlayingInfoDict[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate
        nowPlayingInfoDict[MPMediaItemPropertyPlaybackDuration] = totalTime
        DispatchQueue.main.async {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = self.nowPlayingInfoDict
        }
    }
    // MARK: - Time Observers

    /// Adds a periodic time observer to track and report playback progress.
    private func setupElapsedTimeObserver() {
        guard let player = player else { return }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self = self else { return }
            if self.shouldObserveElapsedTime {
                self.elapsedTimeObserver.send(time.seconds)
            }
        }
    }

    /// Observes the current item's total duration and sends updates.
    private func setupTotalItemTimeObserver() {
        guard let player = player else { return }
        player.publisher(for: \.currentItem?.duration)
            .sink { [weak self] duration in
                guard let duration = duration, duration.isNumeric else { return }
                self?.totalItemTimeObserver.send(duration.seconds)
                self?.totalTime = duration.seconds
            }
            .store(in: &cancellables)
    }

    /// Subscribes to elapsed time updates and updates the published elapsedTime.
    private func observingElapsedTime() {
        guard let player = player else { return }
        elapsedTimeObserver
            .sink { [weak self] time in
                guard let self = self, self.playbackStatePublisher.value == .playing else { return }
                self.elapsedTime = time
                updateDynamicNowPlayingInfo(elapsedTime: time, playbackRate: player.rate)
            }
            .store(in: &cancellables)
    }

    /// Removes the time observer and cancels Combine subscriptions.
    func tearDownTimeObservers() {
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        cancellables.removeAll()
    }

    func updatePlayerStatus(state: PlaybackState) {
        Task { @MainActor in
            self.playbackStatePublisher.send(state)
        }
    }

    deinit {
        tearDownTimeObservers()
        // Cancel any player item–related subscriptions.
        playerItemCancellables.removeAll()
        try? AVAudioSession.sharedInstance().setActive(false)
        URLCache.shared.removeAllCachedResponses()
    }

    // MARK: - Playback Controls

    /// Loads and begins playback of a given Video
    func play(item: VideoItem) {
        thumbnailFrames.removeAll()
        currentItem = item
        guard let finalURL = currentItem?.url else {
            let error = NSError(domain: "PodcastPlayer",
                                code: 404,
                                userInfo: [NSLocalizedDescriptionKey: "No valid URL for Video"])
            onPlaybackError?(error)
            return
        }

        let asset = AVURLAsset(url: finalURL)
        let newItem = AVPlayerItem(asset: asset)

//        updateStaticNowPlayingInfo()
        observePlayerItem(newItem)
        setPlayerItem(newItem)

        player?.play()
        generateThumbnailFrames()
        updatePlayerStatus(state: .playing)
        onPlaybackStatusChanged?(true)
        retryAttempt = 0
    }

    /// Pauses the current playback.
    func pause() {
        player?.pause()
        onPlaybackStatusChanged?(false)
        updatePlayerStatus(state: .paused)
    }

    /// Resumes playback.
    func resume() {
        player?.play()
        onPlaybackStatusChanged?(true)
        updatePlayerStatus(state: .playing)
    }

    /// Stops playback completely and cleans up the current player item.
    func stop() {
        player?.pause()
        // Clean up the current player item before replacing it.
        if let currentItem = player?.currentItem {
            cleanupPlayerItem(currentItem)
        }
        thumbnailFrames.removeAll()
        player?.replaceCurrentItem(with: nil)
        onPlaybackStatusChanged?(false)
        updatePlayerStatus(state: .stopped)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Seeks 15s forward by a default of 15 seconds.
    func seekFifteenForward() {
        guard let player = player else { return }
        let currentTime = player.currentTime()
        let newTime = CMTimeAdd(currentTime, CMTime(seconds: 15, preferredTimescale: currentTime.timescale))
        player.seek(to: newTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Seeks 15s  backward by a default of 10 seconds.
    func seekFifteenBackward() {
        guard let player = player else { return }
        let currentTime = player.currentTime()
        let newTime = CMTimeSubtract(currentTime, CMTime(seconds: 15, preferredTimescale: currentTime.timescale))
        player.seek(to: newTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Seeks forward by a default of 15 seconds.
    func seekForward(seconds: Double = 15) {
        guard let player = player else { return }
        let currentTime = player.currentTime()
        let newTime = CMTimeAdd(currentTime, CMTime(seconds: seconds, preferredTimescale: currentTime.timescale))
        player.seek(to: newTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Seeks backward by a default of 10 seconds.
    func seekBackward(seconds: Double = 15) {
        guard let player = player else { return }
        let currentTime = player.currentTime()
        let newTime = CMTimeSubtract(currentTime, CMTime(seconds: seconds, preferredTimescale: currentTime.timescale))
        player.seek(to: newTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Seeks to a specific time.
    func seek(to time: Double) {
        guard let player = player else { return }
        let targetTime = CMTime(seconds: time, preferredTimescale: 600)
        if playbackStatePublisher.value == .playing {
            shouldObserveElapsedTime = false
            self.playbackStatePublisher.send(.buffering)
            player.seek(to: targetTime) { [weak self] _ in
                guard let self = self else { return }
                self.updatePlayerStatus(state: .playing)
                self.shouldObserveElapsedTime = true
            }
        } else {
            player.seek(to: targetTime)
        }
    }

    func generateThumbnailFrames() {
        Task.detached { [weak self] in
            guard let self, let asset = await self.player?.currentItem?.asset else { return }
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

    /// Sets the playback speed.
    func setPlaybackRate(_ rate: Float) {
        player?.rate = rate
    }

    /// Configures the remote command center.
    func configureRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.player?.play()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.seekBackward()
            return .success
        }

        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.seekForward()
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self, let player = self.player,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let newTime = CMTime(seconds: positionEvent.positionTime, preferredTimescale: 600)
            player.seek(to: newTime)
            return .success
        }
    }

    // MARK: - Network Retry Strategy

    /// Attempts to retry playback with exponential backoff if a network error occurs.
    private func retryPlayback(for item: VideoItem) {
        guard retryAttempt < maxRetryAttempts else { return }
        let delay = pow(2.0, Double(retryAttempt))
        retryAttempt += 1
        print("Retrying playback in \(delay) seconds (attempt \(retryAttempt))")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.play(item: item)
        }
    }

    // MARK: - Player Item Observation & Cleanup

    /// Sets up Combine-based observation for the provided AVPlayerItem.
    private func observePlayerItem(_ item: AVPlayerItem) {
        // Observe status changes.
        item.publisher(for: \.status)
            .sink { [weak self, weak item] status in
                guard let self = self, let item = item else { return }
                switch status {
                case .readyToPlay:
                    self.retryAttempt = 0
                case .failed:
                    if let error = item.error {
                        self.onPlaybackError?(error)
                        if (error as NSError).code == -1009, let item = self.currentItem {
                            self.retryPlayback(for: item)
                        }
                    }
                default:
                    break
                }
            }
            .store(in: &playerItemCancellables)

        // Observe buffering start.
        item.publisher(for: \.isPlaybackBufferEmpty)
            .sink { isEmpty in
                if isEmpty {
                    print("Buffering started...")
                }
            }
            .store(in: &playerItemCancellables)

        // Observe buffering end.
        item.publisher(for: \.isPlaybackLikelyToKeepUp)
            .sink { isLikely in
                if isLikely {
                    print("Buffering ended...")
                }
            }
            .store(in: &playerItemCancellables)
    }

    /// Replaces the current player item after cleaning up its observers.
    private func setPlayerItem(_ newItem: AVPlayerItem?) {
        if let currentItem = player?.currentItem {
            cleanupPlayerItem(currentItem)
        }
        player?.replaceCurrentItem(with: newItem)
    }

    /// Cleans up Combine subscriptions associated with the player item.
    private func cleanupPlayerItem(_ item: AVPlayerItem) {
        playerItemCancellables.removeAll()
    }

    // MARK: - Notification Handlers

    /// Called when a player item finishes playback.
    @objc private func playerItemDidFinish(_ notification: Notification) {
        URLCache.shared.removeAllCachedResponses()
    }

    /// Handles audio session interruptions (e.g., phone calls, Siri).
    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        if type == .began {
            pause()
        } else if type == .ended,
                  let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                player?.play()
            }
        }
    }
}

extension VideoPlayer {
    /// Public computed property to get the current playback time in seconds.
    public var currentPlaybackTime: Double {
        guard let player = self.player else { return 0 }
        let currentCMTime = player.currentTime()
        if !currentCMTime.isValid {
            return 0
        }
        let seconds = CMTimeGetSeconds(currentCMTime)
        return (seconds.isNaN || seconds.isInfinite) ? 0 : seconds
    }
}

public enum PlaybackState: Int, Equatable {
    case waitingForSelection
    case buffering
    case playing
    case paused
    case stopped
    case waitingForConnection
}
