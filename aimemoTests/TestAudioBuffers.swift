//
//  TestAudioBuffers.swift
//  aimemoTests
//
//  Helpers for constructing PCM buffers in tests.
//

import AVFoundation

enum TestAudioBuffers {
  /// Mono, non-interleaved Float32 PCM buffer from raw samples.
  static func mono(_ samples: [Float], sampleRate: Double = 16000) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
      channels: 1, interleaved: false)!
    let buffer = AVAudioPCMBuffer(
      pcmFormat: format, frameCapacity: AVAudioFrameCount(max(samples.count, 1)))!
    buffer.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { src in
      if let base = src.baseAddress, !samples.isEmpty {
        buffer.floatChannelData![0].update(from: base, count: samples.count)
      }
    }
    return buffer
  }

  static func silence(frames: Int, sampleRate: Double = 16000) -> AVAudioPCMBuffer {
    mono([Float](repeating: 0, count: frames), sampleRate: sampleRate)
  }

  static func constant(_ value: Float, frames: Int) -> AVAudioPCMBuffer {
    mono([Float](repeating: value, count: frames))
  }

  /// Sine wave of the given frequency and amplitude.
  static func sine(
    frequency: Float, amplitude: Float, frames: Int, sampleRate: Float = 16000
  ) -> AVAudioPCMBuffer {
    let samples = (0..<frames).map { i in
      amplitude * sin(2 * .pi * frequency * Float(i) / sampleRate)
    }
    return mono(samples, sampleRate: Double(sampleRate))
  }
}
