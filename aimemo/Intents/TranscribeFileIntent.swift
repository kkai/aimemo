//
//  TranscribeFileIntent.swift
//  aimemo
//
//  "Transcribe a file": a Shortcuts action that takes any audio or video
//

import AppIntents
import Foundation
import UniformTypeIdentifiers

struct TranscribeFileIntent: AppIntent {
  static let title: LocalizedStringResource = "Transcribe a File"
  static let description = IntentDescription(
    "Opens the app and transcribes an audio or video file with Whisper, on the device.")
  static let openAppWhenRun = true

  @Parameter(title: "File", supportedContentTypes: [.audio, .movie])
  var file: IntentFile

  static var parameterSummary: some ParameterSummary {
    Summary("Transcribe \(\.$file)")
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    // The shortcut's file may be in memory only; give it a name and a path.
    let name = file.filename.isEmpty ? "Shortcut audio" : file.filename
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("Imports", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent(name)
    try file.data.write(to: url)
    RecorderIntentBridge.shared.request(.transcribe(ImportedFile(url: url, displayName: name)))
    return .result()
  }
}
