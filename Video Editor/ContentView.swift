//
//  ContentView.swift
//  Video Editor
//
//  Created by Raidan on 2025. 03. 01..
//

import PhotosUI
import SwiftUI

// MARK: - Main Content View
struct ContentView: View {
    @State private var shouldNavigateToEditor = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var loadState = LoadState.unknown
    
    var body: some View {
        NavigationStack {
            VStack {
                PhotosPicker(selection: $selectedItem, matching: .videos) {
                    Text("Select a video! 🤩")
                }
            }
            .navigationDestination(isPresented: $shouldNavigateToEditor) {
                VideoEditorRouter(loadState: $loadState)
            }
            .onChange(of: selectedItem) {
                if let item = selectedItem {
                    Task {
                        loadState = .loading
                        if let item = try? await item.loadTransferable(type: VideoItem.self) {
                            loadState = .loaded(item)
                            shouldNavigateToEditor = true
                        } else {
                            loadState = .failed
                        }
                    }
                }
            }
        }
    }
}
