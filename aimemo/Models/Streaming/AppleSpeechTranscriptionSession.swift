//
//  AppleSpeechTranscriptionSession.swift
//  aimemo
//
//  Adapts AppleSpeechRecognizer to the shared session protocol
//

import Foundation

/// Apple Speech behind the same seam as whisper.
///
/// Replaces the 0.1s polling loop that used to mirror the recogniser's state
/// into `RealTimeWhisper`. Two things fall out of that: the loop's up-to-100ms
/// staleness at stop is gone, and the final-flush guarantee now covers this
/// engine too rather than only whisper.
///
/// The vocabulary fits whisper better — `SFSpeechRecognizer` produces its own
/// cumulative partials and has no notion of a window — so partials map to the
/// provisional tail and the final result commits.
@MainActor
final class AppleSpeechTranscriptionSession: LiveTranscriptionSession {

  let updates: AsyncStream<TranscriptionUpdate>
  private let updateContinuation: AsyncStream<TranscriptionUpdate>.Continuation

  private let recognizer: AppleSpeechRecognizer
  private var transcript = LiveTranscript()
  private var mirror: Task<Void, Never>?

  init(options: TranscriptionOptions) {
    self.recognizer = AppleSpeechRecognizer()
    var sink: AsyncStream<TranscriptionUpdate>.Continuation!
    self.updates = AsyncStream(bufferingPolicy: .unbounded) { sink = $0 }
    self.updateContinuation = sink
    recognizer.setLanguage(AppleSpeechRecognizer.preferredLocale(for: options.language))
  }

  func start() async throws {
    guard await recognizer.requestAuthorization() else {
      updateContinuation.yield(
        .failed(message: "Speech recognition is off. Enable it in Settings to use Apple Speech."))
      throw SessionError.notAuthorized
    }
    try recognizer.startRecording()
    startMirroring()
  }

  /// Apple Speech exposes no stream, so its observable state is still polled —
  /// but only here, and the result no longer races the save path.
  private func startMirroring() {
    mirror = Task { @MainActor [weak self] in
      while let self, !Task.isCancelled, self.recognizer.isRecording {
        self.transcript.setProvisional(self.recognizer.transcribedText, confidence: 1)
        self.updateContinuation.yield(.transcript(self.transcript))
        self.updateContinuation.yield(.level(self.recognizer.audioLevels.last ?? 0))
        try? await Task.sleep(for: .milliseconds(100))
      }
    }
  }

  func pause() async {
    recognizer.stopRecording()
    commitWhatWasHeard()
  }

  func resume() async throws {
    try recognizer.startRecording()
    startMirroring()
  }

  func finish() async -> String {
    recognizer.stopRecording()
    mirror?.cancel()
    mirror = nil
    // Read after stopping, so the last partial is not lost to the poll interval.
    commitWhatWasHeard()
    updateContinuation.yield(.transcript(transcript))
    updateContinuation.finish()
    return transcript.committed
  }

  func cancel() async {
    recognizer.stopRecording()
    mirror?.cancel()
    mirror = nil
    updateContinuation.finish()
  }

  private func commitWhatWasHeard() {
    let heard = recognizer.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
    transcript.clearProvisional()
    guard !heard.isEmpty else { return }
    // The recogniser reports cumulatively, so this replaces rather than appends.
    transcript = LiveTranscript()
    transcript.commit(heard)
  }

  enum SessionError: Error { case notAuthorized }
}
