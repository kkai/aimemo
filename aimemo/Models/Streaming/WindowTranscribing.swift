//
//  WindowTranscribing.swift
//  aimemo
//
//  The streaming core's only dependency on an ASR engine
//

import Foundation

/// Decodes one self-contained audio window.
///
/// This protocol is the seam that lets `StreamingTranscriber` be tested without
/// whisper, without a model, and without a microphone — and the seam a future
/// file-import feature plugs into unchanged.
protocol WindowTranscribing: Sendable {
  /// - Parameters:
  ///   - window: 16 kHz mono float samples. Must be at least 1000ms; whisper
  ///     silently returns zero segments below that (whisper.cpp:5253-5259).
  ///   - prompt: committed tail, seeded as `prompt_tokens` for continuity.
  ///   - isPreview: reserved for cheaper throwaway passes over the open window.
  ///     Always false today; kept in the signature so previews can be added
  ///     without touching every call site.
  func transcribe(
    window: [Float],
    prompt: String?,
    options: TranscriptionOptions,
    isPreview: Bool
  ) async throws -> TranscribedWindow

  /// Signals the in-flight decode to stop.
  ///
  /// Must be `nonisolated`: an actor-isolated cancel would queue behind the
  /// very decode it is trying to interrupt.
  nonisolated func abortInFlight()
}
