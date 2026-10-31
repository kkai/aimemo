//
//  SilenceWatch.swift
//  aimemo
//
//  Notices when a recording has had no audio at all for a while
//

import Foundation

/// "Recording" should be a claim the app can back up. This watches the meter
/// levels and reports when nothing above the noise floor of a live microphone
/// has arrived for `limit` seconds: a refused microphone, a capture that died,
/// or no level updates at all. A quiet room still registers above `floor`;
/// a dead input reads as exact zeros.
struct SilenceWatch: Sendable {
  /// Meter level (`AudioSamples.meterLevel`, RMS × 10) treated as no audio.
  /// 0.001 is about -80 dBFS, below any working microphone's self-noise.
  var floor: Float = 0.001
  var limit: TimeInterval = 5

  private var lastSound: Date?

  /// Starts the clock, at the start of a take or a resume.
  mutating func reset(at date: Date) {
    lastSound = date
  }

  mutating func record(level: Float, at date: Date) {
    if level > floor { lastSound = date }
  }

  /// Whether the input has been silent for longer than `limit`. Also true when
  /// levels stopped arriving, so it is checked on a timer, not only per level.
  func isSilent(at date: Date) -> Bool {
    guard let lastSound else { return false }
    return date.timeIntervalSince(lastSound) > limit
  }
}
