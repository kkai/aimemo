//
//  MicrophoneCapture.swift
//  aimemo
//
//  AVAudioEngine capture, converted to whisper's format off the main thread
//

import AVFoundation

/// Owns the audio session, engine, tap and format converter.
///
/// An `actor`, so `setCategory`/`setActive` — tens of milliseconds each — run
/// off the main thread. The tap closure itself runs on the audio render thread
/// and touches only converter state and the two `@Sendable` handlers, so the
/// main thread does no per-buffer work at all. It previously did every
/// conversion, RMS and array copy inside `DispatchQueue.main.async`.
actor MicrophoneCapture {

  enum CaptureError: Error {
    case permissionDenied
    case unsupportedInputFormat
  }

  /// Whisper's required format: 16 kHz mono float32.
  private let outputFormat: AVAudioFormat

  private let engine = AVAudioEngine()
  #if os(iOS)
  private let session = AVAudioSession.sharedInstance()
  #endif

  private let onSamples: @Sendable ([Float]) -> Void
  private let onLevel: @Sendable (Float) -> Void

  /// Touched only from the audio render thread once capture starts.
  private nonisolated(unsafe) var converter: AVAudioConverter?

  private var isTapped = false

  init(onSamples: @escaping @Sendable ([Float]) -> Void,
       onLevel: @escaping @Sendable (Float) -> Void) {
    self.outputFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: 16000,
      channels: 1,
      interleaved: true
    )!
    self.onSamples = onSamples
    self.onLevel = onLevel
  }

  /// Awaits the permission prompt, rather than letting the UI enter "recording"
  /// while the system sheet is still up.
  static func requestPermission() async -> Bool {
    #if os(iOS)
    await withCheckedContinuation { continuation in
      AVAudioApplication.requestRecordPermission { granted in
        continuation.resume(returning: granted)
      }
    }
    #else
    true
    #endif
  }

  func start() async throws {
    #if os(iOS)
    guard await Self.requestPermission() else { throw CaptureError.permissionDenied }
    try session.setCategory(.playAndRecord, mode: .default)
    try session.setActive(true, options: .notifyOthersOnDeactivation)
    #endif

    let input = engine.inputNode
    let inputFormat = input.inputFormat(forBus: 0)
    guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
      // Happens when another app holds the microphone; the old code
      // force-unwrapped the converter here and crashed.
      throw CaptureError.unsupportedInputFormat
    }
    guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
      throw CaptureError.unsupportedInputFormat
    }
    self.converter = converter

    let outputFormat = self.outputFormat
    let onSamples = self.onSamples
    let onLevel = self.onLevel

    input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
      // Audio render thread. Nothing here hops to main.
      onLevel(AudioSamples.meterLevel(from: buffer))

      let ratio = outputFormat.sampleRate / buffer.format.sampleRate
      let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
      guard capacity > 0,
            let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity)
      else { return }

      var consumed = false
      var error: NSError?
      let status = converter.convert(to: out, error: &error) { _, outStatus in
        // The converter asks repeatedly; feeding the same buffer twice would
        // duplicate audio, so report endOfStream after the first hand-off.
        if consumed {
          outStatus.pointee = .noDataNow
          return nil
        }
        consumed = true
        outStatus.pointee = .haveData
        return buffer
      }

      guard status != .error, out.frameLength > 0 else {
        if let error { print("Audio conversion failed: \(error)") }
        return
      }

      if let samples = try? AudioSamples.floats(from: out), !samples.isEmpty {
        onSamples(samples)
      }
    }
    isTapped = true

    engine.prepare()
    try engine.start()
  }

  func stop() {
    if engine.isRunning { engine.stop() }
    if isTapped {
      engine.inputNode.removeTap(onBus: 0)
      isTapped = false
    }
    converter = nil
    #if os(iOS)
    // The whisper path never used to release the session, so stopping a
    // recording left .playAndRecord active and other apps ducked.
    try? session.setActive(false, options: .notifyOthersOnDeactivation)
    #endif
  }
}
