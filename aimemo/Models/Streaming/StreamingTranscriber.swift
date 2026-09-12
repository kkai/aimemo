//
//  StreamingTranscriber.swift
//  aimemo
//
//  Audio backlog, window commit policy, decode invocation and stitching
//

import Foundation

/// Turns a stream of 16 kHz mono samples into a transcript, one bounded window
/// at a time.
///
/// Single-use: one instance per recording. That is deliberate — the previous
/// pipeline leaked the last take's transcript into the next one because reset
/// code is easy to forget to extend. A fresh object cannot forget.
///
/// Knows nothing about AVFoundation or whisper, so it is driven in tests by
/// synthesized `[Float]` and a fake `WindowTranscribing`.
actor StreamingTranscriber {

  private let transcriber: WindowTranscribing
  private let options: TranscriptionOptions

  private var window: TranscriptionWindow
  private var transcript = LiveTranscript()

  /// Ordered hand-off from the audio thread. `yield` is lock-based and
  /// FIFO; a `Task { await … }` per callback would not preserve order, and
  /// reordered audio is corrupt audio.
  private nonisolated let sampleContinuation: AsyncStream<[Float]>.Continuation
  private nonisolated let sampleStream: AsyncStream<[Float]>

  private nonisolated let updateContinuation: AsyncStream<TranscriptionUpdate>.Continuation
  /// Single-consumer stream of transcript and language events.
  nonisolated let updates: AsyncStream<TranscriptionUpdate>

  private var pump: Task<Void, Never>?
  private var isCancelled = false
  private var reportedLanguage = false

  init(transcriber: WindowTranscribing,
       options: TranscriptionOptions,
       policy: TranscriptionWindow.Policy = .default) {
    self.transcriber = transcriber
    self.options = options
    self.window = TranscriptionWindow(policy: policy)

    var sampleSink: AsyncStream<[Float]>.Continuation!
    self.sampleStream = AsyncStream(bufferingPolicy: .unbounded) { sampleSink = $0 }
    self.sampleContinuation = sampleSink

    var updateSink: AsyncStream<TranscriptionUpdate>.Continuation!
    self.updates = AsyncStream(bufferingPolicy: .unbounded) { updateSink = $0 }
    self.updateContinuation = updateSink
  }

  // MARK: - Input

  /// Ordered, non-blocking hand-off. Synchronous and `nonisolated` so the
  /// audio render thread never waits on the actor.
  nonisolated func ingest(_ samples: [Float]) {
    guard !samples.isEmpty else { return }
    sampleContinuation.yield(samples)
  }

  /// Begins consuming ingested audio.
  func start() {
    guard pump == nil else { return }
    pump = Task { [weak self] in
      guard let self else { return }
      for await chunk in self.sampleStream {
        await self.handle(chunk)
      }
    }
  }

  private func handle(_ chunk: [Float]) async {
    guard !isCancelled else { return }
    var decision = window.append(chunk)
    // One chunk can fill more than one window when decoding fell behind, and
    // the backlog carried over by close() may already form the next.
    while case .commit(let reason) = decision {
      await decodeAndCommit(window.close(reason: reason))
      decision = window.append([])
    }
  }

  // MARK: - Decoding

  private func decodeAndCommit(_ closed: TranscriptionWindow.Closed) async {
    do {
      let prompt = transcript.promptTail()
      var result = try await transcriber.transcribe(
        window: closed.samples,
        prompt: prompt,
        options: options,
        isPreview: false
      )

      // A seeded prompt can suppress the decode entirely: whisper may emit EOT
      // immediately when the prompt already reads like the audio it is given.
      // Observed with repeated phrasing. Losing a window of speech is far worse
      // than losing its context, so retry once unprompted.
      if result.text.isEmpty, prompt != nil {
        result = try await transcriber.transcribe(
          window: closed.samples,
          prompt: nil,
          options: options,
          isPreview: false
        )
      }

      transcript.commit(result.text)

      if let language = result.detectedLanguageCode, !reportedLanguage {
        reportedLanguage = true
        updateContinuation.yield(.detectedLanguage(language))
      }
    } catch {
      // One bad window must not wedge the pipeline: the window is already
      // closed, so the next one still decodes. This is the failure mode the
      // old `canTranscribe` flag turned into a permanent lockout.
      updateContinuation.yield(.failed(message: error.localizedDescription))
    }
    updateContinuation.yield(.transcript(transcript))
  }

  // MARK: - Lifecycle

  /// Force-commits the open window without tearing the object down, so audio
  /// either side of a pause is never glued across the discontinuity.
  func commitOpenWindow() async {
    while case .commit(let reason) = window.prepareFlush() {
      await decodeAndCommit(window.close(reason: reason))
    }
  }

  /// Decodes everything still buffered and returns the complete final text.
  ///
  /// Callers must await this before persisting: it is what guarantees the last
  /// words of a recording reach the saved transcript. Returning the text rather
  /// than leaving it on a property makes reading a stale value unrepresentable.
  func finish() async -> String {
    sampleContinuation.finish()

    if let pump {
      // Finishing the continuation ends the pump's for-await once it has
      // drained every chunk already yielded, so awaiting it is the guarantee
      // that all ingested audio has been handled.
      await pump.value
    } else {
      // Never started: drain here so ingest-then-finish still works.
      for await chunk in sampleStream {
        await handle(chunk)
      }
    }
    pump = nil

    await commitOpenWindow()

    updateContinuation.yield(.transcript(transcript))
    updateContinuation.finish()
    return transcript.committed
  }

  /// Drops buffered audio and aborts in-flight work. No final decode.
  func cancel() {
    isCancelled = true
    transcriber.abortInFlight()
    sampleContinuation.finish()
    pump?.cancel()
    pump = nil
    updateContinuation.finish()
  }

  // MARK: - Inspection (tests)

  var currentTranscript: LiveTranscript { transcript }
}
