//
//  ContentView.swift
//  aimemo
//
//  NavigationSplitView wrapper for adaptive sidebar navigation
//

import SwiftUI
import SwiftData

struct ContentView: View {
  @Environment(RealTimeWhisper.self) var audioProcessor
  @Environment(\.modelContext) private var modelContext
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  @State private var selectedRecording: Recording?
  @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
  @State private var showingHistory = false

  var body: some View {
    Group {
      if horizontalSizeClass == .compact {
        // iPhone: Use NavigationStack with sheet for history
        NavigationStack {
          RecordingView()
            .navigationDestination(for: Recording.self) { recording in
              RecordingDetailView(recording: recording)
            }
            .toolbar {
              ToolbarItem(placement: .navigationBarLeading) {
                Button {
                  showingHistory = true
                } label: {
                  Label("History", systemImage: "folder")
                }
              }
            }
            .sheet(isPresented: $showingHistory) {
              NavigationStack {
                RecordingsListView()
                  .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                      Button("Done") {
                        showingHistory = false
                      }
                    }
                  }
              }
            }
        }
      } else {
        // iPad: Use NavigationSplitView with sidebar
        NavigationSplitView(columnVisibility: $columnVisibility) {
          RecordingsListView()
            .navigationSplitViewColumnWidth(min: 300, ideal: 350, max: 400)
        } detail: {
          if let recording = selectedRecording {
            RecordingDetailView(recording: recording)
          } else {
            RecordingView()
              .navigationDestination(for: Recording.self) { recording in
                RecordingDetailView(recording: recording)
              }
          }
        }
      }
    }
    .onAppear {
      // Inject modelContext into audioProcessor for auto-save
      audioProcessor.modelContext = modelContext
    }
  }
}

#Preview {
  ContentView()
    .modelContainer(for: Recording.self, inMemory: true)
}
