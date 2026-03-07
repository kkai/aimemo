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

        #if !PRO_VERSION
        Section {
          Link(destination: URL(string: "https://apps.apple.com/app/ai-memo-pro/id6503480155")!) {
            HStack {
              Label("Buy ai-Memo Pro", systemImage: "star.fill")
                .foregroundColor(.blue)
              Spacer()
              Image(systemName: "arrow.up.right.square")
                .foregroundColor(.secondary)
            }
          }
        } header: {
          Text("Upgrade")
        } footer: {
          Text("Get recording history and model selection with ai-Memo Pro.")
            .font(.caption)
        }
        #endif

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

#Preview {
  SettingsView()
    .environment(RealTimeWhisper())
}
