//
//  AppleSpeechRecognizer.swift
//  aimemo
//
//  Apple Speech Framework integration for real-time transcription
//

import Foundation
import Speech
import AVFoundation

/// `SFSpeechRecognizer` plus its own `AVAudioEngine` capture.
///
/// `@MainActor`: every observable property is written on main. The recognition
/// callback and the audio tap run on framework queues, so they are built by
/// `nonisolated` factories below and hop to main before touching state. This
/// used to write `isRecording` and `audioLevels` from the callback queue.
///
/// Capture and recognition have separate lifetimes. A recognition task can end
/// by itself (server recognition stops after about a minute, or an error), and
/// then capture keeps running: `onRunEnded` reports it and the session starts
/// a new task with `restartRecognition()`. Before, the task ending stopped
/// everything without telling anyone, and the screen kept saying "Recording".
@MainActor
@Observable
final class AppleSpeechRecognizer {
  var transcribedText = ""
  /// Run-relative timings of `transcribedText`, from `SFTranscription.segments`.
  var segments: [TranscriptSegment] = []
  var isRecording = false
  var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
  var errorMessage: String?
  var audioLevels: [Float] = []

  /// Called on main when the recognition task ended by itself while capture is
  /// still running. Never called for `stopRecording()`.
  @ObservationIgnored var onRunEnded: ((SpeechRunEnd) -> Void)?
  /// Words to bias recognition toward (`contextualStrings`), applied to every
  /// task started after it is set.
  @ObservationIgnored var contextualStrings: [String] = []

  private let maxAudioLevels = 100
  @ObservationIgnored private var speechRecognizer: SFSpeechRecognizer?
  @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
  /// The request the audio tap feeds. Read on the render thread.
  @ObservationIgnored private let tapTarget = SpeechRequestFeed()
  /// Identifies the current recognition task. Callbacks from any other task
  /// (a cancelled one, or one that already ended) are dropped.
  @ObservationIgnored private var runID = 0
  @ObservationIgnored private let audioEngine = AVAudioEngine()

  #if os(iOS)
  @ObservationIgnored private let audioSession = AVAudioSession.sharedInstance()
  #endif

  init() {
    speechRecognizer = SFSpeechRecognizer(locale: Self.preferredLocale())

    // Check initial authorization status
    authorizationStatus = SFSpeechRecognizer.authorizationStatus()
  }

  // MARK: - Authorization

  func requestAuthorization() async -> Bool {
    let status = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
    }
    authorizationStatus = status
    return status == .authorized
  }

  // MARK: - Recording

  func startRecording() throws {
    // Check authorization
    guard authorizationStatus == .authorized else {
      throw NSError(
        domain: "AppleSpeech",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Speech recognition not authorized. Please enable in Settings."]
      )
    }

    let recognizer = try availableRecognizer()

    // Reset state
    if audioEngine.isRunning {
      stopRecording()
    }

    transcribedText = ""
    segments = []
    errorMessage = nil

    #if os(iOS)
    // Configure audio session
    try audioSession.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)
    try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    #endif

    beginRecognitionTask(with: recognizer)

    // Configure audio engine
    let inputNode = audioEngine.inputNode
    let recordingFormat = inputNode.outputFormat(forBus: 0)
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat,
                         block: Self.makeTap(feeding: tapTarget, owner: self))

    // Start audio engine
    audioEngine.prepare()
    do {
      try audioEngine.start()
    } catch {
      stopRecording()
      throw error
    }

    isRecording = true
    print("Apple Speech recognition started")
  }

  /// Starts a fresh recognition task on the running capture, after the last
  /// one ended by itself. Clears `transcribedText`, like `startRecording()`;
  /// the session has committed the old run's text before calling this.
  func restartRecognition() throws {
    guard isRecording else {
      throw NSError(domain: "AppleSpeech", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Apple Speech is not recording."])
    }
    let recognizer = try availableRecognizer()
    transcribedText = ""
    segments = []
    errorMessage = nil
    beginRecognitionTask(with: recognizer)
    print("Apple Speech recognition restarted")
  }

  func stopRecording() {
    // Drop whatever the cancelled task still reports.
    runID += 1
    tapTarget.set(nil)

    // Stop audio engine
    if audioEngine.isRunning {
      audioEngine.stop()
    }
    audioEngine.inputNode.removeTap(onBus: 0)

    // End recognition request
    recognitionRequest?.endAudio()
    recognitionRequest = nil

    // Cancel recognition task
    recognitionTask?.cancel()
    recognitionTask = nil

    // Reset audio levels
    audioLevels = []

    isRecording = false
    print("Apple Speech recognition stopped")

    #if os(iOS)
    // Deactivate audio session
    do {
      try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      print("Error deactivating audio session: \(error.localizedDescription)")
    }
    #endif
  }

  // MARK: - Recognition task

  private func availableRecognizer() throws -> SFSpeechRecognizer {
    guard let recognizer = speechRecognizer, recognizer.isAvailable else {
      throw NSError(
        domain: "AppleSpeech",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Apple Speech is not available right now."]
      )
    }
    return recognizer
  }

  private func beginRecognitionTask(with recognizer: SFSpeechRecognizer) {
    runID += 1
    let run = runID

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.taskHint = .unspecified
    request.contextualStrings = contextualStrings

    // Use on-device recognition if available (simulator doesn't support it)
    if recognizer.supportsOnDeviceRecognition {
      request.requiresOnDeviceRecognition = true
      print("Using on-device speech recognition")
    } else {
      request.requiresOnDeviceRecognition = false
      print("Using server-based speech recognition (on-device not available)")
    }

    recognitionRequest = request
    tapTarget.set(request)
    recognitionTask = recognizer.recognitionTask(
      with: request, resultHandler: Self.makeResultHandler(owner: self, run: run))
  }

  /// Main-actor half of the result handler.
  private func handleRecognition(run: Int, text: String?, segments: [TranscriptSegment],
                                 isFinal: Bool, error: String?) {
    guard run == runID, isRecording else { return }
    if let text {
      transcribedText = text
      self.segments = segments
    }
    guard isFinal || error != nil else { return }

    // This task is over. Capture keeps running so the session can restart.
    runID += 1
    tapTarget.set(nil)
    recognitionRequest = nil
    recognitionTask = nil
    if let error {
      errorMessage = error
      print("Recognition error: \(error)")
      onRunEnded?(.failed(message: error))
    } else {
      onRunEnded?(.finished)
    }
  }

  private func appendLevel(_ level: Float) {
    guard isRecording else { return }
    audioLevels.append(level)
    if audioLevels.count > maxAudioLevels {
      audioLevels.removeFirst()
    }
  }

  // MARK: - Callbacks off the main thread

  /// Runs on Speech's callback queue. Extracts plain values there, then hops.
  nonisolated private static func makeResultHandler(
    owner: AppleSpeechRecognizer, run: Int
  ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
    { [weak owner] result, error in
      let text = result?.bestTranscription.formattedString
      // Plain values only: SFTranscriptionSegment is not Sendable.
      let segments = (result?.bestTranscription.segments ?? []).map {
        TranscriptSegment(text: $0.substring, start: $0.timestamp, end: $0.timestamp + $0.duration)
      }
      let isFinal = result?.isFinal ?? false
      let message = error?.localizedDescription
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          owner?.handleRecognition(run: run, text: text, segments: segments,
                                   isFinal: isFinal, error: message)
        }
      }
    }
  }

  /// Runs on the audio render thread.
  nonisolated private static func makeTap(
    feeding target: SpeechRequestFeed, owner: AppleSpeechRecognizer
  ) -> AVAudioNodeTapBlock {
    { [weak owner] buffer, _ in
      target.append(buffer)
      let level = AudioSamples.meterLevel(from: buffer)
      DispatchQueue.main.async {
        MainActor.assumeIsolated { owner?.appendLevel(level) }
      }
    }
  }

  // MARK: - Language Support

  func availableLanguages() -> [Locale] {
    return Array(SFSpeechRecognizer.supportedLocales())
  }

  func setLanguage(_ locale: Locale) {
    speechRecognizer = SFSpeechRecognizer(locale: locale)
  }

  /// Re-resolves the recognizer against the current language setting.
  /// Called when a recording starts, since Settings may have changed since init.
  func refreshLanguage() {
    setLanguage(Self.preferredLocale())
  }

  /// Best supported locale for the user's language choice.
  ///
  /// Apple Speech has no auto-detect, so `.automatic` resolves to the device
  /// locale rather than silently staying on US English — which is what this
  /// used to do unconditionally, despite the store copy advertising
  /// multi-language support for this engine.
  nonisolated static func preferredLocale(for language: TranscriptionLanguage = .selected) -> Locale {
    let supported = SFSpeechRecognizer.supportedLocales()

    func match(_ code: String) -> Locale? {
      // Prefer an exact region match ("de-DE"), else any region of that language.
      supported.first { $0.identifier.replacingOccurrences(of: "_", with: "-") == code }
        ?? supported.first { $0.language.languageCode?.identifier == code }
    }

    if case .specific(let code) = language, let locale = match(code) {
      return locale
    }
    if let device = Locale.current.language.languageCode?.identifier,
       let locale = match(device) {
      return locale
    }
    return Locale(identifier: "en-US")
  }
}
