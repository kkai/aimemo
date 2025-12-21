//
//  SettingsView.swift
//  aimemo
//
//  Settings view for Whisper model selection
//

import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(RealTimeWhisper.self) var audioProcessor

  @State private var selectedModel: WhisperModel = .selected
  @State private var selectedEngine: TranscriptionEngine = .selected
  @State private var isLoadingModel = false
  @State private var showingAlert = false
  @State private var alertMessage = ""
  @State private var showingEngineComparison = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          // Current model info
          VStack(alignment: .leading, spacing: 8) {
            Text("Current Model")
              .font(.caption)
              .foregroundColor(.secondary)

            HStack {
              Text(selectedModel.displayName)
                .font(.headline)

              Spacer()

              Text(selectedModel.fileSize)
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
          }
          .padding(.vertical, 4)
        } header: {
          Text("Active Configuration")
        }

        // Whisper model selection (only show when Whisper is selected)
        #if PRO_VERSION
        if selectedEngine == .whisper {
          Section {
            ForEach(WhisperModel.allCases) { model in
              Button {
                selectModel(model)
              } label: {
                ModelSelectionRow(model: model, isSelected: selectedModel == model)
              }
              .buttonStyle(.plain)
            }
          } header: {
            Text("Available Whisper Models")
          } footer: {
            Text("Larger models provide better accuracy but require more storage and processing time. The app must reload when switching models.")
              .font(.caption)
          }
        }
        #endif

        // Transcription Engine Selection
        Section {
          ForEach(TranscriptionEngine.allCases) { engine in
            Button {
              selectEngine(engine)
            } label: {
              HStack {
                VStack(alignment: .leading, spacing: 4) {
                  Text(engine.displayName)
                    .font(.headline)

                  Text(engine.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()

                if selectedEngine == engine {
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                }
              }
            }
            .buttonStyle(.plain)
          }

          // Comparison button
          Button {
            showingEngineComparison = true
          } label: {
            Label("Compare Engines", systemImage: "info.circle")
          }
        } header: {
          Text("Transcription Engine")
        } footer: {
          if selectedEngine == .appleSpeech {
            Text("Apple Speech provides faster transcription using system-integrated speech recognition.")
              .font(.caption)
          } else {
            Text("Whisper models provide higher accuracy using offline AI models.")
              .font(.caption)
          }
        }

        // Loading indicator
        if isLoadingModel {
          Section {
            HStack {
              Spacer()
              ProgressView()
                .progressViewStyle(.circular)
              Text("Loading model...")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.leading, 8)
              Spacer()
            }
            .padding(.vertical, 8)
          }
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Done") {
            dismiss()
          }
        }
      }
      .alert("Model Loading", isPresented: $showingAlert) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(alertMessage)
      }
      .sheet(isPresented: $showingEngineComparison) {
        EngineComparisonView()
      }
    }
  }

  private func selectEngine(_ engine: TranscriptionEngine) {
    guard engine != selectedEngine else { return }

    selectedEngine = engine
    TranscriptionEngine.selected = engine
    audioProcessor.currentEngine = engine
  }

  private func selectModel(_ model: WhisperModel) {
    guard model != selectedModel else { return }
    guard !isLoadingModel else { return }

    Task {
      isLoadingModel = true

      do {
        // Load the new model
        try await audioProcessor.loadModel(model)

        // Update selection
        await MainActor.run {
          selectedModel = model
          WhisperModel.selected = model
          isLoadingModel = false
        }
      } catch {
        await MainActor.run {
          isLoadingModel = false
          alertMessage = "Failed to load \(model.displayName) model: \(error.localizedDescription)"
          showingAlert = true
        }
      }
    }
  }
}

// MARK: - Engine Comparison View

struct EngineComparisonView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section("Performance") {
          ComparisonRow(
            metric: "Speed",
            whisperValue: "Good",
            appleValue: "Excellent (2.2x faster)"
          )
          ComparisonRow(
            metric: "Accuracy",
            whisperValue: "Excellent (1% WER)",
            appleValue: "Good (8% WER)"
          )
          ComparisonRow(
            metric: "Battery Usage",
            whisperValue: "Higher",
            appleValue: "Lower (optimized)"
          )
        }

        Section("Storage & Requirements") {
          ComparisonRow(
            metric: "Storage",
            whisperValue: "75 MB - 1.5 GB",
            appleValue: "0 MB (system)"
          )
          ComparisonRow(
            metric: "Languages",
            whisperValue: "English only",
            appleValue: "10-60+ languages"
          )
          ComparisonRow(
            metric: "Permission",
            whisperValue: "Microphone only",
            appleValue: "Microphone + Speech"
          )
        }

        Section("Best For") {
          VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
              Text("Whisper Models")
                .font(.headline)
              Text("Important recordings, interviews, technical content where accuracy is critical")
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
              Text("Apple Speech")
                .font(.headline)
              Text("Quick notes, meetings, real-time transcription where speed matters")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
      }
      .navigationTitle("Compare Engines")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Done") {
            dismiss()
          }
        }
      }
    }
  }
}

struct ComparisonRow: View {
  let metric: String
  let whisperValue: String
  let appleValue: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(metric)
        .font(.subheadline)
        .foregroundColor(.secondary)

      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Whisper")
            .font(.caption)
            .foregroundColor(.secondary)
          Text(whisperValue)
            .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        VStack(alignment: .leading, spacing: 4) {
          Text("Apple")
            .font(.caption)
            .foregroundColor(.secondary)
          Text(appleValue)
            .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(.vertical, 4)
  }
}

#Preview {
  SettingsView()
    .environment(RealTimeWhisper())
}
