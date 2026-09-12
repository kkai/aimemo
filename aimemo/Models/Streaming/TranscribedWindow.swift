//
//  TranscribedWindow.swift
//  aimemo
//
//  One window's decode result
//

import Foundation

/// What a single window decode produced. Timings are window-relative:
/// whisper reports `t0`/`t1` from the start of the buffer it was handed
/// (whisper.cpp:5945), so the caller adds its own offset.
struct TranscribedWindow: Equatable, Sendable {

  struct Segment: Equatable, Sendable {
    let text: String
    /// Seconds from the start of the window.
    let start: TimeInterval
    let end: TimeInterval
    /// Mean `whisper_token_data.p` across the segment's tokens.
    let confidence: Float

    init(text: String, start: TimeInterval, end: TimeInterval, confidence: Float) {
      self.text = text
      self.start = start
      self.end = end
      self.confidence = confidence
    }
  }

  let segments: [Segment]
  let detectedLanguageCode: String?

  init(segments: [Segment], detectedLanguageCode: String? = nil) {
    self.segments = segments
    self.detectedLanguageCode = detectedLanguageCode
  }

  /// Concatenated, normalized segment text.
  var text: String {
    LiveTranscript.normalize(segments.map(\.text).joined())
  }

  /// Duration-weighted mean segment confidence.
  var confidence: Float {
    let weighted = segments.reduce(Float(0)) { $0 + $1.confidence * Float(max($1.end - $1.start, 0.001)) }
    let total = segments.reduce(Float(0)) { $0 + Float(max($1.end - $1.start, 0.001)) }
    return total > 0 ? weighted / total : 0
  }

  static let empty = TranscribedWindow(segments: [])
}
