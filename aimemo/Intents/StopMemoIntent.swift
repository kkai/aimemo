//
//  StopMemoIntent.swift
//  aimemo
//
//  "Stop the memo": ends the take and hands the transcript to the shortcut
//

import AppIntents
import Foundation

struct StopMemoIntent: AppIntent {
  static let title: LocalizedStringResource = "Stop the Memo"
  static let description = IntentDescription(
    "Stops the memo being recorded and returns its transcript, so a shortcut can send it on.")
  /// Runs where the recording is, without bringing the app forward.
  static let openAppWhenRun = false

  enum Failure: Error, CustomLocalizedStringResourceConvertible {
    case notRecording
    var localizedStringResource: LocalizedStringResource { "No memo is being recorded." }
  }

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
    guard let recorder = RecorderIntentBridge.shared.recorder, recorder.canStop else {
      throw Failure.notRecording
    }
    await recorder.stopRecord()
    let transcript = recorder.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
    let dialog: IntentDialog = transcript.isEmpty
      ? "Memo stopped. Nothing was transcribed."
      : "Memo stopped."
    return .result(value: transcript, dialog: dialog)
  }
}
