//
//  TranscriptSegment.swift
//  aimemo
//
//  One stretch of speech with its position in the recording
//

import Foundation

/// A timed piece of the transcript. `start` and `end` are seconds of
/// recorded audio from the beginning of the take; paused stretches do not
/// count, which matches the elapsed timer and the saved duration.
///
/// Whisper reports segment times relative to the window it decoded, so the
/// streaming core adds the window's offset; Apple Speech reports them relative
/// to each recognition run, so that session adds the run's offset. Either way
/// the result is one timeline, which is what SRT and VTT need.
struct TranscriptSegment: Codable, Equatable, Sendable {
  var text: String
  var start: TimeInterval
  var end: TimeInterval

  init(text: String, start: TimeInterval, end: TimeInterval) {
    self.text = text
    self.start = start
    self.end = max(end, start)
  }

  /// Segments decoded from one window, shifted onto the recording's timeline.
  /// Non-speech markers (`[BLANK_AUDIO]`, `(music)`) are dropped here, as
  /// `LiveTranscript.normalize` drops them from the text.
  static func fromWindow(_ window: TranscribedWindow, offset: TimeInterval) -> [TranscriptSegment] {
    window.segments.compactMap { segment in
      let text = LiveTranscript.normalize(segment.text)
      guard !text.isEmpty else { return nil }
      return TranscriptSegment(text: text, start: offset + segment.start, end: offset + segment.end)
    }
  }
}
