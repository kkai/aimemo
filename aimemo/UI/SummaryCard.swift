//
//  SummaryCard.swift
//  aimemo
//
//  On-device summary of the transcript on screen (Foundation Models, iOS 26+)
//

import SwiftUI

/// The summary card under a finished transcript. Renders nothing on devices
/// without Apple Intelligence, so the free app and older phones simply never
/// see it. The text never leaves the device: the model runs in the app.
struct SummaryCard: View {
  let transcript: String
  @Binding var summary: String?
  @Bindable var generator: SummaryGenerator
  /// Called with the finished summary, so Pro can store it with the recording.
  var onSummary: ((String) -> Void)? = nil

  @State private var showingError = false

  var body: some View {
    if generator.isAvailable || summary != nil {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Label("Summary", systemImage: "sparkles")
            .font(.headline)
            .foregroundStyle(Theme.textSecondary)
            .accessibilityAddTraits(.isHeader)
          Spacer()
          if summary != nil, generator.isAvailable {
            Button {
              generate()
            } label: {
              Label("Regenerate", systemImage: "arrow.clockwise")
                .font(.caption)
            }
            .tint(Theme.accent)
            .disabled(generator.isGenerating)
          }
        }

        if generator.isGenerating {
          HStack(spacing: 8) {
            ProgressView()
            Text("Summarizing on this device…")
              .font(.subheadline)
              .foregroundStyle(Theme.textSecondary)
          }
          .accessibilityElement(children: .combine)
        } else if let summary {
          Text(summary)
            .font(.body)
            .foregroundStyle(Theme.textPrimary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
          ActionButton(title: "Copy Summary", systemName: "doc.on.doc", tint: Theme.accent) {
            UIPasteboard.general.string = summary
            AccessibilityNotification.Announcement("Summary copied").post()
          }
        } else {
          ActionButton(title: "Summarize", systemName: "sparkles", tint: Theme.accent) {
            generate()
          }
          .disabled(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .cardSurface()
      .alert("Summary Failed", isPresented: $showingError) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(generator.error ?? "Could not generate a summary.")
      }
    }
  }

  private func generate() {
    Task {
      await generator.generateSummary(for: transcript)
      if let text = generator.summaryText {
        summary = text
        onSummary?(text)
      } else if generator.error != nil {
        showingError = true
      }
    }
  }
}
