//
//  StartMemoIntent.swift
//  aimemo
//
//  "Start a memo": Siri, Shortcuts, Spotlight and the Action button
//

import AppIntents
import Foundation

struct StartMemoIntent: AppIntent {
  static let title: LocalizedStringResource = "Start a Memo"
  static let description = IntentDescription(
    "Opens the app and starts recording a new memo.")
  /// Capture needs the foreground: iOS will not start the microphone for a
  /// backgrounded app without an audio background mode.
  static let openAppWhenRun = true

  @MainActor
  func perform() async throws -> some IntentResult {
    RecorderIntentBridge.shared.request(.startRecording)
    return .result()
  }
}
