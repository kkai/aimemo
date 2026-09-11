//
//  ReviewPrompt.swift
//  aimemo
//
//  Asks for an App Store rating after the app has demonstrably been useful
//

import Foundation
import StoreKit
import SwiftUI

/// Decides when to ask for a review.
///
/// The app had no rating prompt at all, and no analytics either, so ratings
/// were left entirely to people who sought out the store page unprompted.
///
/// Rules, deliberately conservative: only after a few successful transcriptions,
/// never twice for the same app version, and never before enough days have
/// passed that the ask is about the app rather than the install.
enum ReviewPrompt {
  private static let countKey = "successfulTranscriptionCount"
  private static let lastVersionKey = "lastReviewPromptVersion"
  private static let firstLaunchKey = "firstLaunchDate"

  /// Transcriptions before the first ask.
  static let transcriptionThreshold = 5
  /// Days since first launch before the first ask.
  static let minimumDaysInstalled = 3

  static var currentVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
  }

  /// Call once at launch so the install date exists before any counting.
  static func registerLaunch(now: Date = Date(), defaults: UserDefaults = .standard) {
    if defaults.object(forKey: firstLaunchKey) == nil {
      defaults.set(now, forKey: firstLaunchKey)
    }
  }

  /// Records a completed transcription and reports whether to ask now.
  static func recordTranscription(now: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
    let count = defaults.integer(forKey: countKey) + 1
    defaults.set(count, forKey: countKey)
    return shouldRequest(now: now, defaults: defaults)
  }

  static func shouldRequest(now: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
    guard defaults.integer(forKey: countKey) >= transcriptionThreshold else { return false }
    // One ask per version: Apple throttles anyway, but asking a user who has
    // already declined on this version is just noise.
    guard defaults.string(forKey: lastVersionKey) != currentVersion else { return false }
    guard let firstLaunch = defaults.object(forKey: firstLaunchKey) as? Date else { return false }
    let days = now.timeIntervalSince(firstLaunch) / 86_400
    return days >= Double(minimumDaysInstalled)
  }

  static func markRequested(defaults: UserDefaults = .standard) {
    defaults.set(currentVersion, forKey: lastVersionKey)
  }

  /// Asks the system, then records that we did so it is not asked again.
  @MainActor
  static func requestIfAppropriate(in scene: UIWindowScene?) {
    guard shouldRequest(), let scene else { return }
    AppStore.requestReview(in: scene)
    markRequested()
  }
}
