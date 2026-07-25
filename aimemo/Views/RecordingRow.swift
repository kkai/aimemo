//
//  RecordingRow.swift
//  aimemo
//
//  Row component for displaying a recording in the list
//

import SwiftUI

struct RecordingRow: View {
  let recording: Recording

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      // Title or date
      HStack {
        Text(recording.displayTitle)
          .font(.headline)
          .foregroundStyle(Theme.textPrimary)
          .lineLimit(1)

        Spacer()

        // Duration badge
        Text(recording.formattedDuration)
          .font(.caption)
          .foregroundStyle(Theme.textSecondary)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(
            Capsule().fill(Theme.accent.opacity(0.15))
          )
      }

      // Transcript preview
      Text(recording.transcriptPreview)
        .font(.subheadline)
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(2)

      // Timestamp (if title exists)
      if recording.title != nil && !recording.title!.isEmpty {
        Text(recording.formattedDate)
          .font(.caption2)
          .foregroundStyle(Theme.textSecondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface(padding: 14)
  }
}

#Preview {
  RecordingRow(recording: Recording(
    timestamp: Date(),
    duration: 125,
    transcriptText: "This is a sample transcript text that demonstrates how the recording row will look in the list view.",
    title: "Sample Recording"
  ))
  .padding()
}
