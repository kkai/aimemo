//
//  RecordingsListView.swift
//  aimemo
//
//  Main view for displaying recordings history with search and filtering
//

import SwiftUI
import SwiftData

struct RecordingsListView: View {
  @Query(sort: \Recording.timestamp, order: .reverse)
  var recordings: [Recording]

  @Environment(\.modelContext) private var modelContext
  @State private var viewModel = RecordingsViewModel()
  @State private var showingShareSheet = false
  @State private var shareItems: [Any] = []

  var filteredRecordings: [Recording] {
    viewModel.filteredRecordings(recordings)
  }

  var body: some View {
    Group {
      if recordings.isEmpty {
        ContentUnavailableView(
          "No Recordings",
          systemImage: "waveform",
          description: Text("Your transcripts will appear here after recording")
        )
      } else {
        List {
          ForEach(filteredRecordings) { recording in
            NavigationLink(value: recording) {
              RecordingRow(recording: recording)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
              Button {
                share(recording)
              } label: {
                Label("Share", systemImage: "square.and.arrow.up")
              }
              .tint(Theme.accent)
            }
            .contextMenu {
              Button {
                share(recording)
              } label: {
                Label("Share", systemImage: "square.and.arrow.up")
              }
              Button {
                UIPasteboard.general.string = recording.transcriptText
              } label: {
                Label("Copy Transcript", systemImage: "doc.on.doc")
              }
              Button {
                viewModel.editRecording(recording)
              } label: {
                Label("Edit Title", systemImage: "pencil")
              }
            }
          }
          .onDelete(perform: deleteRecordings)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .searchable(text: $viewModel.searchText, prompt: "Search recordings")
      }
    }
    .background(Theme.background)
    .navigationTitle("History")
    .navigationDestination(for: Recording.self) { recording in
      RecordingDetailView(recording: recording)
    }
    .toolbar {
      if !recordings.isEmpty {
        EditButton()
      }
    }
    .sheet(isPresented: $viewModel.isShowingEditSheet) {
      if let recording = viewModel.recordingToEdit {
        EditRecordingSheet(recording: recording)
      }
    }
    .sheet(isPresented: $showingShareSheet) {
      ShareSheet(items: shareItems)
    }
  }

  /// The share sheet and its items were declared here but never populated, so
  /// sharing only ever worked from the detail view. Reuses the same
  /// `RecordingsViewModel.shareRecording` payload.
  private func share(_ recording: Recording) {
    shareItems = viewModel.shareRecording(recording)
    showingShareSheet = true
  }

  private func deleteRecordings(at offsets: IndexSet) {
    for index in offsets {
      let recording = filteredRecordings[index]
      modelContext.delete(recording)
    }
  }
}

// MARK: - Edit Recording Sheet

struct EditRecordingSheet: View {
  @Environment(\.dismiss) private var dismiss
  let recording: Recording

  @State private var title: String = ""

  var body: some View {
    NavigationStack {
      Form {
        Section("Title") {
          TextField("Enter a title (optional)", text: $title)
        }

        Section("Details") {
          LabeledContent("Date", value: recording.formattedDate)
          LabeledContent("Duration", value: recording.formattedDuration)
        }

        Section("Transcript") {
          Text(recording.transcriptText)
            .font(.body)
        }
      }
      .navigationTitle("Edit Recording")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            recording.title = title.isEmpty ? nil : title
            dismiss()
          }
        }
      }
      .onAppear {
        title = recording.title ?? ""
      }
    }
  }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
  let items: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    // No update needed
  }
}

#Preview {
  NavigationStack {
    RecordingsListView()
      .modelContainer(for: Recording.self, inMemory: true)
  }
}
