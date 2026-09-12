//
//  TranscriptionWindowTests.swift
//  aimemoTests
//
//  The commit policy: deterministic, no clocks, no sleeps, no model.
//

import Foundation
import Testing
@testable import aimemo

struct TranscriptionWindowTests {

  /// Small limits so tests describe seconds, not minutes.
  private static var policy: TranscriptionWindow.Policy {
    var p = TranscriptionWindow.Policy()
    p.minimumDuration = 1.2
    p.maximumDuration = 5
    p.pauseDuration = 0.6
    return p
  }

  private func makeWindow() -> TranscriptionWindow {
    TranscriptionWindow(policy: Self.policy)
  }

  /// Drives a window with a signal in tap-sized chunks, collecting decisions
  /// and closing whenever one says to.
  @discardableResult
  private func run(
    _ window: inout TranscriptionWindow,
    _ signal: [Float],
    chunk: Int = 1024,
    closed: inout [TranscriptionWindow.Closed]
  ) -> [TranscriptionWindow.Decision] {
    var decisions: [TranscriptionWindow.Decision] = []
    var index = 0
    while index < signal.count {
      let end = min(index + chunk, signal.count)
      let decision = window.append(Array(signal[index..<end]))
      decisions.append(decision)
      if case .commit(let reason) = decision {
        closed.append(window.close(reason: reason))
      }
      index = end
    }
    return decisions
  }

  // MARK: - Not committing

  @Test func emptyWindowWaits() {
    var window = makeWindow()
    #expect(window.append([]) == .wait)
    #expect(window.isEmpty)
    #expect(!window.containsSpeech)
  }

  @Test func speechShorterThanMinimumNeverCommits() {
    // 1.0s of speech then a long pause: below whisper's decodable floor.
    var window = makeWindow()
    var closed: [TranscriptionWindow.Closed] = []
    let decisions = run(&window, TestSignals.speech(seconds: 1.0) + TestSignals.silence(seconds: 2.0),
                        closed: &closed)
    #expect(!decisions.contains { if case .commit = $0 { return true }; return false })
    #expect(closed.isEmpty)
  }

  @Test func pauseShorterThanThresholdDoesNotCommit() {
    var window = makeWindow()
    var closed: [TranscriptionWindow.Closed] = []
    run(&window, TestSignals.speech(seconds: 2.0) + TestSignals.silence(seconds: 0.3),
        closed: &closed)
    #expect(closed.isEmpty)
  }

  // MARK: - Committing

  @Test func pauseAfterMinimumCommits() {
    var window = makeWindow()
    var closed: [TranscriptionWindow.Closed] = []
    run(&window, TestSignals.speech(seconds: 2.0) + TestSignals.silence(seconds: 0.8),
        closed: &closed)
    #expect(closed.count == 1)
    #expect(closed.first?.reason == .pause)
    #expect(window.sampleCount == 0)
  }

  @Test func forceCommitsAtMaximumDuration() {
    // Unbroken speech past the ceiling must still make progress.
    var window = makeWindow()
    var closed: [TranscriptionWindow.Closed] = []
    run(&window, TestSignals.speech(seconds: 7.0), closed: &closed)
    #expect(closed.count >= 1)
    #expect(closed.first?.reason == .maximumDuration)
  }

  @Test func noWindowEverExceedsTheMaximum() {
    // Guards the overshoot a large chunk could otherwise cause.
    for chunk in [160, 1024, 16_000, 48_000] {
      var window = makeWindow()
      var closed: [TranscriptionWindow.Closed] = []
      run(&window, TestSignals.speech(seconds: 12), chunk: chunk, closed: &closed)
      let cap = Self.policy.maximumSamples
      for window in closed {
        #expect(window.samples.count <= cap,
                "chunk \(chunk): window of \(window.samples.count) exceeds cap \(cap)")
      }
    }
  }

  @Test func repeatedSpeechPauseCyclesCommitOncePerCycle() {
    var window = makeWindow()
    var closed: [TranscriptionWindow.Closed] = []
    let cycle = TestSignals.speech(seconds: 2.0) + TestSignals.silence(seconds: 0.8)
    run(&window, cycle + cycle + cycle, closed: &closed)
    #expect(closed.count == 3)
    #expect(closed.allSatisfy { $0.reason == .pause })
  }

  // MARK: - Silence

  @Test func silenceOnlyNeverCommitsAndNeverGrows() {
    // The regression this guards: dropping silence must not reintroduce
    // unbounded buffering.
    var window = makeWindow()
    var closed: [TranscriptionWindow.Closed] = []
    run(&window, TestSignals.silence(seconds: 30), closed: &closed)
    #expect(closed.isEmpty)
    #expect(window.sampleCount == 0)
    #expect(window.pendingCount < Self.policy.samplesPerFrame + 1024)
  }

  @Test func roomToneOnlyNeverCommits() {
    var window = makeWindow()
    var closed: [TranscriptionWindow.Closed] = []
    run(&window, TestSignals.roomTone(seconds: 20), closed: &closed)
    #expect(closed.isEmpty)
    #expect(window.sampleCount == 0)
  }

  @Test func leadingSilenceIsDiscardedSoWindowsStartOnSpeech() {
    var window = makeWindow()
    var closed: [TranscriptionWindow.Closed] = []
    run(&window, TestSignals.silence(seconds: 5) + TestSignals.speech(seconds: 2.0)
        + TestSignals.silence(seconds: 0.8), closed: &closed)
    #expect(closed.count == 1)
    // ~2s of speech plus the 0.6s pause that closed it - not the 5s of silence.
    let captured = closed[0].duration
    #expect(captured < 3.5, "window carried \(captured)s, expected leading silence dropped")
  }

  // MARK: - Chunk-size independence

  @Test func decisionsAreIndependentOfChunkSize() {
    let signal = TestSignals.speech(seconds: 2.0) + TestSignals.silence(seconds: 0.8)
      + TestSignals.speech(seconds: 2.0) + TestSignals.silence(seconds: 0.8)

    var reference: [Int] = []
    for chunk in [160, 320, 1024, 4096, 16_000] {
      var window = makeWindow()
      var closed: [TranscriptionWindow.Closed] = []
      run(&window, signal, chunk: chunk, closed: &closed)
      let lengths = closed.map(\.samples.count)
      if reference.isEmpty {
        reference = lengths
        #expect(lengths.count == 2, "expected two commits, got \(lengths.count)")
      } else {
        #expect(lengths == reference,
                "chunk \(chunk) produced \(lengths), expected \(reference)")
      }
    }
  }

  // MARK: - Closing and flushing

  @Test func closePadsShortTailPastWhispersFloor() {
    // whisper.cpp:5253-5259 returns zero segments below 1000ms, silently.
    var window = makeWindow()
    _ = window.append(TestSignals.speech(seconds: 0.4))
    let closed = window.close(reason: .flush)
    #expect(closed.samples.count == Self.policy.minimumSamples)
    #expect(closed.duration < 0.5, "true duration should be reported unpadded")
    #expect(closed.samples.suffix(100).allSatisfy { $0 == 0 }, "tail should be zero padding")
  }

  @Test func closeEmptiesTheWindow() {
    var window = makeWindow()
    _ = window.append(TestSignals.speech(seconds: 2.0))
    _ = window.close(reason: .flush)
    #expect(window.sampleCount == 0)
    #expect(!window.containsSpeech)
  }

  @Test func prepareFlushCommitsBufferedSpeech() {
    var window = makeWindow()
    _ = window.append(TestSignals.speech(seconds: 0.8))
    #expect(window.prepareFlush() == .commit(.flush))
  }

  @Test func prepareFlushWaitsWhenNothingWasSpoken() {
    var window = makeWindow()
    _ = window.append(TestSignals.silence(seconds: 3))
    #expect(window.prepareFlush() == .wait)
  }

  @Test func prepareFlushKeepsSubFrameResidue() {
    // Trailing speech shorter than one 20ms frame must still reach whisper.
    var window = makeWindow()
    _ = window.append(TestSignals.speech(seconds: 1.0))
    let before = window.sampleCount
    _ = window.append(Array(TestSignals.speech(seconds: 0.01)))  // < one frame
    #expect(window.sampleCount == before, "residue should not be classified yet")
    _ = window.prepareFlush()
    #expect(window.sampleCount > before, "residue should be folded in at flush")
  }

  // MARK: - Conservation

  @Test func backlogSurvivesCloseAndIsNotDropped() {
    // A chunk larger than the window cap must carry its remainder forward
    // rather than losing it in close().
    var window = makeWindow()
    let decision = window.append(TestSignals.speech(seconds: 12))
    #expect(decision == .commit(.maximumDuration))
    let first = window.close(reason: .maximumDuration)
    #expect(first.samples.count == Self.policy.maximumSamples)
    // The remainder was retained and immediately refilled the next window.
    #expect(window.sampleCount > 0, "backlog was dropped by close()")
  }

  @Test func noSpeechIsLostAcrossConsecutiveWindows() {
    var window = makeWindow()
    var closed: [TranscriptionWindow.Closed] = []
    run(&window, TestSignals.speech(seconds: 30), closed: &closed)
    while case .commit(let reason) = window.prepareFlush() {
      closed.append(window.close(reason: reason))
    }
    let captured = closed.reduce(0.0) { $0 + $1.duration }
    // Allow a frame of slack at the boundaries; nothing substantial may vanish.
    #expect(captured > 29.0, "only \(captured)s of 30s survived windowing")
  }

  @Test func flushCanRequireMoreThanOneWindow() {
    // A long backlog holds more than one window's worth, so finish() must loop.
    var window = makeWindow()
    _ = window.append(TestSignals.speech(seconds: 12))
    var windows = 0
    while case .commit(let reason) = window.prepareFlush() {
      _ = window.close(reason: reason)
      windows += 1
      if windows > 10 { break }
    }
    #expect(windows >= 2, "expected the backlog to need multiple windows, got \(windows)")
  }
}
