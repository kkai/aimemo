//
//  ReviewPromptTests.swift
//  aimemoTests
//
//  Gating rules for the App Store review ask. Uses an isolated UserDefaults
//  suite so it never touches the host app's state.
//

import Foundation
import Testing
@testable import aimemo

struct ReviewPromptTests {

  /// A throwaway defaults suite per test.
  private static func freshDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
  }

  private static func install(_ defaults: UserDefaults, daysAgo: Double) -> Date {
    let now = Date()
    defaults.set(now.addingTimeInterval(-daysAgo * 86_400), forKey: "firstLaunchDate")
    return now
  }

  @Test func registerLaunchRecordsFirstLaunchOnce() {
    let defaults = Self.freshDefaults()
    let first = Date(timeIntervalSince1970: 1_000_000)
    ReviewPrompt.registerLaunch(now: first, defaults: defaults)
    ReviewPrompt.registerLaunch(now: first.addingTimeInterval(99_999), defaults: defaults)
    #expect(defaults.object(forKey: "firstLaunchDate") as? Date == first)
  }

  @Test func doesNotAskBeforeEnoughTranscriptions() {
    let defaults = Self.freshDefaults()
    let now = Self.install(defaults, daysAgo: 30)
    for _ in 1..<ReviewPrompt.transcriptionThreshold {
      #expect(ReviewPrompt.recordTranscription(now: now, defaults: defaults) == false)
    }
  }

  @Test func asksOnceThresholdAndAgeAreBothMet() {
    let defaults = Self.freshDefaults()
    let now = Self.install(defaults, daysAgo: 30)
    var asked = false
    for _ in 0..<ReviewPrompt.transcriptionThreshold {
      asked = ReviewPrompt.recordTranscription(now: now, defaults: defaults)
    }
    #expect(asked)
  }

  @Test func doesNotAskAFreshInstallHoweverBusy() {
    // Someone who transcribes twenty things on day one is still on day one.
    let defaults = Self.freshDefaults()
    let now = Self.install(defaults, daysAgo: 0)
    for _ in 0..<20 {
      #expect(ReviewPrompt.recordTranscription(now: now, defaults: defaults) == false)
    }
  }

  @Test func doesNotAskWithoutAKnownInstallDate() {
    let defaults = Self.freshDefaults()
    defaults.set(ReviewPrompt.transcriptionThreshold + 10, forKey: "successfulTranscriptionCount")
    #expect(ReviewPrompt.shouldRequest(defaults: defaults) == false)
  }

  @Test func doesNotAskTwiceForTheSameVersion() {
    let defaults = Self.freshDefaults()
    let now = Self.install(defaults, daysAgo: 30)
    defaults.set(ReviewPrompt.transcriptionThreshold, forKey: "successfulTranscriptionCount")
    #expect(ReviewPrompt.shouldRequest(now: now, defaults: defaults))

    ReviewPrompt.markRequested(defaults: defaults)
    #expect(ReviewPrompt.shouldRequest(now: now, defaults: defaults) == false)
  }

  @Test func asksAgainAfterAVersionBump() {
    let defaults = Self.freshDefaults()
    let now = Self.install(defaults, daysAgo: 30)
    defaults.set(ReviewPrompt.transcriptionThreshold, forKey: "successfulTranscriptionCount")
    defaults.set("0.0.1-ancient", forKey: "lastReviewPromptVersion")
    #expect(ReviewPrompt.shouldRequest(now: now, defaults: defaults))
  }

  @Test func countPersistsAcrossCalls() {
    let defaults = Self.freshDefaults()
    _ = Self.install(defaults, daysAgo: 30)
    _ = ReviewPrompt.recordTranscription(defaults: defaults)
    _ = ReviewPrompt.recordTranscription(defaults: defaults)
    #expect(defaults.integer(forKey: "successfulTranscriptionCount") == 2)
  }
}
