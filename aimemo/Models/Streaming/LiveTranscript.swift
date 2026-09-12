//
//  LiveTranscript.swift
//  aimemo
//
//  Committed text plus the in-flight window's provisional tail
//

import Foundation

/// The transcript as the user sees it: settled text, plus a tail that is still
/// being decoded and is rendered dimmed.
///
/// Stitching lives here rather than in the whisper actor because
/// `whisper_full_with_state` clears its results on entry — each decode returns
/// only its own window, so joining them is the app's job.
struct LiveTranscript: Equatable, Sendable {
  private(set) var committed: String = ""
  private(set) var provisional: String = ""
  /// Mean token probability of the provisional tail, 0…1.
  private(set) var provisionalConfidence: Float = 0

  var fullText: String {
    provisional.isEmpty ? committed : Self.join(committed, provisional)
  }

  var isEmpty: Bool { committed.isEmpty && provisional.isEmpty }

  /// Appends a decoded window and clears the provisional tail it replaces.
  mutating func commit(_ text: String) {
    let clean = Self.normalize(text)
    if !clean.isEmpty {
      committed = Self.join(committed, clean)
    }
    provisional = ""
    provisionalConfidence = 0
  }

  /// Replaces — never appends to — the provisional tail.
  mutating func setProvisional(_ text: String, confidence: Float) {
    provisional = Self.normalize(text)
    provisionalConfidence = confidence
  }

  mutating func clearProvisional() {
    provisional = ""
    provisionalConfidence = 0
  }

  /// Bounded tail of the committed text, seeded into the next window as
  /// context. Cut at a word boundary so a half-word never becomes a prompt.
  func promptTail(maxCharacters: Int = 480) -> String? {
    guard !committed.isEmpty else { return nil }
    guard committed.count > maxCharacters else { return committed }

    let tail = committed.suffix(maxCharacters)
    guard let space = tail.firstIndex(of: " ") else { return String(tail) }
    let cut = tail[tail.index(after: space)...]
    return cut.isEmpty ? String(tail) : String(cut)
  }

  /// Joins two fragments with exactly one space.
  static func join(_ left: String, _ right: String) -> String {
    if left.isEmpty { return right }
    if right.isEmpty { return left }
    return left + " " + right
  }

  /// Collapses whitespace and drops whisper's non-speech artefacts.
  ///
  /// whisper emits bracketed markers and music notes for non-speech audio;
  /// they are noise in a voice memo and must not reach the saved transcript.
  static func normalize(_ raw: String) -> String {
    var text = raw

    for pattern in [#"\[[^\]]*\]"#, #"\([^)]*\)"#, #"♪+"#] {
      text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
    }

    return text
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
