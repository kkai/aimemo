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
  @State private var selectedLanguage: TranscriptionLanguage = .selected
  @State private var translateToEnglish = TranscriptionOptions.translateToEnglishSetting
  @State private var customVocabulary = TranscriptionOptions.customVocabularySetting
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
            ForEach(WhisperModel.bundled) { model in
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
                    .foregroundColor(Theme.accent)
                }
              }
            }
            .buttonStyle(.plain)
          }

        } header: {
          Text("Transcription Engine")
        } footer: {
          if selectedEngine == .appleSpeech {
            Text("Apple Speech starts quickly. iOS runs it on the device where it supports your language.")
              .font(.caption)
          } else {
            Text("Whisper runs on your device and works offline. It detects the language by itself.")
              .font(.caption)
          }
        }

        // Language
        Section {
          Picker("Language", selection: $selectedLanguage) {
            Text(TranscriptionLanguage.automatic.displayName)
              .tag(TranscriptionLanguage.automatic)
            if let device = TranscriptionLanguage.deviceLanguage {
              Text(device.displayName).tag(device)
            }
            Divider()
            ForEach(TranscriptionLanguage.allSpecific) { language in
              Text(language.displayName).tag(language)
            }
          }
          .onChange(of: selectedLanguage) { _, newValue in
            TranscriptionLanguage.selected = newValue
          }
        } header: {
          Text("Language")
        } footer: {
          Text(selectedEngine == .whisper
               ? "Whisper detects the language automatically. Pick one to pin it — auto-detect can misfire on very short clips."
               : "Apple Speech cannot detect the language automatically; Automatic uses your device language.")
            .font(.caption)
        }

        // Translate (Whisper only — Apple Speech has no translation mode)
        if selectedEngine == .whisper {
          Section {
            Toggle("Translate to English", isOn: $translateToEnglish)
              .onChange(of: translateToEnglish) { _, newValue in
                TranscriptionOptions.translateToEnglishSetting = newValue
              }
          } footer: {
            Text("Speak any supported language and get English text. Whisper translates into English only.")
              .font(.caption)
          }

          Section {
            TextField("Names, jargon, acronyms", text: $customVocabulary, axis: .vertical)
              .lineLimit(2...4)
              .autocorrectionDisabled()
              .onChange(of: customVocabulary) { _, newValue in
                TranscriptionOptions.customVocabularySetting = newValue
              }
          } header: {
            Text("Custom Vocabulary")
          } footer: {
            Text("Words Whisper should expect, separated by commas. Helps it spell names and technical terms it would otherwise guess at.")
              .font(.caption)
          }
        }

        #if !PRO_VERSION
        Section {
          Link(destination: URL(string: "https://apps.apple.com/app/ai-memo-pro/id6503480155")!) {
            HStack {
              Label("Buy ai-Memo Pro", systemImage: "star.fill")
                .foregroundColor(Theme.accent)
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
      .scrollContentBackground(.hidden)
      .background(Theme.background)
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
