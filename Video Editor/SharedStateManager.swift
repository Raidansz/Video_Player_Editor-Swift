//
//  SharedStateManager.swift
//  SquareCast
//
//  Created by Raidan on 2025. 02. 24..
//

import Foundation
import Combine

class PlaybackQueue: ObservableObject {
    @Published private(set) var feedId: String?
    @Published private(set) var items: [VideoItem]?
    @Published private(set) var currentIndex: Int?

    var currentItem: VideoItem? {
        guard let currentIndex, let items else { return nil }
        return items[currentIndex]
    }

    static let shared = PlaybackQueue()

    private init() {}

    func setPlaybackQueue(for feedId: String, items: [VideoItem], startIndex: Int? = 0) {
        if feedId != self.feedId {
            self.items = items
            currentIndex = startIndex
        }
    }

    func updateCurrentIndex(to_ newValue: Int) -> Bool {
        guard let items else { return false }
        if 0 <= newValue && newValue < items.count - 1 {
            currentIndex = newValue
            return true
        }
        return false
    }

    func cleanupQueue() {
        feedId = nil
        currentIndex = nil
        items = nil
    }
}
