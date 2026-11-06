//
//  TranscriptExport.swift
//  aimemo
//
//  Markdown, SRT and VTT renderings of a transcript
//

import Foundation

/// A transcript plus what the exporters print around it. Pure value, no I/O:
/// the rendering is tested as strings and the file writing is a few lines in
/// `TranscriptFile`.
struct TranscriptExport: Equatable, Sendable {
  var title: String?
  var date: Date
  var duration: TimeInterval
  var text: String
  var segments: [TranscriptSegment]
  var summary: String?
  var sourceFileName: String?

  init(title: String? = nil, date: Date, duration: TimeInterval, text: String,
       segments: [TranscriptSegment] = [], summary: String? = nil, sourceFileName: String? = nil) {
    self.title = title
    self.date = date
    self.duration = duration
    self.text = text
    self.segments = segments
    self.summary = summary
    self.sourceFileName = sourceFileName
  }

  enum Format: String, CaseIterable, Identifiable, Sendable {
    case markdown, srt, vtt

    var id: String { rawValue }

    var label: String {
      switch self {
      case .markdown: return "Markdown"
      case .srt: return "SRT subtitles"
      case .vtt: return "WebVTT subtitles"
      }
    }

    var fileExtension: String { rawValue == "markdown" ? "md" : rawValue }

    /// Subtitles need timings; Markdown works without them.
    var needsSegments: Bool { self != .markdown }
  }

  /// True when `format` can be produced from this transcript.
  func supports(_ format: Format) -> Bool {
    !format.needsSegments || !segments.isEmpty
  }

  var hasTimings: Bool { !segments.isEmpty }

  /// The transcript in `format`. Nil for a subtitle format without timings.
  func render(_ format: Format) -> String? {
    switch format {
    case .markdown: return markdown
    case .srt: return segments.isEmpty ? nil : srt
    case .vtt: return segments.isEmpty ? nil : vtt
    }
  }

  // MARK: - File names

  /// "Thursday planning.md", or "ai-Memo 2026-11-06 14.32.md" when untitled.
  /// Characters that are not allowed in file names are replaced.
  func fileName(for format: Format) -> String {
    let base: String
    if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty {
      base = title
    } else if let sourceFileName, !sourceFileName.isEmpty {
      base = (sourceFileName as NSString).deletingPathExtension
    } else {
      base = "ai-Memo " + Self.fileDateFormatter.string(from: date)
    }
    let unsafe = CharacterSet(charactersIn: "/\\:?%*|\"<>")
    let clean = base.components(separatedBy: unsafe).joined(separator: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmed = String(clean.prefix(80))
    return (trimmed.isEmpty ? "ai-Memo" : trimmed) + "." + format.fileExtension
  }

  private static let fileDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH.mm"
    return formatter
  }()

  // MARK: - Markdown

  /// A heading, a date line, the summary if there is one, then the transcript:
  /// one paragraph per timed segment with a `[m:ss]` stamp, or the plain text
  /// when there are no timings.
  var markdown: String {
    var lines: [String] = []
    lines.append("# " + (displayTitle))
    lines.append("")
    var meta = Self.markdownDateFormatter.string(from: date) + " · " + Self.clock(duration)
    if let sourceFileName, !sourceFileName.isEmpty {
      meta += " · from " + sourceFileName
    }
    lines.append("*" + meta + "*")
    lines.append("")

    if let summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
      lines.append("## Summary")
      lines.append("")
      lines.append(summary)
      lines.append("")
    }

    lines.append("## Transcript")
    lines.append("")
    if segments.isEmpty {
      lines.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
    } else {
      for segment in segments {
        lines.append("**[\(Self.clock(segment.start))]** " + segment.text)
        lines.append("")
      }
      if lines.last == "" { lines.removeLast() }
    }
    return lines.joined(separator: "\n") + "\n"
  }

  private var displayTitle: String {
    if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty { return title }
    return "Voice memo, " + Self.markdownDateFormatter.string(from: date)
  }

  private static let markdownDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .long
    formatter.timeStyle = .short
    return formatter
  }()

  // MARK: - Subtitles

  /// SubRip: numbered cues, `HH:MM:SS,mmm --> HH:MM:SS,mmm`, blank line between.
  var srt: String {
    cues().enumerated().map { index, cue in
      "\(index + 1)\n\(Self.stamp(cue.start, separator: ",")) --> \(Self.stamp(cue.end, separator: ","))\n\(cue.text)\n"
    }.joined(separator: "\n")
  }

  /// WebVTT: the `WEBVTT` header, then the same cues with a `.` before the
  /// milliseconds and no numbering.
  var vtt: String {
    "WEBVTT\n\n" + cues().map { cue in
      "\(Self.stamp(cue.start, separator: ".")) --> \(Self.stamp(cue.end, separator: "."))\n\(cue.text)\n"
    }.joined(separator: "\n")
  }

  /// Segments as players expect them: monotonic, never zero-length, never
  /// overlapping the next cue. Whisper can end one segment a hair after the
  /// next begins when windows are stitched; the second cue then starts where
  /// the first ends.
  private func cues() -> [TranscriptSegment] {
    var result: [TranscriptSegment] = []
    for raw in segments {
      var cue = raw
      if let previous = result.last, cue.start < previous.end {
        cue.start = previous.end
      }
      if cue.end <= cue.start { cue.end = cue.start + 0.5 }
      result.append(cue)
    }
    return result
  }

  /// `00:01:02,345` or `00:01:02.345`.
  static func stamp(_ seconds: TimeInterval, separator: String) -> String {
    let clamped = max(0, seconds)
    let whole = Int(clamped)
    let millis = Int(((clamped - Double(whole)) * 1000).rounded())
    let (h, m, s, ms) = millis == 1000
      ? ((whole + 1) / 3600, (whole + 1) % 3600 / 60, (whole + 1) % 60, 0)
      : (whole / 3600, whole % 3600 / 60, whole % 60, millis)
    return String(format: "%02d:%02d:%02d%@%03d", h, m, s, separator, ms)
  }

  /// `1:05` or `1:02:05`, for the Markdown stamps and the duration line.
  static func clock(_ seconds: TimeInterval) -> String {
    let total = Int(max(0, seconds).rounded(.down))
    if total >= 3600 {
      return String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
    }
    return String(format: "%d:%02d", total / 60, total % 60)
  }
}
