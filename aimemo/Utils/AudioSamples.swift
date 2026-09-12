//
//  AudioSamples.swift
//  aimemo
//
//  Pure buffer math shared by the capture and transcription paths
//

import AVFoundation
import Accelerate

/// Conversions between `AVAudioPCMBuffer` and the 16 kHz mono float samples
/// whisper.cpp requires.
///
/// Single home for logic that used to exist three times over: `RealTimeWhisper`
/// and `AppleSpeechRecognizer` carried byte-identical amplitude functions, and
/// `AudioProcessor` carried a near-identical, non-clamping converter that
/// nothing in the app ever called.
enum AudioSamples {

  /// Interleaved float samples, clamped to [-1, 1].
  ///
  /// Mono-correct. The multi-channel path indexes `frame * channelCount + channel`
  /// off the first channel pointer, which over-reads for non-interleaved stereo —
  /// a latent bug inherited from the upstream sample. The app only ever feeds
  /// mono, and `AudioSamplesTests` documents it rather than exercising it.
  static func floats(from buffer: AVAudioPCMBuffer) throws -> [Float] {
    guard let channelData = buffer.floatChannelData else {
      throw AudioSampleError.notFloatFormat
    }

    let channelCount = Int(buffer.format.channelCount)
    let frameLength = Int(buffer.frameLength)

    var floats = [Float]()
    floats.reserveCapacity(frameLength * channelCount)

    for frame in 0..<frameLength {
      for channel in 0..<channelCount {
        let index = frame * channelCount + channel
        floats.append(max(-1.0, min(channelData[channel][index], 1.0)))
      }
    }

    return floats
  }

  /// RMS x 10, clamped to 1 — the normalised level the waveform view draws.
  /// Empty buffers give 0 rather than the NaN the previous 0/0 produced.
  static func meterLevel(from buffer: AVAudioPCMBuffer) -> Float {
    guard let channelData = buffer.floatChannelData else { return 0 }
    let frameLength = Int(buffer.frameLength)
    guard frameLength > 0 else { return 0 }

    var meanSquare: Float = 0
    vDSP_measqv(channelData.pointee, vDSP_Stride(buffer.stride), &meanSquare, vDSP_Length(frameLength))

    return min(sqrt(meanSquare) * 10, 1.0)
  }

  /// Mean square (energy) of a sample slice — the quantity `PauseDetector`
  /// compares against its threshold.
  static func energy(of samples: ArraySlice<Float>) -> Float {
    guard !samples.isEmpty else { return 0 }
    var meanSquare: Float = 0
    samples.withUnsafeBufferPointer { buffer in
      guard let base = buffer.baseAddress else { return }
      vDSP_measqv(base, 1, &meanSquare, vDSP_Length(buffer.count))
    }
    return meanSquare
  }
}

enum AudioSampleError: Error {
  case notFloatFormat
}
