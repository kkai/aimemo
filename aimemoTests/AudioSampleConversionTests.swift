//
//  AudioSampleConversionTests.swift
//  aimemoTests
//
//  Pins the buffer-to-float conversion and amplitude math in AudioProcessor
//  and RealTimeWhisper ahead of the planned streaming refactor.
//
//  Mono only: the multi-channel path of convertPCMBufferToFloatArray and
//  decodePCMBuffer indexes `frame * channelCount + channel` off each channel
//  pointer, which over-reads for non-interleaved stereo. The app only ever
//  feeds mono buffers, so that latent bug is documented here, not exercised.
//

import Testing
@testable import aimemo

@MainActor
struct AudioSampleConversionTests {
  // Shared so the whisper tiny-model load in RealTimeWhisper.init runs once
  // for the whole suite.
  private static let whisper = RealTimeWhisper()

  // MARK: AudioProcessor.convertPCMBufferToFloatArray

  @Test func convertPCMBufferToFloatArrayRoundTripsMono() {
    let samples: [Float] = [0.1, -0.2, 0.3]
    let result = AudioProcessor().convertPCMBufferToFloatArray(
      buffer: TestAudioBuffers.mono(samples))
    #expect(result == samples)
  }

  @Test func convertHandlesEmptyBuffer() {
    let result = AudioProcessor().convertPCMBufferToFloatArray(
      buffer: TestAudioBuffers.mono([]))
    #expect(result.isEmpty)
  }

  // MARK: RealTimeWhisper.decodePCMBuffer

  @Test func modelLoadsFromHostAppBundle() {
    // Smoke test for findModelURL: init found and loaded the tiny model.
    #expect(Self.whisper.canTranscribe)
  }

  @Test func decodePCMBufferRoundTripsMono() throws {
    let samples: [Float] = [0.1, -0.2, 0.3]
    let result = try Self.whisper.decodePCMBuffer(TestAudioBuffers.mono(samples))
    #expect(result == samples)
  }

  @Test func decodePCMBufferClampsToUnitRange() throws {
    let result = try Self.whisper.decodePCMBuffer(
      TestAudioBuffers.mono([1.5, -2.0, 0.5]))
    #expect(result == [1.0, -1.0, 0.5])
  }

  @Test func decodePCMBufferEmptyGivesEmpty() throws {
    let result = try Self.whisper.decodePCMBuffer(TestAudioBuffers.mono([]))
    #expect(result.isEmpty)
  }

  // MARK: RealTimeWhisper.calculateAmplitude
  // Empty buffers are not tested: 0/0 -> NaN in the current implementation.

  @Test func amplitudeOfSilenceIsZero() {
    #expect(
      Self.whisper.calculateAmplitude(from: TestAudioBuffers.silence(frames: 1600)) == 0)
  }

  @Test func amplitudeScalesRMSTimesTen() {
    // RMS of constant 0.05 is 0.05; scaled x10 -> 0.5.
    let amplitude = Self.whisper.calculateAmplitude(
      from: TestAudioBuffers.constant(0.05, frames: 1600))
    #expect(abs(amplitude - 0.5) < 0.001)
  }

  @Test func amplitudeClampsAtOne() {
    // RMS of constant 0.5 is 0.5; scaled x10 -> 5, clamped to 1.
    let amplitude = Self.whisper.calculateAmplitude(
      from: TestAudioBuffers.constant(0.5, frames: 1600))
    #expect(amplitude == 1.0)
  }
}
