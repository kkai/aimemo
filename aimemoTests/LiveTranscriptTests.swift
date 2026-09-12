//
//  LiveTranscriptTests.swift
//  aimemoTests
//
//  Stitching, normalization and prompt seeding.
//

import Testing
@testable import aimemo

struct LiveTranscriptTests {

  // MARK: - Committing

  @Test func startsEmpty() {
    let transcript = LiveTranscript()
    #expect(transcript.isEmpty)
    #expect(transcript.fullText.isEmpty)
  }

  @Test func commitJoinsWithExactlyOneSpace() {
    var transcript = LiveTranscript()
    transcript.commit(" Hello.")
    #expect(transcript.committed == "Hello.")
    transcript.commit("  World. ")
    #expect(transcript.committed == "Hello. World.")
  }

  @Test func commitIgnoresEmptyAndWhitespaceOnlyWindows() {
    var transcript = LiveTranscript()
    transcript.commit("Hello.")
    transcript.commit("   ")
    transcript.commit("")
    #expect(transcript.committed == "Hello.")
  }

  @Test func commitClearsTheProvisionalTail() {
    var transcript = LiveTranscript()
    transcript.setProvisional("guessing", confidence: 0.4)
    transcript.commit("Settled.")
    #expect(transcript.provisional.isEmpty)
    #expect(transcript.provisionalConfidence == 0)
    #expect(transcript.fullText == "Settled.")
  }

  // MARK: - Provisional tail

  @Test func provisionalIsReplacedNotAppended() {
    var transcript = LiveTranscript()
    transcript.setProvisional("the quick", confidence: 0.5)
    transcript.setProvisional("the quick brown", confidence: 0.6)
    #expect(transcript.provisional == "the quick brown")
  }

  @Test func fullTextJoinsCommittedAndProvisional() {
    var transcript = LiveTranscript()
    transcript.commit("Settled.")
    transcript.setProvisional("still guessing", confidence: 0.5)
    #expect(transcript.fullText == "Settled. still guessing")
  }

  @Test func clearProvisionalLeavesCommittedAlone() {
    var transcript = LiveTranscript()
    transcript.commit("Settled.")
    transcript.setProvisional("guess", confidence: 0.9)
    transcript.clearProvisional()
    #expect(transcript.fullText == "Settled.")
  }

  // MARK: - Normalization

  @Test func normalizeStripsWhisperNonSpeechMarkers() {
    // whisper emits these for silence and music; they are noise in a memo.
    #expect(LiveTranscript.normalize("[BLANK_AUDIO]") == "")
    #expect(LiveTranscript.normalize("Hello [inaudible] world") == "Hello world")
    #expect(LiveTranscript.normalize("(upbeat music)") == "")
    #expect(LiveTranscript.normalize("♪♪♪") == "")
  }

  @Test func normalizeCollapsesWhitespace() {
    #expect(LiveTranscript.normalize("  a   b \n c  ") == "a b c")
  }

  @Test func normalizeLeavesOrdinaryTextAlone() {
    let text = "The quick brown fox jumps over the lazy dog."
    #expect(LiveTranscript.normalize(text) == text)
  }

  @Test func commitNormalizesBeforeStoring() {
    var transcript = LiveTranscript()
    transcript.commit("Hello [BLANK_AUDIO] world")
    #expect(transcript.committed == "Hello world")
  }

  // MARK: - Prompt seeding

  @Test func promptTailIsNilWhenNothingIsCommitted() {
    #expect(LiveTranscript().promptTail() == nil)
  }

  @Test func promptTailReturnsShortTranscriptsWhole() {
    var transcript = LiveTranscript()
    transcript.commit("Hello world.")
    #expect(transcript.promptTail() == "Hello world.")
  }

  @Test func promptTailIsBoundedAndCutAtAWordBoundary() {
    var transcript = LiveTranscript()
    transcript.commit(String(repeating: "alpha beta ", count: 200))  // ~2200 chars
    let tail = try! #require(transcript.promptTail(maxCharacters: 100))
    #expect(tail.count <= 100)
    #expect(!tail.hasPrefix(" "))
    // Cut at a boundary, so the prompt never starts mid-word.
    #expect(tail.hasPrefix("alpha") || tail.hasPrefix("beta"))
  }

  @Test func promptTailTracksTheMostRecentText() {
    var transcript = LiveTranscript()
    transcript.commit(String(repeating: "old ", count: 300))
    transcript.commit("the newest sentence.")
    let tail = try! #require(transcript.promptTail(maxCharacters: 60))
    #expect(tail.hasSuffix("the newest sentence."))
  }

  // MARK: - join

  @Test func joinHandlesEmptyOperands() {
    #expect(LiveTranscript.join("", "b") == "b")
    #expect(LiveTranscript.join("a", "") == "a")
    #expect(LiveTranscript.join("a", "b") == "a b")
  }
}
