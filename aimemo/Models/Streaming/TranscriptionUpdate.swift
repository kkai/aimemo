//
//  TranscriptionUpdate.swift
//  aimemo
//
//  What a transcription session reports to the presentation layer
//

import Foundation

/// One stream, one switch. Replaces the 0.1s polling loop that used to mirror
/// `AppleSpeechRecognizer`'s state into `RealTimeWhisper`.
enum TranscriptionUpdate: Equatable, Sendable {
  case transcript(LiveTranscript)
  /// Meter level, batched by the capture adapter rather than sent per buffer.
  case level(Float)
  case detectedLanguage(String)
  case failed(message: String)
  /// The session ended by itself and cannot carry on; capture is off. The
  /// recorder should stop the take (keeping what was committed) and show why.
  case stopped(message: String)
}
