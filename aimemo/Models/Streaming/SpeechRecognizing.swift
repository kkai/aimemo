//
//  SpeechRecognizing.swift
//  aimemo
//
//  The slice of AppleSpeechRecognizer the session depends on
//

import Foundation

/// How a recognition task ended when nobody asked it to stop.
enum SpeechRunEnd: Equatable, Sendable {
  /// The recognizer closed the run with a final result. Server recognition
  /// does this after about a minute.
  case finished
  /// An error ended the run.
  case failed(message: String)
}

/// What `AppleSpeechTranscriptionSession` needs from a recognizer, so the
/// session can be driven by a fake in tests. `SFSpeechRecognizer` needs a
/// microphone and authorization, neither of which a unit test has.
@MainActor
protocol SpeechRecognizing: AnyObject {
  /// Cumulative text for the current run. Cleared by `startRecording()` and
  /// `restartRecognition()`.
  var transcribedText: String { get }
  /// True while capture runs, including between a run ending by itself and
  /// the restart.
  var isRecording: Bool { get }
  var audioLevels: [Float] { get }
  /// Called when a run ends by itself while capture is still running. Not
  /// called for `stopRecording()`.
  var onRunEnded: ((SpeechRunEnd) -> Void)? { get set }
  /// Phrases to bias recognition toward, for runs started after setting it.
  var contextualStrings: [String] { get set }

  func requestAuthorization() async -> Bool
  func startRecording() throws
  /// Starts a new run on the running capture.
  func restartRecognition() throws
  func stopRecording()
  func setLanguage(_ locale: Locale)
}

extension AppleSpeechRecognizer: SpeechRecognizing {}
