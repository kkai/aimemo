//
//  ImportedFile.swift
//  aimemo
//
//  Brings a picked or shared file inside the sandbox before it is read
//

import Foundation

/// A file the user handed to the app, copied to a private temporary folder.
///
/// The picker's URL is security-scoped and only valid while access is held;
/// a shared file lands in `Documents/Inbox`, which iOS expects the app to
/// clean. Copying once, up front, means the reader never has to care which
/// it was, and a one-hour transcription cannot lose its source midway.
struct ImportedFile: Sendable, Equatable {
  let url: URL
  /// The name the user knows the file by.
  let displayName: String

  enum StageError: LocalizedError {
    case noAccess
    var errorDescription: String? { "The file could not be opened." }
  }

  /// Copies `source` into the app's temporary folder and returns the copy.
  static func stage(_ source: URL) throws -> ImportedFile {
    let scoped = source.startAccessingSecurityScopedResource()
    defer { if scoped { source.stopAccessingSecurityScopedResource() } }

    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("Imports", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let destination = folder.appendingPathComponent(source.lastPathComponent)
    do {
      try FileManager.default.copyItem(at: source, to: destination)
    } catch {
      throw scoped ? error : StageError.noAccess
    }
    // A share-sheet hand-off is a copy in Documents/Inbox; it has done its job.
    if source.pathComponents.contains("Inbox") {
      try? FileManager.default.removeItem(at: source)
    }
    return ImportedFile(url: destination, displayName: source.lastPathComponent)
  }

  /// Removes the staged copy. Safe to call twice.
  func discard() {
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
  }

  /// "Lecture 4", from "Lecture 4.m4a". A generic name like Voice Memos'
  /// "New Recording 12" is not worth keeping as a title; the auto-title runs.
  var suggestedTitle: String? {
    let base = (displayName as NSString).deletingPathExtension
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !base.isEmpty, !base.hasPrefix("."), !Self.isGeneric(base) else { return nil }
    return base
  }

  static func isGeneric(_ name: String) -> Bool {
    let lower = name.lowercased()
    let prefixes = ["new recording", "recording", "audio", "voice", "memo", "untitled", "img_", "mov_", "video"]
    guard prefixes.contains(where: { lower.hasPrefix($0) }) else { return false }
    // "Recording 12" is generic; "Recording of the board meeting" is a title.
    let rest = prefixes.compactMap { lower.hasPrefix($0) ? String(lower.dropFirst($0.count)) : nil }
      .min(by: { $0.count < $1.count }) ?? ""
    return rest.allSatisfy { $0.isNumber || $0 == " " || $0 == "-" || $0 == "_" || $0 == "." || $0 == ":" }
  }
}
