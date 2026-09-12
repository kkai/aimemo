//
//  LiveTranscriptionSession.swift
//  aimemo
//
//  One recording's lifecycle, behind one protocol for both engines
//

import Foundation

/// A single recording: construct, start, finish, discard.
///
/// Single-use on purpose. The previous design reused one long-lived object and
/// reset its fields by hand at start, which is how the last take's transcript
/// leaked into the next one. A fresh session cannot forget to reset.
///
/// `@MainActor` because every implementation immediately delegates to an actor
/// or to a framework object that is already main-bound; it removes all Sendable
/// friction with `@Observable` at no real cost.
@MainActor
protocol LiveTranscriptionSession: AnyObject {
  /// Single-consumer. Terminates once `finish()` or `cancel()` completes.
  var updates: AsyncStream<TranscriptionUpdate> { get }

  func start() async throws
  /// Commits the open window and stops capture; audio stops arriving.
  func pause() async
  func resume() async throws
  /// Flushes everything and returns the complete final text. Callers must await
  /// this before persisting.
  func finish() async -> String
  func cancel() async
}
