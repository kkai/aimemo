//
//  RecordingView.swift
//  aimemo
//
//  Main recording interface (formerly ContentView)
//

import SwiftUI
import SwiftData
import AVFoundation
#if os(macOS)
import AppKit
#endif
import UniformTypeIdentifiers

struct RecordingView: View {
  @Environment(RealTimeWhisper.self) var audioProcessor
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.modelContext) private var modelContext

  @State private var showingSettings = false
  @State private var showingHistory = false
  @State private var showingFilePicker = false
  @State private var intents = RecorderIntentBridge.shared

  /// The summary of the transcript on screen. Cleared when a new take or
  /// import starts.
  @State private var summary: String?
  @State private var summaryGenerator = SummaryGenerator()

  /// The wordmark keeps its 40 pt look at the default size and scales from it.
  @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 40

  private var showActivity: Bool {
    audioProcessor.canStop
      || audioProcessor.isBusy
      || !audioProcessor.displayText.isEmpty
      || audioProcessor.elapsedTime > 0
  }

  private var status: RecordingStatus {
    switch audioProcessor.state {
    case .recording: return .recording
    case .paused: return .paused(audioProcessor.pauseReason)
    case .stopping: return .finishing
    case .importing: return .importing(audioProcessor.importProgress)
    case .idle: return .complete
    }
  }

  /// What the Share menu and the exporters get: the transcript on screen
  /// with its timings and summary.
  private var export: TranscriptExport {
    TranscriptExport(
      title: nil,
      date: audioProcessor.recordingStartTime ?? Date(),
      duration: audioProcessor.elapsedTime,
      text: audioProcessor.displayText,
      segments: audioProcessor.segments,
      summary: summary,
      sourceFileName: audioProcessor.importedFile?.displayName)
  }

  var body: some View {
    screen
    .sensoryFeedback(.impact(weight: .light), trigger: audioProcessor.state,
                     condition: Self.isPauseOrResume)
    .onChange(of: audioProcessor.state) { old, new in
      announce(from: old, to: new)
      if new == .recording || new == .importing { summary = nil }
    }
    // An intent asked for something; act once the scene can run audio.
    .onChange(of: intents.pending) { _, _ in runPendingIntent() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { runPendingIntent() }
    }
    .onAppear {
      runPendingIntent()
      #if DEBUG
      if let url = LaunchOptions.importFileAtLaunch, audioProcessor.state == .idle,
         audioProcessor.importedFile == nil {
        importFile(at: url)
      }
      #endif
    }
    .fileImporter(isPresented: $showingFilePicker,
                  allowedContentTypes: [.audio, .movie],
                  allowsMultipleSelection: false) { result in
      switch result {
      case .success(let urls):
        guard let url = urls.first else { return }
        importFile(at: url)
      case .failure(let error):
        audioProcessor.report(error.localizedDescription)
      }
    }
    .onChange(of: audioProcessor.errorMessage) { _, message in
      if let message { AccessibilityNotification.Announcement(message).post() }
    }
    .onChange(of: audioProcessor.noAudio) { _, silent in
      if silent { AccessibilityNotification.Announcement(Self.noAudioHint).post() }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .background {
        Task { await audioProcessor.enterBackground() }
      }
    }
    .sheet(isPresented: $showingSettings) {
      SettingsView()
        .environment(audioProcessor)
    }
    #if PRO_VERSION
    .sheet(isPresented: $showingHistory) {
      NavigationStack {
        RecordingsListView()
          .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
              Button("Done") { showingHistory = false }
            }
          }
      }
    }
    #endif
  }

  // MARK: - Sections

  private var screen: some View {
    ZStack {
      Theme.background.ignoresSafeArea()

      VStack(spacing: 0) {
        header

        ScrollView {
          VStack(spacing: 20) {
            title

            if showActivity {
              activity
            }

            #if !PRO_VERSION
            // Below the transcript and never during a take: above a live
            // transcript it pushed the card and its buttons below the fold.
            if audioProcessor.state == .idle {
              ProUpsellCard()
            }
            #endif
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 24)
        }

        if let message = audioProcessor.errorMessage {
          errorLine(message)
        }

        controls
          .padding(.vertical, 16)
      }
    }
  }

  @ViewBuilder
  private var activity: some View {
    StatusPill(status: status)
      .padding(.top, 4)

    if audioProcessor.noAudio && audioProcessor.state == .recording {
      noAudioLine
    }

    VStack(spacing: 6) {
      AudioWaveformView(levels: audioProcessor.audioLevels)
        .frame(height: 60)
      HStack(spacing: 8) {
        Text(audioProcessor.formattedElapsedTime)
          .font(.subheadline.monospacedDigit())
        if let code = audioProcessor.detectedLanguageCode {
          Text("·")
          // The app has detected ~99 languages since 2.4 without ever
          // saying so; this is the only place the user can see it work.
          Text(TranscriptionLanguage.localizedName(for: code))
            .font(.subheadline.weight(.medium))
            .transition(.opacity)
        }
      }
      .foregroundStyle(Theme.textSecondary)
      .animation(.easeInOut(duration: 0.2), value: audioProcessor.detectedLanguageCode)
      // "Elapsed 1 minute 5 seconds, detected language English", not "00:65 dot".
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(elapsedAndLanguageLabel)
      .accessibilityAddTraits(.updatesFrequently)
    }

    transcriptCard

    if audioProcessor.state == .idle, !audioProcessor.transcribedText.isEmpty {
      SummaryCard(transcript: audioProcessor.transcribedText, summary: $summary,
                  generator: summaryGenerator) { text in
        // Pro: the take was saved when it stopped; keep its summary with it.
        if let saved = audioProcessor.lastSaved {
          saved.summary = text
          try? modelContext.save()
        }
      }
    }
  }

  /// Copies the picked file inside the sandbox, then hands it to the recorder.
  private func importFile(at url: URL) {
    do {
      let file = try ImportedFile.stage(url)
      Task { await audioProcessor.transcribe(file: file) }
    } catch {
      audioProcessor.report(error.localizedDescription)
    }
  }

  /// Carries out what Siri or a shortcut asked for, once the scene is active.
  private func runPendingIntent() {
    guard scenePhase == .active, intents.pending != nil, let request = intents.take() else { return }
    switch request {
    case .startRecording:
      guard audioProcessor.state == .idle else { return }
      Task { await audioProcessor.start() }
    case .transcribe(let file):
      Task { await audioProcessor.transcribe(file: file) }
    }
  }


  private var header: some View {
    HStack(spacing: 12) {
      CircleIconButton(systemName: "gearshape", label: "Settings") { showingSettings = true }
      #if PRO_VERSION
      CircleIconButton(systemName: "clock.arrow.circlepath", label: "History") { showingHistory = true }
      #endif
      Spacer()
      CircleIconButton(systemName: "doc.badge.plus", label: "Transcribe a file") {
        showingFilePicker = true
      }
      .disabled(audioProcessor.state != .idle)
    }
    .padding(.horizontal, 20)
    .padding(.top, 8)
  }

  private var title: some View {
    VStack(spacing: 10) {
      Text("aiMemo")
        .font(.system(size: titleSize, weight: .regular, design: .serif))
        .foregroundStyle(Theme.textPrimary)
        .accessibilityLabel("ai-Memo")
        .accessibilityAddTraits(.isHeader)
      // Wraps by width, not a hard line break, so it reflows at large sizes.
      Text("Tap the button and start talking. The text appears while you speak.")
        .font(.subheadline)
        .foregroundStyle(Theme.textSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 300)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.top, 8)
  }

  private var transcriptCard: some View {
    VStack(spacing: 16) {
      ScrollView {
        (Text(verbatim: audioProcessor.transcribedText)
          .foregroundColor(Theme.textPrimary)
         + Text(audioProcessor.provisionalText.isEmpty ? "" : " ")
         + Text(verbatim: audioProcessor.provisionalText)
          // Still being decoded; dimmed until the window commits.
          .foregroundColor(Theme.textSecondary))
          .font(.title3)
          .lineSpacing(4)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
          .accessibilityLabel(audioProcessor.displayText.isEmpty ? "No transcript yet" : audioProcessor.displayText)
          // The dimming says it by sight; the value says it by ear.
          .accessibilityValue(audioProcessor.provisionalText.isEmpty ? "" : "The last words are still being transcribed")
          .accessibilityAddTraits(.updatesFrequently)
      }
      .frame(maxHeight: transcriptHeight)

      HStack(spacing: 12) {
        ActionButton(title: "Copy", systemName: "doc.on.doc", tint: Theme.accent) {
          #if os(iOS)
          UIPasteboard.general.setValue(audioProcessor.displayText,
                                        forPasteboardType: UTType.plainText.identifier)
          #elseif os(macOS)
          NSPasteboard.general.setString(audioProcessor.displayText, forType: .string)
          #endif
          // The copy had no feedback at all, seen or heard.
          AccessibilityNotification.Announcement("Transcript copied").post()
        }
        // Sharing previously required saving first, which the free app never
        // does - so a free user could only ever copy-paste out of the app.
        ShareTranscriptMenu(export: export)
        ActionButton(title: "Clear", systemName: "trash", tint: Theme.danger) {
          audioProcessor.clearTranscript()
          summary = nil
        }
      }
    }
    .cardSurface()
  }

  private var elapsedAndLanguageLabel: String {
    let seconds = Int(audioProcessor.elapsedTime)
    let elapsed = Duration.seconds(seconds)
      .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    guard let code = audioProcessor.detectedLanguageCode else { return "Elapsed \(elapsed)" }
    return "Elapsed \(elapsed), detected language \(TranscriptionLanguage.localizedName(for: code))"
  }

  /// Grows with the text size, so at the largest sizes the card still shows
  /// more than two lines.
  @ScaledMetric(relativeTo: .title3) private var transcriptHeight: CGFloat = 220

  static let noAudioHint = "No sound from the microphone. Check that it is not covered or in use."

  /// Shown while a take has had no audio for a few seconds. Static, so there
  /// is nothing for Reduce Motion to tame; announced once when it appears.
  private var noAudioLine: some View {
    Label(Self.noAudioHint, systemImage: "mic.slash")
      .font(.subheadline)
      .foregroundStyle(Theme.textPrimary)
      .labelStyle(TintedIconLabelStyle(tint: Theme.danger))
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityIdentifier("noAudioHint")
  }

  private func errorLine(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.triangle.fill")
      .font(.subheadline)
      .foregroundStyle(Theme.textPrimary)
      .labelStyle(TintedIconLabelStyle(tint: Theme.danger))
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 20)
      .padding(.top, 8)
  }

  /// Record in the middle; Pause/Resume beside it while a recording runs. An
  /// equal-width slot on the other side keeps the record button centred.
  private var controls: some View {
    HStack(spacing: 24) {
      Color.clear.frame(width: 64, height: 1)
        .accessibilityHidden(true)
      recordButton
      Group {
        if audioProcessor.state == .importing {
          Button {
            Task { await audioProcessor.cancelImport() }
          } label: {
            Image(systemName: "xmark")
              .font(.title3.weight(.semibold))
              .foregroundStyle(Theme.textPrimary)
              .frame(width: 56, height: 56)
              .background(Circle().fill(Theme.surface))
              .overlay(Circle().stroke(Theme.surfaceBorder, lineWidth: 1))
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Cancel transcription")
          .transition(.opacity)
        } else if audioProcessor.canStop {
          PauseResumeButton(isPaused: audioProcessor.state == .paused) {
            Task {
              if audioProcessor.state == .paused {
                await audioProcessor.resume()
              } else {
                await audioProcessor.pause()
              }
            }
          }
          .transition(.opacity)
        } else {
          // Height 1, like the left slot: an unconstrained Color.clear is
          // greedy and the VStack then split the screen between it and the
          // transcript, which clipped the card to two lines after every take.
          Color.clear.frame(height: 1).accessibilityHidden(true)
        }
      }
      .frame(width: 64)
    }
    .animation(.easeInOut(duration: 0.2), value: audioProcessor.canStop)
    .animation(.easeInOut(duration: 0.2), value: audioProcessor.state == .importing)
  }

  private static func isPauseOrResume(_ old: RealTimeWhisper.State,
                                      _ new: RealTimeWhisper.State) -> Bool {
    new == .paused || (old == .paused && new == .recording)
  }

  /// State changes spoken for VoiceOver. The live transcript is not announced:
  /// it changes every few seconds and would drown everything else.
  private func announce(from old: RealTimeWhisper.State, to new: RealTimeWhisper.State) {
    let message: String?
    switch (old, new) {
    case (.idle, .recording): message = "Recording"
    case (.recording, .paused):
      message = RecordingStatus.paused(audioProcessor.pauseReason).label
    case (.paused, .recording): message = "Recording resumed"
    case (.stopping, .idle): message = "Stopped. The transcript is ready."
    case (.idle, .importing): message = "Transcribing the file"
    case (.importing, .idle): message = "File transcribed. The transcript is ready."
    default: message = nil
    }
    if let message { AccessibilityNotification.Announcement(message).post() }
  }

  private var activeScene: UIWindowScene? {
    UIApplication.shared.connectedScenes
      .first { $0.activationState == .foregroundActive } as? UIWindowScene
  }

  private var recordButton: some View {
    importAwareRecordButton
      .disabled(audioProcessor.state == .importing)
      .opacity(audioProcessor.state == .importing ? 0.4 : 1)
  }

  private var importAwareRecordButton: some View {
    AnimatedRecordButton(
      isRecording: Binding(
        get: { audioProcessor.canStop },
        set: { _ in }
      ),
      onStart: {
        Task { await audioProcessor.start() }
      },
      onStop: {
        Task {
          // Awaits the final flush, so the transcript read below is complete.
          await audioProcessor.stopRecord()
          // Count only takes that actually produced text - a recording that
          // transcribed nothing is not evidence the app was useful.
          let transcript = audioProcessor.transcribedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
          if !transcript.isEmpty, ReviewPrompt.recordTranscription() {
            ReviewPrompt.requestIfAppropriate(in: activeScene)
          }
        }
      }
    )
  }
}

#Preview("Empty") {
  RecordingView()
    .environment(RealTimeWhisper())
    .modelContainer(for: Recording.self, inMemory: true)
}

#Preview("Populated") {
  let whisper = RealTimeWhisper()
  whisper.transcribedText = "Das ist ein Test. Das ist ein Test. Ich bin ein Deutscher."
  whisper.audioLevels = (0..<100).map { Float(0.15 + 0.7 * abs(sin(Double($0) / 5.5))) }
  whisper.elapsedTime = 27
  return RecordingView()
    .environment(whisper)
    .modelContainer(for: Recording.self, inMemory: true)
}
