//
//  SilenceWatchTests.swift
//  aimemoTests
//
//  The "No audio" cue and the Apple Speech restart decision, both pure.
//

import Foundation
import Testing
@testable import aimemo

struct SilenceWatchTests {
  private let t0 = Date(timeIntervalSinceReferenceDate: 0)

  @Test func notSilentBeforeTheLimit() {
    var watch = SilenceWatch()
    watch.reset(at: t0)
    watch.record(level: 0, at: t0 + 4)
    #expect(!watch.isSilent(at: t0 + 4.9))
  }

  @Test func zerosForLongerThanTheLimitAreSilent() {
    var watch = SilenceWatch()
    watch.reset(at: t0)
    for second in 1...6 { watch.record(level: 0, at: t0 + Double(second)) }
    #expect(watch.isSilent(at: t0 + 6))
  }

  @Test func noLevelsAtAllAlsoCountAsSilent() {
    var watch = SilenceWatch()
    watch.reset(at: t0)
    #expect(watch.isSilent(at: t0 + 5.5))
  }

  @Test func anyRealSoundRestartsTheClock() {
    var watch = SilenceWatch()
    watch.reset(at: t0)
    watch.record(level: 0.02, at: t0 + 4)
    #expect(!watch.isSilent(at: t0 + 8))
    #expect(watch.isSilent(at: t0 + 9.5))
  }

  @Test func aQuietRoomIsNotSilence() {
    // Room tone at about -60 dBFS reads as 0.01 on the meter.
    var watch = SilenceWatch()
    watch.reset(at: t0)
    for tick in 1...100 { watch.record(level: 0.01, at: t0 + Double(tick) / 10) }
    #expect(!watch.isSilent(at: t0 + 10))
  }

  @Test func neverSilentBeforeAReset() {
    #expect(!SilenceWatch().isSilent(at: t0 + 100))
  }
}

struct SpeechRestartPolicyTests {
  private let t0 = Date(timeIntervalSinceReferenceDate: 0)

  @Test func aLongRunIsAlwaysRestarted() {
    var policy = SpeechRestartPolicy()
    for minute in 0..<10 {
      policy.runStarted(at: t0 + Double(minute) * 60)
      #expect(policy.runEnded(.finished, at: t0 + Double(minute) * 60 + 59) == .restart)
    }
  }

  @Test func threeQuickDeathsInARowGiveUp() {
    var policy = SpeechRestartPolicy()
    var decisions: [SpeechRestartPolicy.Decision] = []
    for i in 0..<3 {
      policy.runStarted(at: t0 + Double(i))
      decisions.append(policy.runEnded(.failed(message: "offline"), at: t0 + Double(i) + 0.3))
    }
    #expect(decisions.prefix(2).allSatisfy { $0 == .restart })
    #expect(decisions.last == .giveUp(message: SpeechRestartPolicy.message(for: .failed(message: "offline"))))
  }

  @Test func aHealthyRunInBetweenResetsTheCount() {
    var policy = SpeechRestartPolicy()
    policy.runStarted(at: t0); _ = policy.runEnded(.finished, at: t0 + 0.5)
    policy.runStarted(at: t0 + 1); _ = policy.runEnded(.finished, at: t0 + 1.5)
    policy.runStarted(at: t0 + 2); _ = policy.runEnded(.finished, at: t0 + 30)
    #expect(policy.quickEndsInARow == 0)
    policy.runStarted(at: t0 + 31)
    #expect(policy.runEnded(.finished, at: t0 + 31.5) == .restart)
  }

  @Test func theGiveUpMessageSaysTheTextWasKept() {
    let message = SpeechRestartPolicy.message(for: .failed(message: "No connection"))
    #expect(message.contains("No connection"))
    #expect(message.contains("kept"))
  }
}
