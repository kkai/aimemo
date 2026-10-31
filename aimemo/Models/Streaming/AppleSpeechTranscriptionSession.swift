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
  private var restartPolicy = SpeechRestartPolicy()
  private let now: () -> Date

  init(options: TranscriptionOptions,
       recognizer: SpeechRecognizing? = nil,
       now: @escaping () -> Date = Date.init) {
    self.recognizer = recognizer ?? AppleSpeechRecognizer()
    self.now = now
    var sink: AsyncStream<TranscriptionUpdate>.Continuation!
    self.updates = AsyncStream(bufferingPolicy: .unbounded) { sink = $0 }
    self.updateContinuation = sink
    self.recognizer.setLanguage(AppleSpeechRecognizer.preferredLocale(for: options.language))
    // The setting that already steers whisper's prompt, for this engine too.
    self.recognizer.contextualStrings = options.contextualStrings
    self.recognizer.onRunEnded = { [weak self] end in self?.runEnded(end) }
  }

  func start() async throws {
    guard await recognizer.requestAuthorization() else {
      updateContinuation.yield(
        .failed(message: "Speech recognition is off. Enable it in Settings to use Apple Speech."))
      throw SessionError.notAuthorized
    }
    try recognizer.startRecording()
    openRun()
    startMirroring()
  }

  /// Apple Speech exposes no stream, so its observable state is still polled —
  /// but only here, and the result no longer races the save path.
  private func startMirroring() {
    mirror = Task { @MainActor [weak self] in
      var lastLevels: [Float] = []
      while let self, !Task.isCancelled, self.recognizer.isRecording {
        // Earlier runs as committed text, this run as the provisional tail.
        var shown = self.transcript
        shown.setProvisional(self.recognizer.transcribedText, confidence: 1)
        self.updateContinuation.yield(.transcript(shown))
        // Only fresh levels: repeating a stale one would hide a dead capture
        // from the "No audio" cue.
        let levels = self.recognizer.audioLevels
        if levels != lastLevels, let level = levels.last {
          self.updateContinuation.yield(.level(level))
          lastLevels = levels
        }
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
    openRun()
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

  private func openRun() {
    runIsOpen = true
    restartPolicy.runStarted(at: now())
  }

  /// The recognizer ended a run on its own while capture is still running:
  /// the server's one-minute limit, or an error. Commit what that run heard
  /// and start the next one on the same capture, so the take carries on with
  /// no gap and no repeated text. If restarting is hopeless, stop and say so,
  /// rather than leave the screen saying "Recording" over a dead recognizer.
  private func runEnded(_ end: SpeechRunEnd) {
    guard runIsOpen else { return }
    commitWhatWasHeard()
    updateContinuation.yield(.transcript(transcript))

    switch restartPolicy.runEnded(end, at: now()) {
    case .restart:
      do {
        try recognizer.restartRecognition()
        openRun()
      } catch {
        giveUp(SpeechRestartPolicy.message(forRestartError: error))
      }
    case .giveUp(let message):
      giveUp(message)
    }
  }

  /// Capture off, and the presentation layer told the take is over. The
  /// committed text stays; `finish()` still returns it.
  private func giveUp(_ message: String) {
    recognizer.stopRecording()
    mirror?.cancel()
    mirror = nil
    updateContinuation.yield(.stopped(message: message))
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
