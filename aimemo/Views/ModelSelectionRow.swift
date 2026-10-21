//
//  ModelSelectionRow.swift
//  aimemo
//
//  Row component for displaying Whisper model information in settings
//

import SwiftUI

struct ModelSelectionRow: View {
  let model: WhisperModel
  let isSelected: Bool

  var body: some View {
    HStack(spacing: 12) {
      // Selection indicator
      Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
        .font(.title3)
        // The row's button carries .isSelected; the symbol name is noise.
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        // Model name and quality badge
        HStack {
          Text(model.displayName)
            .font(.headline)
            .foregroundStyle(Theme.textPrimary)

          // Light text on a stronger tint: blue and purple text on a 20%
          // tint of themselves measured 3.6:1, under the 4.5:1 floor.
          Text(model.quality)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(qualityColor.opacity(0.3))
            .foregroundStyle(Theme.textPrimary)
            .cornerRadius(4)
        }

        // Description
        // System secondary, like the rest of Settings: Theme.textSecondary is
        // tuned for the app's own background, not a Form row.
        Text(model.description)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)

        // Size and memory requirements
        HStack(spacing: 12) {
          Label(model.fileSize, systemImage: "externaldrive")
            .font(.caption)
            .foregroundStyle(.secondary)

          Label(model.memoryRequirement, systemImage: "memorychip")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Spacer()
    }
    .padding(.vertical, 8)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  private var qualityColor: Color {
    switch model {
    case .tiny: return .orange
    case .base: return .green
    case .small: return .blue
    case .medium: return .purple
    }
  }
}

#Preview {
  List {
    ModelSelectionRow(model: .tiny, isSelected: true)
    ModelSelectionRow(model: .base, isSelected: false)
    ModelSelectionRow(model: .small, isSelected: false)
    ModelSelectionRow(model: .medium, isSelected: false)
  }
}
