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
  var onRunEnded: ((SpeechRunEnd) -> Void)?
  var contextualStrings: [String] = []
  var authorized = true
  /// Thrown by restartRecognition(), as when the recognizer went unavailable.
  var restartError: Error?
  private(set) var restartCount = 0

  func requestAuthorization() async -> Bool { authorized }

  func startRecording() throws {
    transcribedText = ""
    isRecording = true
  }

  func restartRecognition() throws {
    restartCount += 1
    if let restartError { throw restartError }
    transcribedText = ""
  }

  /// The run ends by itself, as at the server's one-minute limit. Like the
  /// real one, capture keeps running and the run's text survives.
  func endRun(_ end: SpeechRunEnd = .finished) {
    onRunEnded?(end)
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

  /// A clock the tests move by hand, for the restart policy.
  @MainActor
  final class Clock {
    var now = Date(timeIntervalSinceReferenceDate: 0)
    func advance(_ seconds: TimeInterval) { now += seconds }
  }

  private func makeSession(
    options: TranscriptionOptions = .default,
    clock: Clock? = nil
  ) -> (AppleSpeechTranscriptionSession, FakeSpeechRecognizer) {
    let clock = clock ?? Clock()
    let recognizer = FakeSpeechRecognizer()
    let session = AppleSpeechTranscriptionSession(options: options, recognizer: recognizer,
                                                  now: { clock.now })
    return (session, recognizer)
  }

  /// Everything the session has yielded so far, without waiting for more.
  private func drain(_ session: AppleSpeechTranscriptionSession) async -> [TranscriptionUpdate] {
    _ = await session.finish()
    var seen: [TranscriptionUpdate] = []
    for await update in session.updates { seen.append(update) }
    return seen
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

  // MARK: - Runs that end by themselves

  @Test func aRunEndingByItselfRestartsAndKeepsEveryWord() async throws {
    let clock = Clock()
    let (session, recognizer) = makeSession(clock: clock)
    try await session.start()
    recognizer.hear("first minute")
    clock.advance(60)
    recognizer.endRun(.finished)

    #expect(recognizer.restartCount == 1)
    #expect(recognizer.isRecording, "capture must keep running across the restart")
    recognizer.hear("second minute")
    #expect(await session.finish() == "first minute second minute")
  }

  @Test func anErrorEndingTheRunAlsoRestarts() async throws {
    let clock = Clock()
    let (session, recognizer) = makeSession(clock: clock)
    try await session.start()
    recognizer.hear("before the error")
    clock.advance(20)
    recognizer.endRun(.failed(message: "network"))
    recognizer.hear("after it")
    #expect(recognizer.restartCount == 1)
    #expect(await session.finish() == "before the error after it")
  }

  @Test func restartsMixWithPausesWithoutRepeatingText() async throws {
    let clock = Clock()
    let (session, recognizer) = makeSession(clock: clock)
    try await session.start()
    recognizer.hear("one")
    clock.advance(60)
    recognizer.endRun()
    recognizer.hear("two")
    await session.pause()
    try await session.resume()
    recognizer.hear("three")
    clock.advance(60)
    recognizer.endRun()
    #expect(await session.finish() == "one two three",
            "a run that ended and was committed must not be committed again at finish")
  }

  @Test func aRunEndAfterPauseIsIgnored() async throws {
    let (session, recognizer) = makeSession()
    try await session.start()
    recognizer.hear("held")
    await session.pause()
    recognizer.endRun()
    #expect(recognizer.restartCount == 0)
    #expect(await session.finish() == "held")
  }

  @Test func aRecognizerThatKeepsDyingStopsTheTakeHonestly() async throws {
    let clock = Clock()
    let (session, recognizer) = makeSession(clock: clock)
    try await session.start()
    recognizer.hear("kept")
    for _ in 0..<3 {
      clock.advance(0.2)
      recognizer.endRun(.failed(message: "offline"))
    }
    #expect(!recognizer.isRecording, "capture is off once the session gives up")
    let updates = await drain(session)
    #expect(updates.contains { if case .stopped = $0 { true } else { false } })
    #expect(updates.last == .transcript(committedTranscript("kept")))
  }

  @Test func aRestartThatCannotBeginStopsTheTake() async throws {
    let (session, recognizer) = makeSession()
    try await session.start()
    recognizer.hear("so far")
    recognizer.restartError = NSError(domain: "test", code: 2)
    recognizer.endRun()
    #expect(!recognizer.isRecording)
    let updates = await drain(session)
    #expect(updates.contains { if case .stopped = $0 { true } else { false } })
  }

  @Test func theFinalTextOfAFailedRestartIsReturnedOnce() async throws {
    let (session, recognizer) = makeSession()
    try await session.start()
    recognizer.hear("only once")
    recognizer.restartError = NSError(domain: "test", code: 2)
    recognizer.endRun()
    #expect(await session.finish() == "only once")
  }

  @Test func theCustomVocabularyBecomesContextualStrings() {
    var options = TranscriptionOptions.default
    options.customVocabulary = "Kunze, ai-Memo\nWhisper"
    let (_, recognizer) = makeSession(options: options)
    #expect(recognizer.contextualStrings == ["Kunze", "ai-Memo", "Whisper"])
  }

  private func committedTranscript(_ text: String) -> LiveTranscript {
    var transcript = LiveTranscript()
    transcript.commit(text)
    return transcript
  }
}
