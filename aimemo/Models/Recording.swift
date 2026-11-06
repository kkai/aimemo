//
//  Recording.swift
//  aimemo
//
//  SwiftData model for storing transcript history
//

import Foundation
import SwiftData

@Model
final class Recording {
  // Core identification
  var id: UUID
  var timestamp: Date

  // Recording metadata
  var duration: TimeInterval
  var transcriptText: String

  // User-editable properties
  var title: String?

  // On-device AI summary (Foundation Models, iOS 26+)
  var summary: String?

  /// JSON of `[TranscriptSegment]`. Stored as data rather than a Codable
  /// array so the 2.5 store migrates with nothing but a new optional column.
  var segmentsData: Data?

  /// For transcripts made from a file: the file's name, shown in the detail
  /// view and used as the default title.
  var sourceFileName: String?

  init(
    timestamp: Date,
    duration: TimeInterval,
    transcriptText: String,
    title: String? = nil,
    summary: String? = nil,
    segments: [TranscriptSegment] = [],
    sourceFileName: String? = nil
  ) {
    self.id = UUID()
    self.timestamp = timestamp
    self.duration = duration
    self.transcriptText = transcriptText
    self.title = title
    self.summary = summary
    self.segmentsData = segments.isEmpty ? nil : try? JSONEncoder().encode(segments)
    self.sourceFileName = sourceFileName
  }

  /// Timed pieces of the transcript; empty for 2.5 recordings and for engines
  /// that gave no timings.
  var segments: [TranscriptSegment] {
    get {
      guard let segmentsData else { return [] }
      return (try? JSONDecoder().decode([TranscriptSegment].self, from: segmentsData)) ?? []
    }
    set { segmentsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
  }

  /// Everything the exporters need, in one value.
  var exportable: TranscriptExport {
    TranscriptExport(title: title, date: timestamp, duration: duration,
                     text: transcriptText, segments: segments, summary: summary,
                     sourceFileName: sourceFileName)
  }

  // MARK: - Computed Properties

  var displayTitle: String {
    if let title = title, !title.isEmpty {
      return title
    }
    return formattedDate
  }

  var formattedDate: String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: timestamp)
  }

  var formattedDuration: String {
    let minutes = Int(duration) / 60
    let seconds = Int(duration) % 60
    return String(format: "%d:%02d", minutes, seconds)
  }

  /// "2 minutes, 5 seconds", for VoiceOver; the badge shows "2:05".
  var spokenDuration: String {
    Duration.seconds(Int(duration))
      .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
  }

  var transcriptPreview: String {
    let maxLength = 100
    if transcriptText.count > maxLength {
      return String(transcriptText.prefix(maxLength)) + "..."
    }
    return transcriptText
  }
}
