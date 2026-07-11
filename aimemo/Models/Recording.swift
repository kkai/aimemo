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

  init(
    timestamp: Date,
    duration: TimeInterval,
    transcriptText: String,
    title: String? = nil,
    summary: String? = nil
  ) {
    self.id = UUID()
    self.timestamp = timestamp
    self.duration = duration
    self.transcriptText = transcriptText
    self.title = title
    self.summary = summary
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

  var transcriptPreview: String {
    let maxLength = 100
    if transcriptText.count > maxLength {
      return String(transcriptText.prefix(maxLength)) + "..."
    }
    return transcriptText
  }
}
