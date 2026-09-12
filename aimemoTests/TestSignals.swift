//
//  TestSignals.swift
//  aimemoTests
//
//  Synthesized 16 kHz mono [Float] for driving the streaming core without a
//  microphone or a model.
//

import Foundation

enum TestSignals {
  static let sampleRate: Double = 16_000

  static func samples(seconds: Double) -> Int {
    Int((sampleRate * seconds).rounded())
  }

  /// Digital silence.
  static func silence(seconds: Double) -> [Float] {
    [Float](repeating: 0, count: samples(seconds: seconds))
  }

  /// Low-level room tone — below any sane speech threshold, but not zero.
  static func roomTone(seconds: Double, amplitude: Float = 0.0005) -> [Float] {
    var generator = SystemRandomNumberGenerator()
    return (0..<samples(seconds: seconds)).map { _ in
      Float.random(in: -amplitude...amplitude, using: &generator)
    }
  }

  /// Speech-like: loud enough to clear the threshold by orders of magnitude.
  static func speech(seconds: Double, amplitude: Float = 0.3) -> [Float] {
    let count = samples(seconds: seconds)
    return (0..<count).map { i in
      let t = Double(i) / sampleRate
      // Two tones plus a slow envelope, so energy never sits exactly at zero.
      let carrier = sin(2 * .pi * 180 * t) + 0.5 * sin(2 * .pi * 440 * t)
      let envelope = 0.7 + 0.3 * sin(2 * .pi * 3 * t)
      return Float(carrier * envelope) * amplitude
    }
  }

  /// Feeds a signal through `body` in fixed-size chunks, as a tap would.
  static func feed(_ signal: [Float], chunk: Int, _ body: ([Float]) -> Void) {
    var index = 0
    while index < signal.count {
      let end = min(index + chunk, signal.count)
      body(Array(signal[index..<end]))
      index = end
    }
  }
}
