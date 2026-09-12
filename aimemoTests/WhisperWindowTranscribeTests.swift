//
//  WhisperWindowTranscribeTests.swift
//  aimemoTests
//
//  The real whisper decode through the streaming path.
//
//  SLOW AND DELIBERATE. Each decode runs whisper on the simulator's CPU
//  fallback (no Metal), so a full pass is minutes, not seconds. Window policy
//  and pipeline behaviour are covered fast and deterministically in
//  TranscriptionWindowTests / StreamingTranscriberTests / RealAudioWindowingTests;
//  this suite exists only to prove the C interop and the whisper params that
//  those fakes cannot exercise. Run it before shipping, not on every edit:
//
//    xcodebuild test … -only-testing:aimemoTests/WhisperWindowTranscribeTests
//
//  Gated the same way as MultilingualTranscriptionTests: skipped when the model
//  or fixtures cannot be resolved. Serialized, and sharing one context, because
//  loading the model per test dominated the runtime and because abortInFlight()
//  on a shared actor must not race another test's decode.
//

import Foundation
import Testing
@testable import aimemo

@Suite(.serialized)
struct WhisperWindowTranscribeTests {

  // MARK: - Shared fixtures

  private static var sourceDir: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  }

  private static func fixture(_ base: String) -> [Float]? {
    let url = sourceDir.appendingPathComponent("Resources/audio/\(base).wav")
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try? WavFixture.load(url)
  }

  private static var modelURL: URL? {
    let name = WhisperModel.base.resourceName
    let src = sourceDir
      .deletingLastPathComponent()
      .appendingPathComponent("aimemo/Resources/models/\(name).bin")
    if FileManager.default.fileExists(atPath: src.path) { return src }
    return Bundle.main.url(forResource: name, withExtension: "bin", subdirectory: "models")
      ?? Bundle.main.url(forResource: name, withExtension: "bin")
  }

  /// One model load for the whole suite.
  private static let shared: WhisperContext? = {
    guard let url = modelURL else { return nil }
    return try? WhisperContext(path: url)
  }()

  private static var canRun: Bool {
    shared != nil && fixture("en") != nil && fixture("de") != nil
  }

  private func context() throws -> WhisperContext {
    try #require(Self.shared)
  }

  // MARK: - Interop: segments, timestamps, confidence, detection

  @Test(.enabled(if: WhisperWindowTranscribeTests.canRun))
  func windowedDecodeYieldsSegmentsTimestampsConfidenceAndLanguage() async throws {
    // One decode, four properties - each one is a thing single_segment=true /
    // no_timestamps=true used to make impossible.
    let samples = try #require(Self.fixture("de"))
    let duration = Double(samples.count) / 16_000

    let result = try await context().transcribe(window: samples, prompt: nil)
    print("[window] segments=\(result.segments.count) lang=\(result.detectedLanguageCode ?? "nil") text=\"\(result.text)\"")

    #expect(!result.segments.isEmpty, "single_segment=false should yield segments")
    #expect(result.detectedLanguageCode == "de")

    #expect(result.confidence > 0, "no token probabilities were collected")
    #expect(result.confidence <= 1.0001, "confidence \(result.confidence) is not a probability")

    for segment in result.segments {
      print("[timestamps] \(segment.start)-\(segment.end) p=\(segment.confidence)")
      #expect(segment.start >= 0)
      #expect(segment.end >= segment.start)
      // Window-relative, so they cannot run past the window itself.
      #expect(segment.end <= duration + 1.0,
              "segment end \(segment.end) exceeds window duration \(duration)")
    }

    let lower = result.text.lowercased()
    #expect(["fuchs", "hund", "wochenende"].contains { lower.contains($0) },
            "windowed decode lost the content: \"\(result.text)\"")
  }

  @Test(.enabled(if: WhisperWindowTranscribeTests.canRun))
  func pinnedLanguageIsNotEchoedBackAsADetection() async throws {
    var pinned = TranscriptionOptions.default
    pinned.language = .specific("de")
    let result = try await context().transcribe(
      window: try #require(Self.fixture("de")), prompt: nil, options: pinned)
    #expect(result.detectedLanguageCode == nil)
    #expect(!result.text.isEmpty)
  }

  @Test(.enabled(if: WhisperWindowTranscribeTests.canRun))
  func promptDoesNotLeakIntoTheTranscript() async throws {
    // prompt_tokens seed the decoder; they must never be emitted as text.
    let result = try await context().transcribe(
      window: try #require(Self.fixture("en")),
      prompt: "Zzyzx Kaikunze Anthropic, previously committed text.")
    let lower = result.text.lowercased()
    print("[prompt] \"\(result.text)\"")
    #expect(!lower.contains("zzyzx"), "prompt leaked: \"\(result.text)\"")
  }

  @Test(.enabled(if: WhisperWindowTranscribeTests.canRun))
  func translateStillWorksThroughTheWindowedPath() async throws {
    var options = TranscriptionOptions.default
    options.translateToEnglish = true
    let result = try await context().transcribe(
      window: try #require(Self.fixture("de")), prompt: nil, options: options)
    let lower = result.text.lowercased()
    print("[translate] \"\(result.text)\"")

    #expect(["fox", "dog", "weekend"].contains { lower.contains($0) },
            "translation lost: \"\(result.text)\"")
    #expect(!lower.contains("fuchs"), "still German: \"\(result.text)\"")
  }

  // MARK: - Cancellation

  @Test(.enabled(if: WhisperWindowTranscribeTests.canRun))
  func abortInFlightStopsARunningDecode() async throws {
    // abortInFlight must interrupt a decode already holding the actor, which is
    // why the token is nonisolated. A pre-set flag would not test this: every
    // decode resets it on entry so a stale abort cannot kill the next window.
    let ctx = try context()
    let samples = try #require(Self.fixture("en"))

    let decode = Task { try await ctx.transcribe(window: samples, prompt: nil) }
    try? await Task.sleep(for: .milliseconds(400))
    ctx.abortInFlight()

    var threw = false
    do { _ = try await decode.value } catch { threw = true }
    #expect(threw, "aborted decode should throw rather than return partial text")

    // And the context must still be usable afterwards.
    let after = try await ctx.transcribe(window: samples, prompt: nil)
    #expect(!after.text.isEmpty, "context was left unusable by the abort")
  }

  // MARK: - Whole pipeline on real audio

  @Test(.enabled(if: WhisperWindowTranscribeTests.canRun))
  func repeatedUtterancesCommitSeparateWindowsAndSurviveSuppression() async throws {
    // Two utterances separated by silence, in one language - the real shape of
    // a recording. It is also the worst case for prompting: window two is
    // seeded with the exact sentence it is about to hear again, and whisper
    // answers that with silence. StreamingTranscriber's unprompted retry is
    // what recovers it, so this exercises that path against the real model.
    let en = try #require(Self.fixture("en"))
    let gap = TestSignals.silence(seconds: 1.0)

    let core = StreamingTranscriber(transcriber: try context(), options: .default)
    await core.start()
    TestSignals.feed(en + gap + en, chunk: 1024) { core.ingest($0) }
    let final = await core.finish()
    print("[pipeline] \"\(final)\"")

    let occurrences = final.lowercased().components(separatedBy: "fox").count - 1
    #expect(occurrences >= 2,
            "expected both windows to survive, got \(occurrences) in \"\(final)\"")
    #expect(!final.lowercased().contains("[blank_audio]"),
            "non-speech marker survived normalization")
  }

  @Test(.enabled(if: WhisperWindowTranscribeTests.canRun))
  func autoDetectedLanguageIsPinnedForTheRestOfTheRecording() async throws {
    // German first, then English audio. Once German is detected the recording
    // stays German - per-window re-detection is unreliable on short audio and
    // a carried prompt can steer it. This asserts the decision, not an accident.
    let de = try #require(Self.fixture("de"))
    let en = try #require(Self.fixture("en"))
    let gap = TestSignals.silence(seconds: 1.0)

    let core = StreamingTranscriber(transcriber: try context(), options: .default)
    let updates = await core.updates
    await core.start()
    TestSignals.feed(de + gap + en, chunk: 1024) { core.ingest($0) }
    let final = await core.finish()
    print("[pinned pipeline] \"\(final)\"")

    var languages: [String] = []
    for await update in updates {
      if case .detectedLanguage(let code) = update { languages.append(code) }
    }
    #expect(languages == ["de"], "language should be reported once, got \(languages)")
    #expect(!final.isEmpty)
  }
}
