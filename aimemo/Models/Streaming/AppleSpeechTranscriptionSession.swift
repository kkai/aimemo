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

  private let recognizer: SpeechRecognizing
  /// Text from runs that have ended. The recogniser restarts from empty on
  /// every `startRecording()`, so each run's text is committed once, on pause
  /// or finish, and appended here.
  private var transcript = LiveTranscript()
  /// True between a start/resume and the pause/finish that commits that run.
  private var runIsOpen = false
  private var mirror: Task<Void, Never>?

  init(options: TranscriptionOptions,
       recognizer: SpeechRecognizing? = nil) {
    self.recognizer = recognizer ?? AppleSpeechRecognizer()
    var sink: AsyncStream<TranscriptionUpdate>.Continuation!
    self.updates = AsyncStream(bufferingPolicy: .unbounded) { sink = $0 }
    self.updateContinuation = sink
    self.recognizer.setLanguage(AppleSpeechRecognizer.preferredLocale(for: options.language))
  }

  func start() async throws {
    guard await recognizer.requestAuthorization() else {
      updateContinuation.yield(
        .failed(message: "Speech recognition is off. Enable it in Settings to use Apple Speech."))
      throw SessionError.notAuthorized
    }
    try recognizer.startRecording()
    runIsOpen = true
    startMirroring()
  }

  /// Apple Speech exposes no stream, so its observable state is still polled —
  /// but only here, and the result no longer races the save path.
  private func startMirroring() {
    mirror = Task { @MainActor [weak self] in
      while let self, !Task.isCancelled, self.recognizer.isRecording {
        // Earlier runs as committed text, this run as the provisional tail.
        var shown = self.transcript
        shown.setProvisional(self.recognizer.transcribedText, confidence: 1)
        self.updateContinuation.yield(.transcript(shown))
        self.updateContinuation.yield(.level(self.recognizer.audioLevels.last ?? 0))
        try? await Task.sleep(for: .milliseconds(100))
      }
    }
  }

  func pause() async {
    recognizer.stopRecording()
    mirror?.cancel()
    mirror = nil
    commitWhatWasHeard()
    updateContinuation.yield(.transcript(transcript))
  }

  func resume() async throws {
    try recognizer.startRecording()
    runIsOpen = true
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

  /// Appends the run that just ended. The recogniser's text is cumulative
  /// within a run only; it used to replace the whole transcript here, so
  /// anything said before a pause was lost at the next pause or at finish.
  /// Guarded, because the recogniser keeps its text after stopping: a pause
  /// followed by finish would otherwise commit the same run twice.
  private func commitWhatWasHeard() {
    transcript.clearProvisional()
    guard runIsOpen else { return }
    runIsOpen = false
    transcript.commit(recognizer.transcribedText)
  }

  enum SessionError: Error { case notAuthorized }
}
