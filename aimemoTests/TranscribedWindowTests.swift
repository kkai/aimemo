//
//  TranscribedWindowTests.swift
//  aimemoTests
//

import Testing
@testable import aimemo

struct TranscribedWindowTests {

  private func segment(_ text: String, _ start: Double, _ end: Double, _ confidence: Float)
    -> TranscribedWindow.Segment {
    .init(text: text, start: start, end: end, confidence: confidence)
  }

  @Test func emptyWindowHasNoTextAndZeroConfidence() {
    #expect(TranscribedWindow.empty.text.isEmpty)
    #expect(TranscribedWindow.empty.confidence == 0)
  }

  @Test func textConcatenatesSegmentsAndNormalizes() {
    let window = TranscribedWindow(segments: [
      segment(" Hello", 0, 1, 0.9),
      segment(" world. ", 1, 2, 0.9),
    ])
    #expect(window.text == "Hello world.")
  }

  @Test func textStripsNonSpeechMarkersFromSegments() {
    let window = TranscribedWindow(segments: [segment("[BLANK_AUDIO]", 0, 1, 0.2)])
    #expect(window.text.isEmpty)
  }

  @Test func confidenceIsDurationWeighted() {
    // A long confident segment should outweigh a short doubtful one.
    let window = TranscribedWindow(segments: [
      segment("a", 0, 9, 1.0),
      segment("b", 9, 10, 0.0),
    ])
    #expect(window.confidence > 0.85)
  }

  @Test func confidenceOfASingleSegmentIsItsOwn() {
    let window = TranscribedWindow(segments: [segment("a", 0, 2, 0.42)])
    #expect(abs(window.confidence - 0.42) < 0.001)
  }

  @Test func zeroLengthSegmentsDoNotDivideByZero() {
    let window = TranscribedWindow(segments: [segment("a", 1, 1, 0.5)])
    #expect(window.confidence.isFinite)
  }

  @Test func detectedLanguageIsCarried() {
    let window = TranscribedWindow(segments: [], detectedLanguageCode: "de")
    #expect(window.detectedLanguageCode == "de")
  }
}
