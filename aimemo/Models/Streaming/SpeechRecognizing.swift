//
//  SpeechRecognizing.swift
//  aimemo
//
//  The slice of AppleSpeechRecognizer the session depends on
//

import Foundation

/// What `AppleSpeechTranscriptionSession` needs from a recognizer, so the
/// session can be driven by a fake in tests. `SFSpeechRecognizer` needs a
/// microphone and authorization, neither of which a unit test has.
@MainActor
protocol SpeechRecognizing: AnyObject {
  /// Cumulative text for the current run. Cleared by `startRecording()`.
  var transcribedText: String { get }
  var isRecording: Bool { get }
  var audioLevels: [Float] { get }

  func requestAuthorization() async -> Bool
  func startRecording() throws
  func stopRecording()
  func setLanguage(_ locale: Locale)
}

extension AppleSpeechRecognizer: SpeechRecognizing {}
