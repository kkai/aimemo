//
//  WhisperTranscriptionSession.swift
//  aimemo
//
//  Wires the microphone to the streaming core. No policy lives here.
//

import Foundation

/// Whisper engine session: `MicrophoneCapture` → `StreamingTranscriber` →
/// `updates`. Deliberately thin, because nothing in it can be unit-tested — the
/// microphone and the audio session only exist on a device.
@MainActor
final class WhisperTranscriptionSession: LiveTranscriptionSession {

  let updates: AsyncStream<TranscriptionUpdate>
  private let updateContinuation: AsyncStream<TranscriptionUpdate>.Continuation

  private let core: StreamingTranscriber
  private let capture: MicrophoneCapture
  private var forwarder: Task<Void, Never>?

  init(context: WhisperContext,
       options: TranscriptionOptions,
       policy: TranscriptionWindow.Policy = .default) {
    let core = StreamingTranscriber(transcriber: context, options: options, policy: policy)
    self.core = core

    var sink: AsyncStream<TranscriptionUpdate>.Continuation!
    self.updates = AsyncStream(bufferingPolicy: .unbounded) { sink = $0 }
    self.updateContinuation = sink

    let continuation = sink!
    self.capture = MicrophoneCapture(
      onSamples: { samples in core.ingest(samples) },
      onLevel: { level in continuation.yield(.level(level)) }
    )
  }

  func start() async throws {
    await core.start()
    // Forward the core's transcript events into this session's single stream.
    forwarder = Task { [core, updateContinuation] in
      for await update in core.updates {
        updateContinuation.yield(update)
      }
    }
    do {
      try await capture.start()
    } catch {
      updateContinuation.yield(.failed(message: Self.describe(error)))
      throw error
    }
  }

  func pause() async {
    await capture.stop()
    // Close the open window now: resuming would otherwise glue audio across the
    // discontinuity and whisper would hallucinate over the seam.
    await core.commitOpenWindow()
  }

  func resume() async throws {
    try await capture.start()
  }

  func finish() async -> String {
    await capture.stop()
    let final = await core.finish()
    await forwarder?.value
    forwarder = nil
    updateContinuation.finish()
    return final
  }

  func cancel() async {
    await capture.stop()
    await core.cancel()
    forwarder?.cancel()
    forwarder = nil
    updateContinuation.finish()
  }

  private static func describe(_ error: Error) -> String {
    if let error = error as? MicrophoneCapture.CaptureError {
      switch error {
      case .permissionDenied:
        return "Microphone access is off. Enable it in Settings to record."
      case .unsupportedInputFormat:
        return "The microphone is unavailable. Another app may be using it."
      }
    }
    return error.localizedDescription
  }
}
