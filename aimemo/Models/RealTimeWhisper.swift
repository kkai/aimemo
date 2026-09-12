//
//  RealTimeWhisper.swift
//  aimemo
//
//  Presentation adapter over a LiveTranscriptionSession
//

import AVFoundation
import SwiftData
import SwiftUI

/// Observable state for the recording screen, and the recording lifecycle.
///
/// Everything that used to make this class risky now lives elsewhere: audio
/// capture in `MicrophoneCapture`, windowing and stitching in
/// `StreamingTranscriber`, decode in `WhisperContext`. What is left is a state
/// machine, some published properties, and the save.
///
/// `@MainActor`, so every `@Observable` mutation is on one thread by
/// construction rather than by convention — the previous version wrote
/// `transcribedText` from the cooperative pool while SwiftUI read it on main.
@MainActor
@Observable
final class RealTimeWhisper {

  enum State: Equatable, Sendable {
    case idle
    case recording
    case paused
    /// Flushing the final window. A second tap must not start a new recording
    /// on top of the old one.
    case stopping
  }

  // MARK: - Observable state

  private(set) var state: State = .idle
  /// True while a recording is in progress; drives the record button.
  var canStop: Bool { state == .recording || state == .paused }
  /// True while the final flush is running.
  var isBusy: Bool { state == .stopping }

  /// Committed text. This is what gets saved, copied and shared.
  var transcribedText = ""
  /// The window still being decoded, rendered dimmed.
  private(set) var provisionalText = ""
  private(set) var provisionalConfidence: Float = 0
  /// Committed plus provisional, for display.
  var displayText: String {
    provisionalText.isEmpty ? transcribedText
      : LiveTranscript.join(transcribedText, provisionalText)
  }

  var audioLevels: [Float] = []
  var elapsedTime: TimeInterval = 0
  private(set) var detectedLanguageCode: String?
  private(set) var errorMessage: String?

  /// "A model is loaded." Nothing more — the old flag doubled as a
  /// transcription mutex and could wedge itself false forever.
  private(set) var canTranscribe = false

  var currentModel: WhisperModel = .selected
  var currentEngine: TranscriptionEngine = .selected
  var modelContext: ModelContext?

  // MARK: - Collaborators

  private let loader: WhisperModelLoader
  private let makeSession: (TranscriptionEngine, TranscriptionOptions, WhisperContext?)
    -> LiveTranscriptionSession
  private var whisperContext: WhisperContext?

  private var session: LiveTranscriptionSession?
  private var consumer: Task<Void, Never>?

  /// Options in force for the current take, snapshotted at start so changing
  /// Settings mid-recording cannot switch language part-way through.
  private var activeOptions: TranscriptionOptions = .current

  private let maxAudioLevels = 100
  private var recordingStartTime: Date?
  /// Elapsed time accumulated before the current run, so pause is honest.
  private var elapsedBase: TimeInterval = 0
  private var segmentStart: Date?
  private var timerTask: Task<Void, Never>?

  // MARK: - Init

  init(
    loader: WhisperModelLoader = WhisperModelLoader(),
    makeSession: (
      (TranscriptionEngine, TranscriptionOptions, WhisperContext?) -> LiveTranscriptionSession
    )? = nil
  ) {
    self.loader = loader
    self.makeSession = makeSession ?? { engine, options, context in
      switch engine {
      case .whisper:
        // A missing context is prevented by the guard in start().
        return WhisperTranscriptionSession(context: context!, options: options)
      case .appleSpeech:
        return AppleSpeechTranscriptionSession(options: options)
      }
    }

    let selected = WhisperModel.selected
    do {
      whisperContext = try loader.makeContext(for: selected)
      currentModel = selected
      canTranscribe = true
    } catch {
      print("Error loading model: \(error.localizedDescription)")
    }
  }

  // MARK: - Model

  func loadModel(_ model: WhisperModel) async throws {
    // Swapping the context under a live decode loop would free it mid-flight.
    guard state == .idle else { throw ModelError.busy }
    whisperContext = try loader.makeContext(for: model)
    currentModel = model
    canTranscribe = true
  }

  enum ModelError: LocalizedError {
    case busy
    case notLoaded

    var errorDescription: String? {
      switch self {
      case .busy: return "Stop the recording before changing model."
      case .notLoaded: return "No transcription model is loaded."
      }
    }
  }

  // MARK: - Lifecycle

  func start() async {
    guard state == .idle else { return }

    if currentEngine == .whisper && whisperContext == nil {
      errorMessage = ModelError.notLoaded.errorDescription
      return
    }

    // Everything per-take is reset in one place, so adding a field cannot
    // quietly leave last take's value on screen.
    transcribedText = ""
    provisionalText = ""
    provisionalConfidence = 0
    detectedLanguageCode = nil
    errorMessage = nil
    audioLevels = []
    activeOptions = .current
    elapsedBase = 0
    recordingStartTime = Date()
    segmentStart = Date()

    let session = makeSession(currentEngine, activeOptions, whisperContext)
    self.session = session
    consume(session)

    state = .recording
    startTimer()

    do {
      try await session.start()
    } catch {
      errorMessage = errorMessage ?? error.localizedDescription
      await teardown()
      state = .idle
    }
  }

  func pause() async {
    guard state == .recording else { return }
    state = .paused
    stopTimer()
    elapsedBase += Date().timeIntervalSince(segmentStart ?? Date())
    await session?.pause()
  }

  func resume() async {
    guard state == .paused, let session else { return }
    do {
      try await session.resume()
      segmentStart = Date()
      state = .recording
      startTimer()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// Flushes the final window, then saves. `transcribedText` is complete once
  /// this returns — the previous version read it before the last decode landed,
  /// so the closing words were on screen but missing from the saved recording.
  func stopRecord() async {
    guard state == .recording || state == .paused else { return }
    let wasRecording = state == .recording
    state = .stopping
    stopTimer()
    // Paused time is already folded into elapsedBase; adding it twice would
    // inflate the saved duration.
    if wasRecording, let segmentStart {
      elapsedBase += Date().timeIntervalSince(segmentStart)
    }
    elapsedTime = elapsedBase

    if let session {
      transcribedText = await session.finish()
    }
    await teardown()

    provisionalText = ""
    provisionalConfidence = 0
    audioLevels = []
    state = .idle

    #if PRO_VERSION
    saveRecording()
    #endif
  }

  func cancel() async {
    guard state != .idle else { return }
    state = .stopping
    stopTimer()
    await session?.cancel()
    await teardown()
    state = .idle
  }

  private func teardown() async {
    consumer?.cancel()
    consumer = nil
    session = nil
  }

  // MARK: - Updates

  private func consume(_ session: LiveTranscriptionSession) {
    consumer = Task { [weak self] in
      for await update in session.updates {
        guard let self else { return }
        switch update {
        case .transcript(let transcript):
          self.transcribedText = transcript.committed
          self.provisionalText = transcript.provisional
          self.provisionalConfidence = transcript.provisionalConfidence
        case .level(let level):
          self.audioLevels.append(level)
          if self.audioLevels.count > self.maxAudioLevels {
            self.audioLevels.removeFirst()
          }
        case .detectedLanguage(let code):
          // Only meaningful when whisper was left to detect; a pinned language
          // would just echo the user's own choice back at them.
          if self.activeOptions.language == .automatic {
            self.detectedLanguageCode = code
          }
        case .failed(let message):
          self.errorMessage = message
        }
      }
    }
  }

  // MARK: - Elapsed timer

  private func startTimer() {
    timerTask?.cancel()
    timerTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(200))
        guard let self, self.state == .recording, let start = self.segmentStart else { break }
        self.elapsedTime = self.elapsedBase + Date().timeIntervalSince(start)
      }
    }
  }

  private func stopTimer() {
    timerTask?.cancel()
    timerTask = nil
  }

  /// Elapsed time formatted mm:ss for the recording screen.
  var formattedElapsedTime: String {
    let total = Int(elapsedTime)
    return String(format: "%02d:%02d", total / 60, total % 60)
  }

  // MARK: - Persistence

  private func saveRecording() {
    guard let modelContext,
          !transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let startTime = recordingStartTime else {
      return
    }

    let recording = Recording(
      timestamp: startTime,
      // Measured time, not wall clock at save: the flush can take seconds, and
      // paused stretches should not count.
      duration: elapsedTime,
      transcriptText: transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
    )

    modelContext.insert(recording)

    do {
      try modelContext.save()
      autoTitle(recording, in: modelContext)
    } catch {
      print("Error saving recording: \(error.localizedDescription)")
    }
  }

  /// Fills an empty title with an on-device AI suggestion (iOS 26+).
  /// Fire-and-forget: never blocks saving, never overwrites a user title.
  private func autoTitle(_ recording: Recording, in modelContext: ModelContext) {
    let generator = SummaryGenerator()
    guard generator.isAvailable, recording.title == nil else { return }

    Task { @MainActor in
      guard let title = await generator.generateTitle(for: recording.transcriptText),
            recording.title == nil else { return }
      recording.title = title
      try? modelContext.save()
    }
  }
}
