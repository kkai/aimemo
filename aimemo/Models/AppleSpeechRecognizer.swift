//
//  AppleSpeechRecognizer.swift
//  aimemo
//
//  Apple Speech Framework integration for real-time transcription
//

import Foundation
import Speech
import AVFoundation

@Observable
class AppleSpeechRecognizer {
  var transcribedText = ""
  var isRecording = false
  var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
  var errorMessage: String?
  var audioLevels: [Float] = []

  private let maxAudioLevels = 100
  private var speechRecognizer: SFSpeechRecognizer?
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private let audioEngine = AVAudioEngine()

  #if os(iOS)
  private let audioSession = AVAudioSession.sharedInstance()
  #endif

  // Recording metadata for auto-save
  private var recordingStartTime: Date?

  init() {
    // Initialize with user's preferred language, fallback to English
    speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    // Check initial authorization status
    authorizationStatus = SFSpeechRecognizer.authorizationStatus()
  }

  // MARK: - Authorization

  func requestAuthorization() async -> Bool {
    await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        DispatchQueue.main.async {
          self.authorizationStatus = status
          continuation.resume(returning: status == .authorized)
        }
      }
    }
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

    // Check availability
    guard let recognizer = speechRecognizer, recognizer.isAvailable else {
      throw NSError(
        domain: "AppleSpeech",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Speech recognition not available"]
      )
    }

    // Reset state
    if audioEngine.isRunning {
      stopRecording()
    }

    recordingStartTime = Date()
    transcribedText = ""
    errorMessage = nil

    #if os(iOS)
    // Configure audio session
    try audioSession.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)
    try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    #endif

    // Create recognition request
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true

    // Use on-device recognition if available (simulator doesn't support it)
    if recognizer.supportsOnDeviceRecognition {
      request.requiresOnDeviceRecognition = true
      print("Using on-device speech recognition")
    } else {
      request.requiresOnDeviceRecognition = false
      print("Using server-based speech recognition (on-device not available)")
    }

    // Optional: Add task hint for better accuracy (iOS 13+)
    if #available(iOS 13.0, *) {
      request.taskHint = .unspecified  // Can be .dictation, .search, .confirmation
    }

    recognitionRequest = request

    // Start recognition task
    recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
      guard let self = self else { return }

      if let error = error {
        DispatchQueue.main.async {
          self.errorMessage = error.localizedDescription
          print("Recognition error: \(error.localizedDescription)")
        }
        return
      }

      guard let result = result else { return }

      // Update transcribed text
      DispatchQueue.main.async {
        self.transcribedText = result.bestTranscription.formattedString
      }

      // If final result, stop recording
      if result.isFinal {
        self.stopRecording()
      }
    }

    // Configure audio engine
    let inputNode = audioEngine.inputNode
    let recordingFormat = inputNode.outputFormat(forBus: 0)

    inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, time in
      guard let self = self else { return }

      // Send audio to recognition
      self.recognitionRequest?.append(buffer)

      // Calculate amplitude for visualization
      DispatchQueue.main.async {
        let amplitude = self.calculateAmplitude(from: buffer)
        self.audioLevels.append(amplitude)
        if self.audioLevels.count > self.maxAudioLevels {
          self.audioLevels.removeFirst()
        }
      }
    }

    // Start audio engine
    audioEngine.prepare()
    try audioEngine.start()

    isRecording = true
    print("Apple Speech recognition started")
  }

  func stopRecording() {
    // Stop audio engine
    if audioEngine.isRunning {
      audioEngine.stop()
      audioEngine.inputNode.removeTap(onBus: 0)
    }

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

  // MARK: - Audio Processing

  private func calculateAmplitude(from buffer: AVAudioPCMBuffer) -> Float {
    guard let channelData = buffer.floatChannelData else { return 0.0 }

    let channelDataValue = channelData.pointee
    let channelDataValueArray = stride(
      from: 0,
      to: Int(buffer.frameLength),
      by: buffer.stride
    ).map { channelDataValue[$0] }

    // Calculate RMS (Root Mean Square) for amplitude
    let rms = sqrt(channelDataValueArray.map { $0 * $0 }.reduce(0, +) / Float(channelDataValueArray.count))

    // Normalize and apply scaling for better visualization
    let normalizedLevel = min(rms * 10, 1.0)

    return normalizedLevel
  }

  // MARK: - Language Support

  func availableLanguages() -> [Locale] {
    return Array(SFSpeechRecognizer.supportedLocales())
  }

  func setLanguage(_ locale: Locale) {
    speechRecognizer = SFSpeechRecognizer(locale: locale)
  }
}
