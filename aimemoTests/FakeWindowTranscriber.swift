//
//  FakeWindowTranscriber.swift
//  aimemoTests
//
//  Stands in for whisper so the streaming core can be driven deterministically.
//

import Foundation
@testable import aimemo

/// Records every request and returns scripted results.
actor FakeWindowTranscriber: WindowTranscribing {

  struct Request: Equatable {
    let sampleCount: Int
    let prompt: String?
    let isPreview: Bool
  }

  private(set) var requests: [Request] = []
  private var nextIndex = 0
  private let texts: [String]
  private let language: String?
  /// Throw on these call indices (0-based).
  private let failingIndices: Set<Int>
  /// Artificial decode latency, to let backlog build up.
  private let delay: Duration?
  /// Reproduces whisper emitting nothing when a prompt is supplied, which it
  /// does when the prompt already reads like the audio.
  private let emptyWhenPrompted: Bool

  private nonisolated let abortBox = AbortBox()

  final class AbortBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var wasRequested: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func request() { lock.lock(); value = true; lock.unlock() }
  }

  init(texts: [String] = [],
       language: String? = nil,
       failingIndices: Set<Int> = [],
       delay: Duration? = nil,
       emptyWhenPrompted: Bool = false) {
    self.texts = texts
    self.language = language
    self.failingIndices = failingIndices
    self.delay = delay
    self.emptyWhenPrompted = emptyWhenPrompted
  }

  var abortWasRequested: Bool { abortBox.wasRequested }
  var callCount: Int { requests.count }
  var prompts: [String?] { requests.map(\.prompt) }

  func transcribe(
    window: [Float],
    prompt: String?,
    options: TranscriptionOptions,
    isPreview: Bool
  ) async throws -> TranscribedWindow {
    let index = nextIndex
    nextIndex += 1
    requests.append(Request(sampleCount: window.count, prompt: prompt, isPreview: isPreview))

    if let delay { try? await Task.sleep(for: delay) }

    if failingIndices.contains(index) {
      throw FakeError.scripted
    }

    if emptyWhenPrompted, prompt != nil {
      return TranscribedWindow(segments: [], detectedLanguageCode: language)
    }

    let text = index < texts.count ? texts[index] : "window\(index)"
    return TranscribedWindow(
      segments: [.init(text: text, start: 0, end: 1, confidence: 0.9)],
      detectedLanguageCode: language
    )
  }

  nonisolated func abortInFlight() {
    abortBox.request()
  }

  enum FakeError: Error { case scripted }
}
