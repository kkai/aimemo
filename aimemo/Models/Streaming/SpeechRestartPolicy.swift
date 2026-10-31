//
//  SpeechRestartPolicy.swift
//  aimemo
//
//  Whether an Apple Speech run that ended by itself is restarted
//

import Foundation

/// Decides what happens when a recognition run ends without the user asking.
///
/// Normally the answer is "start another one": server recognition ends every
/// run after about a minute, and long-form dictation is a chain of runs. What
/// must not happen is a tight loop against a recognizer that fails as soon as
/// it starts (offline on a server-only language, say), so several runs in a
/// row that each die within `minimumHealthyRun` stop the recording instead.
struct SpeechRestartPolicy: Sendable {

  enum Decision: Equatable, Sendable {
    case restart
    case giveUp(message: String)
  }

  var minimumHealthyRun: TimeInterval = 2
  var maxQuickEndsInARow = 3

  private(set) var quickEndsInARow = 0
  private var runStart: Date?

  mutating func runStarted(at date: Date) {
    runStart = date
  }

  mutating func runEnded(_ end: SpeechRunEnd, at date: Date) -> Decision {
    let lasted = runStart.map { date.timeIntervalSince($0) } ?? 0
    runStart = nil
    if lasted < minimumHealthyRun {
      quickEndsInARow += 1
    } else {
      quickEndsInARow = 0
    }
    guard quickEndsInARow >= maxQuickEndsInARow else { return .restart }
    return .giveUp(message: Self.message(for: end))
  }

  static func message(for end: SpeechRunEnd) -> String {
    switch end {
    case .finished:
      return "Apple Speech kept stopping, so the recording ended. The transcript up to that point was kept."
    case .failed(let reason):
      return "Apple Speech stopped (\(reason)). The transcript up to that point was kept."
    }
  }

  /// Message for a restart that could not even begin.
  static func message(forRestartError error: Error) -> String {
    "Apple Speech stopped (\(error.localizedDescription)). The transcript up to that point was kept."
  }
}
