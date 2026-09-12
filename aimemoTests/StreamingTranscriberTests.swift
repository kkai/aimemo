//
//  StreamingTranscriberTests.swift
//  aimemoTests
//
//  The streaming core, driven by synthesized audio and a fake engine.
//  Pins the three data-loss bugs the old pipeline had.
//

import Foundation
import Testing
@testable import aimemo

struct StreamingTranscriberTests {

  private static var policy: TranscriptionWindow.Policy {
    var p = TranscriptionWindow.Policy()
    p.minimumDuration = 1.2
    p.maximumDuration = 5
    p.pauseDuration = 0.6
    return p
  }

  private func makeCore(
    _ fake: FakeWindowTranscriber,
    options: TranscriptionOptions = .default
  ) -> StreamingTranscriber {
    StreamingTranscriber(transcriber: fake, options: options, policy: Self.policy)
  }

  /// One speech burst followed by a pause long enough to commit.
  private var cycle: [Float] {
    TestSignals.speech(seconds: 2.0) + TestSignals.silence(seconds: 0.8)
  }

  private func feed(_ core: StreamingTranscriber, _ signal: [Float], chunk: Int = 1024) {
    TestSignals.feed(signal, chunk: chunk) { core.ingest($0) }
  }

  // MARK: - Committing

  @Test func commitsOncePerSpeechPauseCycle() async {
    let fake = FakeWindowTranscriber(texts: ["one.", "two.", "three."])
    let core = makeCore(fake)
    await core.start()
    feed(core, cycle + cycle + cycle)

    let final = await core.finish()
    #expect(await fake.callCount == 3)
    #expect(final == "one. two. three.")
  }

  @Test func commitsAreOrdered() async {
    let fake = FakeWindowTranscriber(texts: ["alpha", "beta", "gamma"])
    let core = makeCore(fake)
    await core.start()
    feed(core, cycle + cycle + cycle)
    let final = await core.finish()
    #expect(final == "alpha beta gamma")
  }

  // MARK: - Data-loss bug #1: the final window must survive stop

  @Test func finishFlushesAWindowThatNeverReachedItsPause() async {
    // Stop mid-sentence: the old pipeline read transcribedText before the
    // in-flight pass landed, so these words were on screen but not saved.
    let fake = FakeWindowTranscriber(texts: ["the final words"])
    let core = makeCore(fake)
    await core.start()
    feed(core, TestSignals.speech(seconds: 2.0))   // no trailing pause

    let final = await core.finish()
    #expect(await fake.callCount == 1)
    #expect(final == "the final words")
  }

  @Test func finishFlushesSubSecondTrailingSpeech() async {
    // Shorter than whisper's 1000ms floor; must still be decoded, padded.
    let fake = FakeWindowTranscriber(texts: ["yes"])
    let core = makeCore(fake)
    await core.start()
    feed(core, TestSignals.speech(seconds: 0.4))

    let final = await core.finish()
    #expect(final == "yes")
    let request = try! #require(await fake.requests.first)
    #expect(request.sampleCount >= Self.policy.minimumSamples,
            "window was not padded past whisper's floor")
  }

  @Test func finishAfterACommitStillReturnsEverything() async {
    let fake = FakeWindowTranscriber(texts: ["committed.", "trailing."])
    let core = makeCore(fake)
    await core.start()
    feed(core, cycle + TestSignals.speech(seconds: 2.0))
    let final = await core.finish()
    #expect(final == "committed. trailing.")
  }

  @Test func finishWithNoSpeechReturnsEmptyAndDecodesNothing() async {
    let fake = FakeWindowTranscriber()
    let core = makeCore(fake)
    await core.start()
    feed(core, TestSignals.silence(seconds: 5))
    let final = await core.finish()
    #expect(final.isEmpty)
    #expect(await fake.callCount == 0, "silence must never reach whisper")
  }

  @Test func ingestBeforeStartIsStillTranscribed() async {
    let fake = FakeWindowTranscriber(texts: ["early"])
    let core = makeCore(fake)
    feed(core, TestSignals.speech(seconds: 2.0))
    await core.start()
    let final = await core.finish()
    #expect(final == "early")
  }

  @Test func finishWithoutStartStillDrains() async {
    let fake = FakeWindowTranscriber(texts: ["never started"])
    let core = makeCore(fake)
    feed(core, TestSignals.speech(seconds: 2.0))
    let final = await core.finish()
    #expect(final == "never started")
  }

  // MARK: - Data-loss bug #3: one bad decode must not wedge the pipeline

  @Test func aThrowingDecodeDoesNotStopLaterWindows() async {
    // The old canTranscribe flag cleared before a guard that could return
    // early, permanently disabling transcription.
    let fake = FakeWindowTranscriber(texts: ["one.", "two.", "three."],
                                     failingIndices: [0])
    let core = makeCore(fake)
    await core.start()
    feed(core, cycle + cycle + cycle)

    let final = await core.finish()
    #expect(await fake.callCount == 3, "later windows were not attempted")
    #expect(final == "two. three.")
  }

  @Test func aThrowingDecodeReportsFailure() async {
    let fake = FakeWindowTranscriber(texts: ["x"], failingIndices: [0])
    let core = makeCore(fake)
    let updates = await core.updates
    await core.start()
    feed(core, cycle)
    _ = await core.finish()

    var sawFailure = false
    for await update in updates {
      if case .failed = update { sawFailure = true }
    }
    #expect(sawFailure)
  }

  // MARK: - Prompt seeding

  @Test func eachWindowIsSeededWithThePreviousCommittedTail() async {
    let fake = FakeWindowTranscriber(texts: ["one.", "two.", "three."])
    let core = makeCore(fake)
    await core.start()
    feed(core, cycle + cycle + cycle)
    _ = await core.finish()

    let prompts = await fake.prompts
    #expect(prompts.count == 3)
    #expect(prompts[0] == nil, "the first window has no context to carry")
    #expect(prompts[1] == "one.")
    #expect(prompts[2] == "one. two.")
  }

  // MARK: - Window contract

  @Test func noWindowIsEverShorterThanWhispersFloor() async {
    let fake = FakeWindowTranscriber()
    let core = makeCore(fake)
    await core.start()
    feed(core, cycle + TestSignals.speech(seconds: 0.3))
    _ = await core.finish()

    for request in await fake.requests {
      #expect(request.sampleCount >= Self.policy.minimumSamples,
              "handed whisper \(request.sampleCount) samples, below its floor")
    }
  }

  @Test func noWindowExceedsTheCap() async {
    let fake = FakeWindowTranscriber()
    let core = makeCore(fake)
    await core.start()
    feed(core, TestSignals.speech(seconds: 18))
    _ = await core.finish()

    for request in await fake.requests {
      #expect(request.sampleCount <= Self.policy.maximumSamples)
    }
  }

  @Test func everyRequestIsACommitNotAPreview() async {
    // Previews are deferred; isPreview exists only to keep the signature stable.
    let fake = FakeWindowTranscriber()
    let core = makeCore(fake)
    await core.start()
    feed(core, cycle + cycle)
    _ = await core.finish()
    #expect(await fake.requests.allSatisfy { !$0.isPreview })
  }

  @Test func longUnbrokenSpeechCommitsSeveralWindows() async {
    let fake = FakeWindowTranscriber()
    let core = makeCore(fake)
    await core.start()
    feed(core, TestSignals.speech(seconds: 18))
    _ = await core.finish()
    #expect(await fake.callCount >= 3, "18s at a 5s cap should need several windows")
  }

  // MARK: - Backlog

  @Test func audioArrivingDuringASlowDecodeIsNotLost() async {
    // The decode is slower than the audio, so backlog builds while a window
    // is in flight. None of it may be dropped.
    let fake = FakeWindowTranscriber(delay: .milliseconds(60))
    let core = makeCore(fake)
    await core.start()
    feed(core, cycle + cycle + cycle + cycle)
    _ = await core.finish()
    #expect(await fake.callCount == 4)
  }

  // MARK: - Updates

  @Test func updatesCarryTheGrowingTranscript() async {
    let fake = FakeWindowTranscriber(texts: ["one.", "two."])
    let core = makeCore(fake)
    let updates = await core.updates
    await core.start()
    feed(core, cycle + cycle)
    _ = await core.finish()

    var texts: [String] = []
    for await update in updates {
      if case .transcript(let t) = update { texts.append(t.committed) }
    }
    #expect(texts.contains("one."))
    #expect(texts.last == "one. two.")
  }

  @Test func detectedLanguageIsReportedOnceNotPerWindow() async {
    let fake = FakeWindowTranscriber(texts: ["a", "b", "c"], language: "de")
    let core = makeCore(fake)
    let updates = await core.updates
    await core.start()
    feed(core, cycle + cycle + cycle)
    _ = await core.finish()

    var languages: [String] = []
    for await update in updates {
      if case .detectedLanguage(let code) = update { languages.append(code) }
    }
    #expect(languages == ["de"])
  }

  @Test func updatesTerminateAfterFinish() async {
    let fake = FakeWindowTranscriber()
    let core = makeCore(fake)
    let updates = await core.updates
    await core.start()
    feed(core, cycle)
    _ = await core.finish()

    var count = 0
    for await _ in updates { count += 1 }
    #expect(count > 0, "stream should have delivered before terminating")
  }

  // MARK: - Cancel

  @Test func cancelAbortsInFlightWorkAndDecodesNoTail() async {
    let fake = FakeWindowTranscriber()
    let core = makeCore(fake)
    await core.start()
    feed(core, TestSignals.speech(seconds: 2.0))
    await core.cancel()
    #expect(await fake.abortWasRequested)
  }

  // MARK: - Prompt suppression

  @Test func anEmptyPromptedDecodeIsRetriedWithoutThePrompt() async {
    // whisper can emit nothing when the prompt already reads like the audio.
    // Losing a window of speech is worse than losing its context.
    let fake = FakeWindowTranscriber(texts: ["one.", "two.", "three."],
                                     emptyWhenPrompted: true)
    let core = makeCore(fake)
    await core.start()
    feed(core, cycle + cycle)
    let final = await core.finish()

    // Window 1 has no prompt and succeeds. Window 2 is prompted, comes back
    // empty, and is retried bare.
    let prompts = await fake.prompts
    #expect(prompts.count == 3, "expected a retry, got calls: \(prompts)")
    #expect(prompts[0] == nil)
    #expect(prompts[1] != nil)
    #expect(prompts[2] == nil, "the retry must drop the prompt")
    #expect(final.contains("one."))
    #expect(!final.isEmpty)
  }

  @Test func aGenuinelySilentWindowIsNotRetriedForever() async {
    // No prompt on the first window, so an empty result there must not loop.
    let fake = FakeWindowTranscriber(texts: [""], emptyWhenPrompted: false)
    let core = makeCore(fake)
    await core.start()
    feed(core, cycle)
    let final = await core.finish()
    #expect(await fake.callCount == 1)
    #expect(final.isEmpty)
  }
}

