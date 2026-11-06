//
//  MemoShortcuts.swift
//  aimemo
//
//  The phrases Siri and Spotlight know without any setup
//

import AppIntents

struct MemoShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: StartMemoIntent(),
      phrases: [
        "Start a memo in \(.applicationName)",
        "Start recording in \(.applicationName)",
        "New memo in \(.applicationName)",
        "Record a memo with \(.applicationName)",
      ],
      shortTitle: "Start a Memo",
      systemImageName: "mic.fill"
    )
    AppShortcut(
      intent: StopMemoIntent(),
      phrases: [
        "Stop the memo in \(.applicationName)",
        "Stop recording in \(.applicationName)",
      ],
      shortTitle: "Stop the Memo",
      systemImageName: "stop.fill"
    )
    AppShortcut(
      intent: TranscribeFileIntent(),
      phrases: [
        "Transcribe a file in \(.applicationName)",
        "Transcribe audio with \(.applicationName)",
      ],
      shortTitle: "Transcribe a File",
      systemImageName: "doc.text"
    )
  }
}
