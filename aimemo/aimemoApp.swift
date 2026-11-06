//
//  aimemoApp.swift
//  aimemo
//
//  Created by kai on 13.09.25.
//

import SwiftUI
import SwiftData

@main
struct aimemoApp: App {
  @State private var audioProcessor: RealTimeWhisper
  private let modelContainer = LaunchOptions.makeModelContainer()

  init() {
    let recorder = LaunchOptions.makeRecorder()
    _audioProcessor = State(initialValue: recorder)
    // Siri and Shortcuts reach the recorder through the bridge.
    RecorderIntentBridge.shared.recorder = recorder
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(audioProcessor)
        .task { ReviewPrompt.registerLaunch() }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }
    .modelContainer(modelContainer)
  }
}
