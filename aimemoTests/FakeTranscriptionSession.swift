//
//  FakeTranscriptionSession.swift
//  aimemoTests
//
//  Stands in for a recording session so RealTimeWhisper's state machine can be
//  tested without a microphone, a model, or simulator audio.
//

import Foundation
@testable import aimemo

@MainActor
final class FakeTranscriptionSession: LiveTranscriptionSession {

  let updates: AsyncStream<TranscriptionUpdate>
  private let continuation: AsyncStream<TranscriptionUpdate>.Continuation

  /// What finish() hands back as the complete transcript.
  var finalText: String
  /// Thrown by start(), to exercise the failure path.
  var startError: Error?

  private(set) var startCount = 0
  private(set) var pauseCount = 0
  private(set) var resumeCount = 0
  private(set) var finishCount = 0
  private(set) var cancelCount = 0

  init(finalText: String = "final transcript", startError: Error? = nil) {
    self.finalText = finalText
    self.startError = startError
    var sink: AsyncStream<TranscriptionUpdate>.Continuation!
    self.updates = AsyncStream(bufferingPolicy: .unbounded) { sink = $0 }
    self.continuation = sink
  }

  /// Pushes an update as a live session would.
  func emit(_ update: TranscriptionUpdate) {
    continuation.yield(update)
  }

  func start() async throws {
    startCount += 1
    if let startError { throw startError }
  }

  func pause() async { pauseCount += 1 }
  func resume() async throws { resumeCount += 1 }

  func finish() async -> String {
    finishCount += 1
    continuation.finish()
    return finalText
  }

  func cancel() async {
    cancelCount += 1
    continuation.finish()
  }

  enum FakeError: Error { case cannotStart }
}
