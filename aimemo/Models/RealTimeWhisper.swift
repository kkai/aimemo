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
    /// Decoding a file the user handed over. Record is disabled; Cancel keeps
    /// what has been committed so far.
    case importing
  }

  // MARK: - Observable state

  private(set) var state: State = .idle {
    didSet {
      let live = state != .idle
      if live != (oldValue != .idle) { keepScreenAwake(live) }
    }
  }
  /// True while a recording is in progress; drives the record button.
  var canStop: Bool { state == .recording || state == .paused }
  /// True while the final flush is running.
  var isBusy: Bool { state == .stopping }
  /// 0…1 while `state == .importing`.
  private(set) var importProgress: Double = 0
  /// The file being transcribed, while `state == .importing`, and the source
  /// of the transcript on screen afterwards.
  private(set) var importedFile: ImportedFile?
  /// Set while paused: whether the user paused or the system did (a call,
  /// Siri, an alarm). Only a system pause is resumed automatically.
  private(set) var pauseReason: PauseReason?

  /// Committed text. This is what gets saved, copied and shared.
  var transcribedText = ""
  /// Timed pieces of `transcribedText`, filled when a take finishes. Empty
  /// while recording and for engines that report no timings.
  private(set) var segments: [TranscriptSegment] = []
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
  /// True when a running take has had no audio for a few seconds. The
  /// screen shows it, so "Recording" over a dead microphone is visible.
  private(set) var noAudio = false

  /// "A model is loaded." Nothing more — the old flag doubled as a
  /// transcription mutex and could wedge itself false forever.
  private(set) var canTranscribe = false

  var currentModel: WhisperModel = .selected
  var currentEngine: TranscriptionEngine = .selected
  var modelContext: ModelContext?
  /// The history entry the last take was saved to (Pro), so a summary made
  /// on the recording screen can be stored with it.
  private(set) var lastSaved: Recording?

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
  private(set) var recordingStartTime: Date?
  /// The import's streaming core, held so Cancel can abort the decode.
  private var importCore: StreamingTranscriber?
  private var importCancelled = false
  /// Stands in for the loaded whisper context when transcribing a file; tests
  /// inject a fake so the import path runs without a model.
  private let fileTranscriberOverride: WindowTranscribing?
  /// Elapsed time accumulated before the current run, so pause is honest.
  private var elapsedBase: TimeInterval = 0
  private var segmentStart: Date?
  private var timerTask: Task<Void, Never>?
  private var silenceWatch = SilenceWatch()

  /// Auto-Lock suspends the app and capture with it, and there is no
  /// background audio mode yet (2.6 step 2), so the screen stays on while a
  /// take is live. Injected so tests don't flip the real setting.
  private let keepScreenAwake: (Bool) -> Void

  /// Kept alive for the recorder's lifetime; owns the notification observers.
  private var liveSessionEvents: AudioSessionEvents?
  private var sessionEventsTask: Task<Void, Never>?

  // MARK: - Init

  init(
    loader: WhisperModelLoader = WhisperModelLoader(),
    makeSession: (
      (TranscriptionEngine, TranscriptionOptions, WhisperContext?) -> LiveTranscriptionSession
    )? = nil,
    sessionEvents: AsyncStream<AudioSessionEvent>? = nil,
    noAudioAfter: TimeInterval = 5,
    keepScreenAwake: ((Bool) -> Void)? = nil,
    fileTranscriber: WindowTranscribing? = nil
  ) {
    self.loader = loader
    self.fileTranscriberOverride = fileTranscriber
    self.keepScreenAwake = keepScreenAwake ?? { awake in
      #if os(iOS)
      UIApplication.shared.isIdleTimerDisabled = awake
      #endif
    }
    self.makeSession = makeSession ?? { engine, options, context in
      switch engine {
      case .whisper:
        // A missing context is prevented by the guard in start().
        return WhisperTranscriptionSession(context: context!, options: options)
      case .appleSpeech:
        return AppleSpeechTranscriptionSession(options: options)
      }
    }

    silenceWatch.limit = noAudioAfter

    let selected = WhisperModel.selected
    do {
      whisperContext = try loader.makeContext(for: selected)
      currentModel = selected
      canTranscribe = true
    } catch {
      print("Error loading model: \(error.localizedDescription)")
    }

    let events: AsyncStream<AudioSessionEvent>
    if let sessionEvents {
      events = sessionEvents
    } else {
      let live = AudioSessionEvents()
      liveSessionEvents = live
      events = live.events
    }
    sessionEventsTask = Task { [weak self] in
      for await event in events {
        guard let self else { return }
        await self.handle(event)
      }
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
    segments = []
    provisionalText = ""
    provisionalConfidence = 0
    detectedLanguageCode = nil
    errorMessage = nil
    pauseReason = nil
    lastSaved = nil
    audioLevels = []
    noAudio = false
    silenceWatch.reset(at: Date())
    activeOptions = .current
    elapsedBase = 0
    recordingStartTime = Date()
    segmentStart = Date()
    importedFile?.discard()
    importedFile = nil

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

  /// A pause the user asked for.
  func pause() async {
    await pause(reason: .user)
  }

  private func pause(reason: PauseReason) async {
    guard state == .recording else { return }
    state = .paused
    pauseReason = reason
    noAudio = false
    stopTimer()
    elapsedBase += Date().timeIntervalSince(segmentStart ?? Date())
    await session?.pause()
  }

  /// The app left the screen. Without a background audio mode iOS suspends
  /// it and capture stops, so pause now and say so, instead of coming back
  /// to a "Recording" pill with a gap in the audio and in the timer.
  func enterBackground() async {
    guard state == .recording else { return }
    await pause(reason: .background)
    errorMessage = "Recording paused when you left the app. Tap Resume to continue."
  }

  func resume() async {
    guard state == .paused, let session else { return }
    do {
      try await session.resume()
      segmentStart = Date()
      silenceWatch.reset(at: Date())
      noAudio = false
      state = .recording
      pauseReason = nil
      errorMessage = nil
      startTimer()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  // MARK: - Interruptions

  func handle(_ event: AudioSessionEvent) async {
    switch InterruptionPolicy.action(for: event, state: state, pauseReason: pauseReason) {
    case .ignore:
      break
    case .pause:
      await pause(reason: .interruption)
    case .resume:
      await resume()
    case .restartCapture:
      await restartCapture()
    case .stop:
      await stopRecord()
      errorMessage = "The system reset its audio. The transcript up to that point was kept."
    }
  }

  /// Picks up a new input device without the user seeing a pause. Pausing the
  /// session commits the open window, so nothing is glued across the switch.
  private func restartCapture() async {
    guard state == .recording, let session else { return }
    await session.pause()
    do {
      try await session.resume()
    } catch {
      // No usable input right now: hold the recording rather than lose it.
      state = .paused
      pauseReason = .interruption
      stopTimer()
      elapsedBase += Date().timeIntervalSince(segmentStart ?? Date())
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
    pauseReason = nil
    noAudio = false
    stopTimer()
    // Paused time is already folded into elapsedBase; adding it twice would
    // inflate the saved duration.
    if wasRecording, let segmentStart {
      elapsedBase += Date().timeIntervalSince(segmentStart)
    }
    elapsedTime = elapsedBase

    if let session {
      transcribedText = await session.finish()
      segments = await session.finalSegments()
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
    noAudio = false
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
          self.silenceWatch.record(level: level, at: Date())
          if self.noAudio, !self.silenceWatch.isSilent(at: Date()) { self.noAudio = false }
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
        case .stopped(let message):
          // The engine gave up by itself. Stop for real (flush, save) rather
          // than keep a "Recording" pill over nothing.
          await self.stopRecord()
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
        let now = Date()
        self.elapsedTime = self.elapsedBase + now.timeIntervalSince(start)
        // Checked here too, not only per level: no levels at all is the
        // clearest sign capture has died.
        let silent = self.silenceWatch.isSilent(at: now)
        if silent != self.noAudio { self.noAudio = silent }
      }
    }
  }

  private func stopTimer() {
    timerTask?.cancel()
    timerTask = nil
  }

  /// The Clear button. One place, so the timings cannot outlive the text.
  func clearTranscript() {
    transcribedText = ""
    segments = []
    importedFile?.discard()
    importedFile = nil
  }

  /// Shows a message on the error line, for failures that happen outside
  /// the recorder (a file that could not be opened).
  func report(_ message: String) {
    errorMessage = message
  }

  // MARK: - Files

  enum ImportFailure: LocalizedError {
    case busy
    var errorDescription: String? { "Stop the recording before transcribing a file." }
  }

  /// Transcribes an audio or video file with the loaded Whisper model. Apple
  /// Speech has no file path here, so the setting is ignored for imports;
  /// the language and vocabulary settings still apply.
  ///
  /// Runs to completion or until `cancelImport()`. The transcript lands in
  /// `transcribedText` and `segments` like a live take, and Pro saves it to
  /// History with the file's name.
  func transcribe(file: ImportedFile) async {
    guard state == .idle else {
      errorMessage = ImportFailure.busy.errorDescription
      return
    }
    guard let transcriber: WindowTranscribing = fileTranscriberOverride ?? whisperContext else {
      errorMessage = ModelError.notLoaded.errorDescription
      return
    }

    transcribedText = ""
    segments = []
    provisionalText = ""
    provisionalConfidence = 0
    detectedLanguageCode = nil
    errorMessage = nil
    pauseReason = nil
    audioLevels = []
    noAudio = false
    activeOptions = .current
    elapsedBase = 0
    elapsedTime = 0
    recordingStartTime = Date()
    lastSaved = nil
    importedFile?.discard()
    importedFile = file
    importProgress = 0
    importCancelled = false

    state = .importing

    let core = StreamingTranscriber(transcriber: transcriber, options: activeOptions)
    importCore = core
    let mirror = Task { [weak self] in
      for await update in core.updates {
        guard let self else { return }
        switch update {
        case .transcript(let transcript):
          self.transcribedText = transcript.committed
          self.provisionalText = transcript.provisional
        case .detectedLanguage(let code):
          if self.activeOptions.language == .automatic { self.detectedLanguageCode = code }
        case .failed(let message):
          self.errorMessage = message
        case .level, .stopped:
          break
        }
      }
    }

    let reader = AudioFileReader(url: file.url)
    var failure: String?
    var duration: TimeInterval = 0
    do {
      duration = try await reader.duration()
      var fed = 0
      for try await chunk in reader.samples() {
        if importCancelled { break }
        await core.feed(chunk)
        fed += chunk.count
        if duration > 0 {
          importProgress = min(1, Double(fed) / AudioFileReader.sampleRate / duration)
        }
        // Keeps the elapsed line meaningful: how much of the file is done.
        elapsedTime = Double(fed) / AudioFileReader.sampleRate
      }
    } catch {
      failure = error.localizedDescription
    }

    if importCancelled {
      transcribedText = await core.currentTranscript.committed
      segments = await core.currentTranscript.committedSegments
    } else {
      transcribedText = await core.finish()
      segments = await core.currentTranscript.committedSegments
      importProgress = 1
      await mirror.value
    }
    mirror.cancel()
    importCore = nil
    provisionalText = ""
    provisionalConfidence = 0
    if duration > 0, !importCancelled { elapsedTime = duration }
    state = .idle

    if let failure {
      errorMessage = failure
    } else if transcribedText.isEmpty, !importCancelled {
      errorMessage = "No speech was found in \(file.displayName)."
    }

    #if PRO_VERSION
    if !importCancelled { saveImport(file, duration: duration) }
    #endif
  }

  /// Stops the decode and keeps the text committed so far.
  func cancelImport() async {
    guard state == .importing else { return }
    importCancelled = true
    await importCore?.cancel()
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
      transcriptText: transcribedText.trimmingCharacters(in: .whitespacesAndNewlines),
      segments: segments
    )

    modelContext.insert(recording)

    do {
      try modelContext.save()
      lastSaved = recording
      autoTitle(recording, in: modelContext)
    } catch {
      print("Error saving recording: \(error.localizedDescription)")
    }
  }

  private func saveImport(_ file: ImportedFile, duration: TimeInterval) {
    guard let modelContext,
          !transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    let recording = Recording(
      timestamp: recordingStartTime ?? Date(),
      duration: duration > 0 ? duration : elapsedTime,
      transcriptText: transcribedText.trimmingCharacters(in: .whitespacesAndNewlines),
      title: file.suggestedTitle,
      segments: segments,
      sourceFileName: file.displayName
    )
    modelContext.insert(recording)
    do {
      try modelContext.save()
      lastSaved = recording
      autoTitle(recording, in: modelContext)
    } catch {
      print("Error saving import: \(error.localizedDescription)")
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
