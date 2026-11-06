//
//  RealTimeWhisperStateTests.swift
//  aimemoTests
//
//  The recording state machine, with a fake session. This is the coverage the
//  roadmap flagged as missing before pause/resume could be built safely.
//

import Foundation
import SwiftData
import Testing
@testable import aimemo

/// Serialized: several tests set the shared TranscriptionLanguage default, and
/// RealTimeWhisper.start() snapshots it. Running them in parallel lets one
/// test's language leak into another's recorder.
@MainActor
@Suite(.serialized)
struct RealTimeWhisperStateTests {

  /// A recorder whose sessions are fakes, so nothing touches audio hardware.
  private func makeRecorder(
    _ session: FakeTranscriptionSession
  ) -> RealTimeWhisper {
    // An empty event stream: the live one would let a real route change on
    // the test machine restart the fake mid-test.
    RealTimeWhisper(makeSession: { _, _, _ in session },
                    sessionEvents: AsyncStream { _ in },
                    keepScreenAwake: { _ in })
  }

  /// Records every idle-timer change the recorder asks for.
  @MainActor
  final class AwakeLog {
    var values: [Bool] = []
  }

  // MARK: - Transitions

  @Test func startsIdle() {
    let recorder = makeRecorder(FakeTranscriptionSession())
    #expect(recorder.state == .idle)
    #expect(!recorder.canStop)
    #expect(!recorder.isBusy)
  }

  @Test func startMovesToRecording() async {
    let session = FakeTranscriptionSession()
    let recorder = makeRecorder(session)
    await recorder.start()
    #expect(recorder.state == .recording)
    #expect(recorder.canStop)
    #expect(session.startCount == 1)
  }

  @Test func startIsIgnoredWhileAlreadyRecording() async {
    let session = FakeTranscriptionSession()
    let recorder = makeRecorder(session)
    await recorder.start()
    await recorder.start()
    #expect(session.startCount == 1)
  }

  @Test func fullCycleStartPauseResumeStopEndsIdle() async {
    let session = FakeTranscriptionSession()
    let recorder = makeRecorder(session)

    await recorder.start()
    #expect(recorder.state == .recording)
    await recorder.pause()
    #expect(recorder.state == .paused)
    #expect(recorder.canStop, "a paused recording is still stoppable")
    await recorder.resume()
    #expect(recorder.state == .recording)
    await recorder.stopRecord()
    #expect(recorder.state == .idle)

    #expect(session.pauseCount == 1)
    #expect(session.resumeCount == 1)
    #expect(session.finishCount == 1)
  }

  @Test func stopFromPausedReturnsToIdle() async {
    let session = FakeTranscriptionSession()
    let recorder = makeRecorder(session)
    await recorder.start()
    await recorder.pause()
    await recorder.stopRecord()
    #expect(recorder.state == .idle)
    #expect(session.finishCount == 1)
  }

  @Test func illegalTransitionsAreNoOpsNotCrashes() async {
    let session = FakeTranscriptionSession()
    let recorder = makeRecorder(session)

    await recorder.pause()                 // idle -> pause
    #expect(recorder.state == .idle)
    await recorder.resume()                // idle -> resume
    #expect(recorder.state == .idle)
    await recorder.stopRecord()            // idle -> stop
    #expect(recorder.state == .idle)
    #expect(session.finishCount == 0)

    await recorder.start()
    await recorder.resume()                // recording -> resume
    #expect(recorder.state == .recording)
    #expect(session.resumeCount == 0)
  }

  @Test func aFailedStartReturnsToIdleAndReportsWhy() async {
    let session = FakeTranscriptionSession(startError: FakeTranscriptionSession.FakeError.cannotStart)
    let recorder = makeRecorder(session)
    await recorder.start()
    #expect(recorder.state == .idle)
    #expect(recorder.errorMessage != nil)
  }

  // MARK: - Per-take reset (data-loss bug #2)

  @Test func startClearsThePreviousTakesTranscript() async {
    // The old pipeline never reset this, so the last take's text was visible
    // under the new take's waveform until the first decode landed.
    let session = FakeTranscriptionSession()
    let recorder = makeRecorder(session)
    recorder.transcribedText = "text from the previous recording"
    await recorder.start()
    #expect(recorder.transcribedText.isEmpty)
  }

  @Test func startClearsProvisionalTextLanguageAndLevels() async {
    let session = FakeTranscriptionSession()
    let recorder = makeRecorder(session)
    recorder.audioLevels = [0.5, 0.5]
    await recorder.start()
    session.emit(.transcript(LiveTranscript()))
    #expect(recorder.provisionalText.isEmpty)
    #expect(recorder.detectedLanguageCode == nil)
    #expect(recorder.audioLevels.isEmpty)
  }

  // MARK: - Final flush (data-loss bug #1)

  @Test func stopTakesItsTranscriptFromTheFinalFlush() async {
    // The guarantee: finish() returns the text, so a stale read is
    // unrepresentable rather than merely avoided.
    let session = FakeTranscriptionSession(finalText: "the complete transcript")
    let recorder = makeRecorder(session)
    await recorder.start()
    session.emit(.transcript(LiveTranscript()))
    await recorder.stopRecord()
    #expect(recorder.transcribedText == "the complete transcript")
  }

  @Test func stopClearsTheProvisionalTail() async {
    let session = FakeTranscriptionSession()
    let recorder = makeRecorder(session)
    await recorder.start()
    await recorder.stopRecord()
    #expect(recorder.provisionalText.isEmpty)
    #expect(recorder.audioLevels.isEmpty)
  }

  // MARK: - Updates

  @Test func transcriptUpdatesReachTheObservableProperties() async {
    let session = FakeTranscriptionSession()
    let recorder = makeRecorder(session)
    await recorder.start()

    var transcript = LiveTranscript()
    transcript.commit("settled.")
    transcript.setProvisional("guessing", confidence: 0.4)
    session.emit(.transcript(transcript))

    await Task.yield()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(recorder.transcribedText == "settled.")
    #expect(recorder.provisionalText == "guessing")
    #expect(recorder.displayText == "settled. guessing")
  }

  @Test func levelsAreCappedAtTheWaveformWidth() async {
    let session = FakeTranscriptionSession()
    let recorder = makeRecorder(session)
    await recorder.start()
    for _ in 0..<250 { session.emit(.level(0.5)) }
    try? await Task.sleep(for: .milliseconds(100))
    #expect(recorder.audioLevels.count <= 100)
  }

  @Test func detectedLanguageIsSuppressedWhenTheUserPinnedOne() async {
    TranscriptionLanguage.selected = .specific("fr")
    defer { TranscriptionLanguage.selected = .automatic }

    let session = FakeTranscriptionSession()
    let recorder = makeRecorder(session)
    await recorder.start()
    session.emit(.detectedLanguage("de"))
    try? await Task.sleep(for: .milliseconds(50))
    #expect(recorder.detectedLanguageCode == nil,
            "a pinned language should not be echoed back as a detection")
  }

  @Test func detectedLanguageSurfacesWhenAutoDetecting() async {
    TranscriptionLanguage.selected = .automatic
    defer { TranscriptionLanguage.selected = .automatic }
    let session = FakeTranscriptionSession()
    let recorder = makeRecorder(session)
    await recorder.start()
    session.emit(.detectedLanguage("de"))
    try? await Task.sleep(for: .milliseconds(50))
    #expect(recorder.detectedLanguageCode == "de")
  }

  // MARK: - Elapsed time

  @Test func elapsedTimeDoesNotAdvanceWhilePaused() async {
    let session = FakeTranscriptionSession()
    let recorder = makeRecorder(session)
    await recorder.start()
    try? await Task.sleep(for: .milliseconds(300))
    await recorder.pause()

    let frozen = recorder.elapsedTime
    try? await Task.sleep(for: .milliseconds(300))
    #expect(recorder.elapsedTime == frozen, "the clock ran while paused")
  }

  @Test func elapsedTimeIsFormattedAsMinutesAndSeconds() {
    let recorder = makeRecorder(FakeTranscriptionSession())
    recorder.elapsedTime = 65
    #expect(recorder.formattedElapsedTime == "01:05")
  }

  // MARK: - Model swapping

  @Test func loadModelIsRefusedWhileRecording() async throws {
    // SettingsView is reachable from the recording screen; swapping the context
    // under a live decode would free it mid-flight.
    let session = FakeTranscriptionSession()
    let recorder = makeRecorder(session)
    await recorder.start()
    await #expect(throws: RealTimeWhisper.ModelError.self) {
      try await recorder.loadModel(.base)
    }
  }

  @Test func loadModelIsAllowedWhenIdle() async throws {
    let recorder = makeRecorder(FakeTranscriptionSession())
    try await recorder.loadModel(.base)
    #expect(recorder.currentModel == .base)
    #expect(recorder.canTranscribe)
  }

  // MARK: - Saving (Pro)

  #if PRO_VERSION
  @Test func stopSavesExactlyOneRecordingWithTheFlushedText() async throws {
    let container = try ModelContainer(
      for: Recording.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let session = FakeTranscriptionSession(finalText: "saved transcript")
    let recorder = makeRecorder(session)
    recorder.modelContext = container.mainContext

    await recorder.start()
    await recorder.stopRecord()

    let saved = try container.mainContext.fetch(FetchDescriptor<Recording>())
    #expect(saved.count == 1)
    #expect(saved.first?.transcriptText == "saved transcript")
  }

  @Test func anEmptyTranscriptIsNotSaved() async throws {
    let container = try ModelContainer(
      for: Recording.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let session = FakeTranscriptionSession(finalText: "   ")
    let recorder = makeRecorder(session)
    recorder.modelContext = container.mainContext

    await recorder.start()
    await recorder.stopRecord()

    #expect(try container.mainContext.fetch(FetchDescriptor<Recording>()).isEmpty)
  }
  #endif

  // MARK: - Honest stops

  @Test func aSessionThatStopsByItselfEndsTheTakeAndSaysWhy() async {
    let session = FakeTranscriptionSession(finalText: "what was heard")
    let recorder = makeRecorder(session)
    await recorder.start()
    session.emit(.stopped(message: "Apple Speech stopped."))
    try? await Task.sleep(for: .milliseconds(100))
    #expect(recorder.state == .idle, "the pill must not stay on Recording")
    #expect(session.finishCount == 1)
    #expect(recorder.transcribedText == "what was heard")
    #expect(recorder.errorMessage == "Apple Speech stopped.")
  }

  @Test func theScreenStaysAwakeOnlyWhileATakeIsLive() async {
    let log = AwakeLog()
    let session = FakeTranscriptionSession()
    let recorder = RealTimeWhisper(makeSession: { _, _, _ in session },
                                   sessionEvents: AsyncStream { _ in },
                                   keepScreenAwake: { log.values.append($0) })
    await recorder.start()
    #expect(log.values == [true])
    await recorder.pause()
    await recorder.resume()
    #expect(log.values == [true], "pause and resume keep the take live")
    await recorder.stopRecord()
    #expect(log.values == [true, false])
  }

  @Test func aFailedStartLetsTheScreenSleepAgain() async {
    let log = AwakeLog()
    let session = FakeTranscriptionSession(startError: FakeTranscriptionSession.FakeError.cannotStart)
    let recorder = RealTimeWhisper(makeSession: { _, _, _ in session },
                                   sessionEvents: AsyncStream { _ in },
                                   keepScreenAwake: { log.values.append($0) })
    await recorder.start()
    #expect(log.values.last == false)
  }

  @Test func leavingTheAppPausesAndSaysSo() async {
    let session = FakeTranscriptionSession()
    let recorder = makeRecorder(session)
    await recorder.start()
    await recorder.enterBackground()
    #expect(recorder.state == .paused)
    #expect(recorder.pauseReason == .background)
    #expect(session.pauseCount == 1)
    #expect(recorder.errorMessage != nil)
    await recorder.resume()
    #expect(recorder.state == .recording)
    #expect(recorder.errorMessage == nil)
  }

  @Test func leavingTheAppWhilePausedChangesNothing() async {
    let session = FakeTranscriptionSession()
    let recorder = makeRecorder(session)
    await recorder.start()
    await recorder.pause()
    await recorder.enterBackground()
    #expect(recorder.pauseReason == .user)
    #expect(session.pauseCount == 1)
  }

  @Test func noAudioShowsAfterSilenceAndClearsOnSound() async {
    let session = FakeTranscriptionSession()
    let recorder = RealTimeWhisper(makeSession: { _, _, _ in session },
                                   sessionEvents: AsyncStream { _ in },
                                   noAudioAfter: 0.3,
                                   keepScreenAwake: { _ in })
    await recorder.start()
    #expect(!recorder.noAudio)
    session.emit(.level(0))
    try? await Task.sleep(for: .milliseconds(700))
    #expect(recorder.noAudio, "no sound for longer than the limit")
    session.emit(.level(0.3))
    try? await Task.sleep(for: .milliseconds(250))
    #expect(!recorder.noAudio)
    await recorder.pause()
    #expect(!recorder.noAudio, "a paused take is expected to be silent")
  }

  // MARK: - Files

  nonisolated private static var wavFixture: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Resources/audio/en.wav")
  }
  nonisolated private static var hasWav: Bool { FileManager.default.fileExists(atPath: wavFixture.path) }

  private func makeImporter(_ fake: FakeWindowTranscriber) -> RealTimeWhisper {
    RealTimeWhisper(makeSession: { _, _, _ in FakeTranscriptionSession() },
                    sessionEvents: AsyncStream { _ in },
                    keepScreenAwake: { _ in },
                    fileTranscriber: fake)
  }

  @Test(.enabled(if: RealTimeWhisperStateTests.hasWav))
  func transcribingAFileRunsImportingToIdleWithTimedText() async throws {
    let fake = FakeWindowTranscriber(texts: ["Hello from a file."], language: "en")
    let recorder = makeImporter(fake)
    let file = try ImportedFile.stage(Self.wavFixture)
    defer { file.discard() }

    await recorder.transcribe(file: file)

    #expect(recorder.state == .idle)
    #expect(recorder.transcribedText.hasPrefix("Hello from a file."))
    #expect(!recorder.segments.isEmpty)
    #expect(recorder.importProgress == 1)
    #expect(recorder.detectedLanguageCode == "en")
    #expect(abs(recorder.elapsedTime - 4.67) < 0.1, "elapsed is the file's duration")
    #expect(recorder.importedFile == file)
    #expect(recorder.errorMessage == nil)
  }

  @Test func transcribingAFileIsRefusedWhileRecording() async {
    let session = FakeTranscriptionSession()
    let recorder = makeRecorder(session)
    await recorder.start()
    await recorder.transcribe(file: ImportedFile(url: URL(fileURLWithPath: "/tmp/x.m4a"), displayName: "x.m4a"))
    #expect(recorder.state == .recording)
    #expect(recorder.errorMessage != nil)
  }

  @Test func anUnreadableFileEndsIdleWithAMessage() async {
    let fake = FakeWindowTranscriber()
    let recorder = makeImporter(fake)
    await recorder.transcribe(file: ImportedFile(url: URL(fileURLWithPath: "/nonexistent/\(UUID()).m4a"),
                                                 displayName: "gone.m4a"))
    #expect(recorder.state == .idle)
    #expect(recorder.errorMessage != nil)
  }

  @Test func clearDropsTheTimingsWithTheText() async {
    let session = FakeTranscriptionSession(finalText: "words")
    session.segments = [TranscriptSegment(text: "words", start: 0, end: 1)]
    let recorder = makeRecorder(session)
    await recorder.start()
    await recorder.stopRecord()
    #expect(recorder.segments.count == 1)
    recorder.clearTranscript()
    #expect(recorder.transcribedText.isEmpty)
    #expect(recorder.segments.isEmpty)
  }

  #if PRO_VERSION
  @Test(.enabled(if: RealTimeWhisperStateTests.hasWav))
  func anImportIsSavedWithItsFileName() async throws {
    let container = try ModelContainer(
      for: Recording.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let fake = FakeWindowTranscriber(texts: ["Saved from a file."])
    let recorder = makeImporter(fake)
    recorder.modelContext = container.mainContext
    let file = try ImportedFile.stage(Self.wavFixture)
    defer { file.discard() }

    await recorder.transcribe(file: file)

    let saved = try container.mainContext.fetch(FetchDescriptor<Recording>())
    #expect(saved.count == 1)
    #expect(saved.first?.sourceFileName == "en.wav")
    #expect(saved.first?.title == "en")
    #expect(saved.first?.segments.isEmpty == false)
    #expect(recorder.lastSaved === saved.first)
  }
  #endif
}
