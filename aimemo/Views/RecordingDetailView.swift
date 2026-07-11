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
      VStack(alignment: .leading, spacing: 20) {
        // Header section
        VStack(alignment: .leading, spacing: 8) {
          Text(recording.displayTitle)
            .font(.title2)
            .bold()

          HStack {
            Label(recording.formattedDate, systemImage: "calendar")
            Spacer()
            Label(recording.formattedDuration, systemImage: "clock")
          }
          .font(.subheadline)
          .foregroundColor(.secondary)
        }

        Divider()

        // Transcript section
        VStack(alignment: .leading, spacing: 8) {
          Text("Transcript")
            .font(.headline)
            .foregroundColor(.secondary)

          Text(recording.transcriptText)
            .font(.body)
            .textSelection(.enabled)
        }

        // AI summary section (on-device Foundation Models, iOS 26+).
        // Renders nothing on devices without Apple Intelligence.
        if recording.summary != nil || summaryGenerator.isAvailable {
          Divider()

          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("AI Summary")
                .font(.headline)
                .foregroundColor(.secondary)

              Spacer()

              if recording.summary != nil && summaryGenerator.isAvailable {
                Button {
                  generateSummary()
                } label: {
                  Label("Regenerate", systemImage: "arrow.clockwise")
                    .font(.caption)
                }
                .disabled(summaryGenerator.isGenerating)
              }
            }

            if summaryGenerator.isGenerating {
              HStack(spacing: 8) {
                ProgressView()
                Text("Summarizing…")
                  .font(.subheadline)
                  .foregroundColor(.secondary)
              }
              .padding(.vertical, 4)
            } else if let summary = recording.summary {
              Text(summary)
                .font(.body)
                .textSelection(.enabled)
            } else {
              Button {
                generateSummary()
              } label: {
                Label("Generate Summary", systemImage: "sparkles")
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(.bordered)
              .tint(.blue)
            }
          }
        }

        Spacer(minLength: 20)

        // Action buttons
        VStack(spacing: 12) {
          Button {
            copyToClipboard()
          } label: {
            Label("Copy to Clipboard", systemImage: "doc.on.doc")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .tint(.blue)

          Button {
            shareRecording()
          } label: {
            Label("Share", systemImage: "square.and.arrow.up")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .tint(.blue)

          Button {
            viewModel.editRecording(recording)
          } label: {
            Label("Edit Title", systemImage: "pencil")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .tint(.gray)
        }
      }
      .padding()
    }
    .navigationBarTitleDisplayMode(.inline)
    .overlay(alignment: .top) {
      if copiedToClipboard {
        Text("Copied to clipboard")
          .font(.caption)
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
          .background(Color.secondary.opacity(0.8))
          .foregroundColor(.white)
          .cornerRadius(20)
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
