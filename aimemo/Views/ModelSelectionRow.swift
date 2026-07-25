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

      VStack(alignment: .leading, spacing: 4) {
        // Model name and quality badge
        HStack {
          Text(model.displayName)
            .font(.headline)
            .foregroundStyle(Theme.textPrimary)

          Text(model.quality)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(qualityColor.opacity(0.2))
            .foregroundStyle(qualityColor)
            .cornerRadius(4)
        }

        // Description
        Text(model.description)
          .font(.subheadline)
          .foregroundStyle(Theme.textSecondary)
          .lineLimit(2)

        // Size and memory requirements
        HStack(spacing: 12) {
          Label(model.fileSize, systemImage: "externaldrive")
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)

          Label(model.memoryRequirement, systemImage: "memorychip")
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
        }
      }

      Spacer()
    }
    .padding(.vertical, 8)
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
