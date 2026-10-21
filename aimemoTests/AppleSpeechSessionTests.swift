//
//  AppleSpeechSessionTests.swift
//  aimemoTests
//
//  The Apple Speech session's pause/resume stitching, against a fake
//  recogniser that behaves like SFSpeechRecognizer: cumulative text within a
//  run, cleared on every start.
//

import Foundation
import Testing
@testable import aimemo

@MainActor
final class FakeSpeechRecognizer: SpeechRecognizing {
  var transcribedText = ""
  var isRecording = false
  var audioLevels: [Float] = []
  var authorized = true

  func requestAuthorization() async -> Bool { authorized }

  func startRecording() throws {
    transcribedText = ""
    isRecording = true
  }

  func stopRecording() {
    // Like the real one, the text survives the stop.
    isRecording = false
  }

  func setLanguage(_ locale: Locale) {}

  /// What the recogniser has heard so far in this run.
  func hear(_ text: String) { transcribedText = text }
}

@MainActor
struct AppleSpeechSessionTests {

  private func makeSession() -> (AppleSpeechTranscriptionSession, FakeSpeechRecognizer) {
    let recognizer = FakeSpeechRecognizer()
    let session = AppleSpeechTranscriptionSession(options: .default, recognizer: recognizer)
    return (session, recognizer)
  }

  @Test func oneRunFinishesWithWhatWasHeard() async throws {
    let (session, recognizer) = makeSession()
    try await session.start()
    recognizer.hear("Hello there")
    #expect(await session.finish() == "Hello there")
  }

  @Test func textBeforeAPauseSurvivesTheNextRun() async throws {
    let (session, recognizer) = makeSession()
    try await session.start()
    recognizer.hear("First part")
    await session.pause()
    try await session.resume()
    recognizer.hear("second part")
    #expect(await session.finish() == "First part second part")
  }

  @Test func severalPausesKeepEveryRunInOrder() async throws {
    let (session, recognizer) = makeSession()
    try await session.start()
    recognizer.hear("one")
    await session.pause()
    try await session.resume()
    recognizer.hear("two")
    await session.pause()
    try await session.resume()
    recognizer.hear("three")
    #expect(await session.finish() == "one two three")
  }

  @Test func finishingWhilePausedDoesNotRepeatTheLastRun() async throws {
    let (session, recognizer) = makeSession()
    try await session.start()
    recognizer.hear("Only once")
    await session.pause()
    #expect(await session.finish() == "Only once")
  }

  @Test func aSilentRunAddsNothing() async throws {
    let (session, recognizer) = makeSession()
    try await session.start()
    recognizer.hear("Before")
    await session.pause()
    try await session.resume()
    #expect(await session.finish() == "Before")
  }

  @Test func refusedAuthorizationFailsTheStart() async {
    let (session, recognizer) = makeSession()
    recognizer.authorized = false
    await #expect(throws: AppleSpeechTranscriptionSession.SessionError.self) {
      try await session.start()
    }
  }
}
