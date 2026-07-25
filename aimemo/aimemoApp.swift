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
  @State private var audioProcessor = RealTimeWhisper()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(audioProcessor)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }
    .modelContainer(for: Recording.self)
  }
}
