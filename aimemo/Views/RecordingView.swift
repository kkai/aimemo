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

  @State private var showingSettings = false
  @State private var showingHistory = false

  private var showActivity: Bool {
    audioProcessor.canStop
      || audioProcessor.isBusy
      || !audioProcessor.displayText.isEmpty
      || audioProcessor.elapsedTime > 0
  }

  private var status: RecordingStatus {
    switch audioProcessor.state {
    case .recording: return .recording
    case .paused: return .paused(byInterruption: audioProcessor.pauseReason == .interruption)
    case .stopping: return .finishing
    case .idle: return .complete
    }
  }

  var body: some View {
    screen
    .sensoryFeedback(.impact(weight: .light), trigger: audioProcessor.state,
                     condition: Self.isPauseOrResume)
    .onChange(of: audioProcessor.state) { old, new in
      announce(from: old, to: new)
    }
    .onChange(of: audioProcessor.errorMessage) { _, message in
      if let message { AccessibilityNotification.Announcement(message).post() }
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

            #if !PRO_VERSION
            ProUpsellCard()
            #endif

            if showActivity {
              activity
            }
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

    VStack(spacing: 6) {
      AudioWaveformView(levels: audioProcessor.audioLevels)
        .frame(height: 60)
      HStack(spacing: 8) {
        Text(audioProcessor.formattedElapsedTime)
          .font(.system(size: 15, weight: .regular).monospacedDigit())
        if let code = audioProcessor.detectedLanguageCode {
          Text("·")
          // The app has detected ~99 languages since 2.4 without ever
          // saying so; this is the only place the user can see it work.
          Text(TranscriptionLanguage.localizedName(for: code))
            .font(.system(size: 15, weight: .medium))
            .transition(.opacity)
        }
      }
      .foregroundStyle(Theme.textSecondary)
      .animation(.easeInOut(duration: 0.2), value: audioProcessor.detectedLanguageCode)
    }

    transcriptCard
  }


  private var header: some View {
    HStack(spacing: 12) {
      CircleIconButton(systemName: "gearshape") { showingSettings = true }
      #if PRO_VERSION
      CircleIconButton(systemName: "clock.arrow.circlepath") { showingHistory = true }
      #endif
      Spacer()
    }
    .padding(.horizontal, 20)
    .padding(.top, 8)
  }

  private var title: some View {
    VStack(spacing: 10) {
      Text("aiMemo")
        .font(.system(size: 40, weight: .regular, design: .serif))
        .foregroundStyle(Theme.textPrimary)
      Text("Tap the button and start talking.\nThe text appears while you speak.")
        .font(.system(size: 15))
        .foregroundStyle(Theme.textSecondary)
        .multilineTextAlignment(.center)
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
          .font(.system(size: 19))
          .lineSpacing(4)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
      }
      .frame(maxHeight: 220)

      HStack(spacing: 12) {
        ActionButton(title: "Copy", systemName: "doc.on.doc", tint: Theme.accent) {
          #if os(iOS)
          UIPasteboard.general.setValue(audioProcessor.displayText,
                                        forPasteboardType: UTType.plainText.identifier)
          #elseif os(macOS)
          NSPasteboard.general.setString(audioProcessor.displayText, forType: .string)
          #endif
        }
        // Sharing previously required saving first, which the free app never
        // does - so a free user could only ever copy-paste out of the app.
        ShareLink(item: audioProcessor.displayText) {
          HStack(spacing: 8) {
            Image(systemName: "square.and.arrow.up")
            Text("Share")
          }
          .actionButtonStyle(tint: Theme.accent)
        }
        .buttonStyle(.plain)
        ActionButton(title: "Clear", systemName: "trash", tint: Theme.danger) {
          audioProcessor.transcribedText = ""
        }
      }
    }
    .cardSurface()
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
        if audioProcessor.canStop {
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
          Color.clear.accessibilityHidden(true)
        }
      }
      .frame(width: 64)
    }
    .animation(.easeInOut(duration: 0.2), value: audioProcessor.canStop)
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
      message = audioProcessor.pauseReason == .interruption ? "Paused by a call or alarm" : "Paused"
    case (.paused, .recording): message = "Recording resumed"
    case (.stopping, .idle): message = "Stopped. The transcript is ready."
    default: message = nil
    }
    if let message { AccessibilityNotification.Announcement(message).post() }
  }

  private var activeScene: UIWindowScene? {
    UIApplication.shared.connectedScenes
      .first { $0.activationState == .foregroundActive } as? UIWindowScene
  }

  private var recordButton: some View {
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
