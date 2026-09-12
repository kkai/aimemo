//
//  AudioSamplesTests.swift
//  aimemoTests
//
//  Pins the buffer-to-float conversion and amplitude math, now that both live
//  in AudioSamples rather than being duplicated across RealTimeWhisper,
//  AppleSpeechRecognizer and the (deleted) AudioProcessor.
//
//  Mono only: the multi-channel path indexes `frame * channelCount + channel`
//  off each channel pointer, which over-reads for non-interleaved stereo. The
//  app only ever feeds mono buffers, so that latent bug is documented here,
//  not exercised.
//
//  These assertions are carried over verbatim from AudioSampleConversionTests,
//  minus its shared `RealTimeWhisper()` instance — the suite used to load a
//  57MB whisper model just to reach two pure functions.
//

import AVFoundation
import Testing
@testable import aimemo

struct AudioSamplesTests {

  // MARK: floats(from:)

  @Test func floatsRoundTripMono() throws {
    let samples: [Float] = [0.1, -0.2, 0.3]
    #expect(try AudioSamples.floats(from: TestAudioBuffers.mono(samples)) == samples)
  }

  @Test func floatsClampToUnitRange() throws {
    let result = try AudioSamples.floats(from: TestAudioBuffers.mono([1.5, -2.0, 0.5]))
    #expect(result == [1.0, -1.0, 0.5])
  }

  @Test func floatsOfEmptyBufferAreEmpty() throws {
    #expect(try AudioSamples.floats(from: TestAudioBuffers.mono([])).isEmpty)
  }

  // MARK: meterLevel(from:)

  @Test func meterLevelOfSilenceIsZero() {
    #expect(AudioSamples.meterLevel(from: TestAudioBuffers.silence(frames: 1600)) == 0)
  }

  @Test func meterLevelScalesRMSTimesTen() {
    // RMS of constant 0.05 is 0.05; scaled x10 -> 0.5.
    let level = AudioSamples.meterLevel(from: TestAudioBuffers.constant(0.05, frames: 1600))
    #expect(abs(level - 0.5) < 0.001)
  }

  @Test func meterLevelClampsAtOne() {
    // RMS of constant 0.5 is 0.5; scaled x10 -> 5, clamped to 1.
    #expect(AudioSamples.meterLevel(from: TestAudioBuffers.constant(0.5, frames: 1600)) == 1.0)
  }

  @Test func meterLevelOfEmptyBufferIsZeroNotNaN() {
    // The previous implementation divided 0 by 0 here and returned NaN, which
    // would have propagated into the waveform view.
    let level = AudioSamples.meterLevel(from: TestAudioBuffers.mono([]))
    #expect(level == 0)
    #expect(!level.isNaN)
  }

  // MARK: energy(of:)

  @Test func energyOfSilenceIsZero() {
    #expect(AudioSamples.energy(of: [Float](repeating: 0, count: 800)[...]) == 0)
  }

  @Test func energyIsMeanSquare() {
    // Constant 0.5 -> mean square 0.25.
    let energy = AudioSamples.energy(of: [Float](repeating: 0.5, count: 800)[...])
    #expect(abs(energy - 0.25) < 1e-6)
  }

  @Test func energyOfEmptySliceIsZero() {
    #expect(AudioSamples.energy(of: [Float]()[...]) == 0)
  }

  @Test func energyMatchesPauseDetectorOnTheSameSignal() {
    // AudioSamples.energy and PauseDetector.isPause must agree on what
    // "quiet" means; the window commit policy depends on it.
    let quiet = [Float](repeating: 0.001, count: 1600)
    let detector = PauseDetector(energyThreshold: 0.01, sampleRate: 16000, bufferDuration: 0.1)
    #expect(AudioSamples.energy(of: quiet[...]) < 0.01)
    #expect(detector.isPause(buffer: TestAudioBuffers.mono(quiet)))
  }
}
