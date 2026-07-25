//
//  RecordingDetailView.swift
//  aimemo
//
//  Detail view for displaying full transcript and recording metadata
//

import SwiftUI

struct RecordingDetailView: View {
  let recording: Recording

  @Environment(\.modelContext) private var modelContext
  @State private var viewModel = RecordingsViewModel()
  @State private var showingShareSheet = false
  @State private var copiedToClipboard = false
  @State private var summaryGenerator = SummaryGenerator()
  @State private var showingSummaryError = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        // Header card
        VStack(alignment: .leading, spacing: 10) {
          Text(recording.displayTitle)
            .font(.title2)
            .bold()
            .foregroundStyle(Theme.textPrimary)

          HStack {
            Label(recording.formattedDate, systemImage: "calendar")
            Spacer()
            Label(recording.formattedDuration, systemImage: "clock")
          }
          .font(.subheadline)
          .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()

        // Transcript card
        VStack(alignment: .leading, spacing: 8) {
          Text("Transcript")
            .font(.headline)
            .foregroundStyle(Theme.textSecondary)

          Text(recording.transcriptText)
            .font(.body)
            .foregroundStyle(Theme.textPrimary)
            .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()

        // AI summary card (on-device Foundation Models, iOS 26+).
        // Renders nothing on devices without Apple Intelligence.
        if recording.summary != nil || summaryGenerator.isAvailable {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("AI Summary")
                .font(.headline)
                .foregroundStyle(Theme.textSecondary)

              Spacer()

              if recording.summary != nil && summaryGenerator.isAvailable {
                Button {
                  generateSummary()
                } label: {
                  Label("Regenerate", systemImage: "arrow.clockwise")
                    .font(.caption)
                }
                .tint(Theme.accent)
                .disabled(summaryGenerator.isGenerating)
              }
            }

            if summaryGenerator.isGenerating {
              HStack(spacing: 8) {
                ProgressView()
                Text("Summarizing…")
                  .font(.subheadline)
                  .foregroundStyle(Theme.textSecondary)
              }
              .padding(.vertical, 4)
            } else if let summary = recording.summary {
              Text(summary)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
            } else {
              ActionButton(title: "Generate Summary", systemName: "sparkles", tint: Theme.accent) {
                generateSummary()
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .cardSurface()
        }

        // Action buttons
        VStack(spacing: 12) {
          ActionButton(title: "Copy to Clipboard", systemName: "doc.on.doc", tint: Theme.accent) {
            copyToClipboard()
          }
          ActionButton(title: "Share", systemName: "square.and.arrow.up", tint: Theme.accent) {
            shareRecording()
          }
          ActionButton(title: "Edit Title", systemName: "pencil", tint: Theme.textSecondary) {
            viewModel.editRecording(recording)
          }
        }
        .padding(.top, 4)
      }
      .padding()
    }
    .background(Theme.background)
    .navigationBarTitleDisplayMode(.inline)
    .overlay(alignment: .top) {
      if copiedToClipboard {
        Text("Copied to clipboard")
          .font(.caption)
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
          .background(Capsule().fill(Theme.surface))
          .overlay(Capsule().stroke(Theme.surfaceBorder, lineWidth: 1))
          .foregroundStyle(Theme.textPrimary)
          .padding(.top, 8)
          .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .sheet(isPresented: $viewModel.isShowingEditSheet) {
      EditRecordingSheet(recording: recording)
    }
    .sheet(isPresented: $showingShareSheet) {
      ShareSheet(items: viewModel.shareRecording(recording))
    }
    .alert("Summary Failed", isPresented: $showingSummaryError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(summaryGenerator.error ?? "Could not generate a summary.")
    }
  }

  private func generateSummary() {
    Task {
      await summaryGenerator.generateSummary(for: recording.transcriptText)
      if let summary = summaryGenerator.summaryText {
        recording.summary = summary
        try? modelContext.save()
      } else if summaryGenerator.error != nil {
        showingSummaryError = true
      }
    }
  }

  private func copyToClipboard() {
    UIPasteboard.general.string = recording.transcriptText

    withAnimation {
      copiedToClipboard = true
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      withAnimation {
        copiedToClipboard = false
      }
    }
  }

  private func shareRecording() {
    showingShareSheet = true
  }
}

#Preview {
  NavigationStack {
    RecordingDetailView(recording: Recording(
      timestamp: Date(),
      duration: 125,
      transcriptText: "This is a sample transcript that demonstrates how the full transcript view will look when displaying a recording. It includes multiple sentences and shows how the text selection and sharing features work.",
      title: "Sample Recording"
    ))
  }
  .modelContainer(for: Recording.self, inMemory: true)
}
