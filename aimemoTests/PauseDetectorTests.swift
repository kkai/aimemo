//
//  PauseDetectorTests.swift
//  aimemoTests
//
//  Characterization tests for the mean-energy pause detection math.
//

import Testing
@testable import aimemo

struct PauseDetectorTests {
  private func makeDetector(threshold: Float) -> PauseDetector {
    PauseDetector(energyThreshold: threshold, sampleRate: 16000, bufferDuration: 0.1)
  }

  @Test func silenceIsPause() {
    let detector = makeDetector(threshold: 0.01)
    #expect(detector.isPause(buffer: TestAudioBuffers.silence(frames: 1600)))
  }

  @Test func loudSignalIsNotPause() {
    // Constant 0.5 -> mean energy 0.25, well above threshold 0.01.
    let detector = makeDetector(threshold: 0.01)
    #expect(!detector.isPause(buffer: TestAudioBuffers.constant(0.5, frames: 1600)))
  }

  @Test func energyExactlyAtThresholdIsNotPause() {
    // Constant 0.5 -> mean energy exactly 0.25 (0.5^2 and its mean are
    // binary-exact in Float, unlike 0.1^2); comparison is strict `<`.
    let detector = makeDetector(threshold: 0.25)
    #expect(!detector.isPause(buffer: TestAudioBuffers.constant(0.5, frames: 1600)))
  }

  @Test func quietSignalBelowThresholdIsPause() {
    // Constant 0.05 -> mean energy 0.0025, below threshold 0.01.
    let detector = makeDetector(threshold: 0.01)
    #expect(detector.isPause(buffer: TestAudioBuffers.constant(0.05, frames: 1600)))
  }

  @Test func sineWaveEnergyMatchesTheory() {
    // Full-scale sine -> mean energy amplitude^2 / 2 = 0.5.
    let buffer = TestAudioBuffers.sine(frequency: 440, amplitude: 1.0, frames: 16000)
    #expect(!makeDetector(threshold: 0.4).isPause(buffer: buffer))
    #expect(makeDetector(threshold: 0.6).isPause(buffer: buffer))
  }

  // MARK: - Slice API
  //
  // TranscriptionWindow classifies 20ms frames through isPause(samples:).
  // It must agree with the buffer path it was factored out of.

  @Test func sliceAndBufferAgreeOnTheSameSignal() {
    let detector = makeDetector(threshold: 0.01)
    for value in [Float(0), 0.001, 0.05, 0.1, 0.5] {
      let samples = [Float](repeating: value, count: 1600)
      #expect(detector.isPause(samples: samples[...])
              == detector.isPause(buffer: TestAudioBuffers.mono(samples)),
              "disagreement at amplitude \(value)")
    }
  }

  @Test func sliceSilenceIsPause() {
    #expect(makeDetector(threshold: 0.01).isPause(samples: [Float](repeating: 0, count: 320)[...]))
  }

  @Test func sliceLoudSignalIsNotPause() {
    #expect(!makeDetector(threshold: 0.01).isPause(samples: [Float](repeating: 0.5, count: 320)[...]))
  }

  @Test func emptySliceReadsAsPause() {
    // No evidence of speech; the window treats it as quiet rather than
    // starting a segment on it.
    #expect(makeDetector(threshold: 0.01).isPause(samples: [Float]()[...]))
  }

  @Test func sliceRespectsOffsetIntoItsBase() {
    // ArraySlice indices are base-relative; the detector must read the slice,
    // not the first N elements of the underlying array.
    let signal = [Float](repeating: 0.5, count: 320) + [Float](repeating: 0, count: 320)
    let detector = makeDetector(threshold: 0.01)
    #expect(!detector.isPause(samples: signal[0..<320]))
    #expect(detector.isPause(samples: signal[320..<640]))
  }

  @Test func detectorIsSendableValueType() {
    // It is captured by the audio render thread; copies must be independent.
    let detector = makeDetector(threshold: 0.01)
    let copy = detector
    #expect(copy.energyThreshold == detector.energyThreshold)
  }
}

