//
//  PauseDetector.swift
//  aimemo
//
//  Mean-energy silence test used by the window commit policy
//

import AVFoundation
import Accelerate

/// Classifies a span of audio as speech or silence by mean energy.
///
/// Written for the upstream sample and unit-tested here since v2.3, but never
/// instantiated by the app until the streaming window needed it: the vendored
/// whisper.cpp predates whisper's own VAD API, and its `no_speech_thold` is
/// dead code, so pause detection has to happen in Swift.
///
/// A `struct` of immutable scalars, hence `Sendable` — it is read from the
/// audio render thread.
struct PauseDetector: Sendable {
  let energyThreshold: Float
  let sampleRate: Float
  let bufferDuration: TimeInterval

  init(energyThreshold: Float, sampleRate: Float, bufferDuration: TimeInterval) {
    self.energyThreshold = energyThreshold
    self.sampleRate = sampleRate
    self.bufferDuration = bufferDuration
  }

  /// Frameworks-free core, used by `TranscriptionWindow` per 20ms frame.
  func isPause(samples: ArraySlice<Float>) -> Bool {
    // An empty span carries no evidence of speech, so it reads as quiet.
    guard !samples.isEmpty else { return true }
    return AudioSamples.energy(of: samples) < energyThreshold
  }

  /// Buffer entry point retained for the capture path and the existing tests.
  /// Reads the channel data in place rather than copying it into an Array.
  func isPause(buffer: AVAudioPCMBuffer) -> Bool {
    guard let samples = buffer.floatChannelData?.pointee else {
      return false
    }
    let count = Int(buffer.frameLength)
    guard count > 0 else { return true }

    var meanEnergy: Float = 0
    vDSP_measqv(samples, 1, &meanEnergy, vDSP_Length(count))
    return meanEnergy < energyThreshold
  }
}
