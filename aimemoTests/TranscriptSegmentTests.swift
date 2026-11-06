//
//  TranscriptSegmentTests.swift
//  aimemoTests
//
//  Where timings come from: window offsets, run offsets, word merging.
//

import Foundation
import Testing
@testable import aimemo

struct TranscriptSegmentTests {

  @Test func windowSegmentsAreShiftedByTheWindowOffset() {
    let window = TranscribedWindow(segments: [
      .init(text: " Hello", start: 0.2, end: 1.0, confidence: 0.9),
      .init(text: " [BLANK_AUDIO]", start: 1.0, end: 1.5, confidence: 0.1),
      .init(text: " world.", start: 1.5, end: 2.0, confidence: 0.9),
    ])
    let shifted = TranscriptSegment.fromWindow(window, offset: 30)
    #expect(shifted == [
      TranscriptSegment(text: "Hello", start: 30.2, end: 31.0),
      TranscriptSegment(text: "world.", start: 31.5, end: 32.0),
    ])
  }

  @Test func endNeverPrecedesStart() {
    #expect(TranscriptSegment(text: "x", start: 5, end: 4).end == 5)
  }

  @Test func liveTranscriptKeepsSegmentsWithTheText() {
    var transcript = LiveTranscript()
    transcript.commit("one", segments: [TranscriptSegment(text: "one", start: 0, end: 1)])
    transcript.commit("", segments: [TranscriptSegment(text: "ghost", start: 1, end: 2)])
    transcript.commit("two", segments: [TranscriptSegment(text: "two", start: 2, end: 3)])
    #expect(transcript.committed == "one two")
    #expect(transcript.committedSegments.map(\.text) == ["one", "two"])
  }

  @Test func roundTripsThroughJSON() throws {
    let segments = [TranscriptSegment(text: "a", start: 0.25, end: 1.5)]
    let data = try JSONEncoder().encode(segments)
    #expect(try JSONDecoder().decode([TranscriptSegment].self, from: data) == segments)
  }

  // MARK: - Apple Speech word merging

  @Test func wordsMergeIntoPhrasesUpToFiveSeconds() {
    let words = (0..<12).map { i in
      TranscriptSegment(text: "w\(i)", start: Double(i), end: Double(i) + 0.8)
    }
    let merged = AppleSpeechTranscriptionSession.merged(words)
    // w0…w4 fit in 5 s (w4 ends at 4.8); w5 would end at 5.8.
    #expect(merged.map(\.text) == ["w0 w1 w2 w3 w4", "w5 w6 w7 w8 w9", "w10 w11"])
    #expect(merged.first?.start == 0)
    #expect(merged.first?.end == 4.8)
  }

  @Test func aSentenceEndClosesThePhrase() {
    let words = [
      TranscriptSegment(text: "Hello", start: 0, end: 0.5),
      TranscriptSegment(text: "there.", start: 0.6, end: 1.0),
      TranscriptSegment(text: "Next", start: 1.2, end: 1.6),
    ]
    #expect(AppleSpeechTranscriptionSession.merged(words).map(\.text) == ["Hello there.", "Next"])
  }

  @Test func mergingNothingGivesNothing() {
    #expect(AppleSpeechTranscriptionSession.merged([]).isEmpty)
  }
}
