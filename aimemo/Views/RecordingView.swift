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
      || !audioProcessor.transcribedText.isEmpty
      || audioProcessor.elapsedTime > 0
  }

  private var status: RecordingStatus {
    audioProcessor.canStop ? .recording : .complete
  }

  var body: some View {
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
              StatusPill(status: status)
                .padding(.top, 4)

              VStack(spacing: 6) {
                AudioWaveformView(levels: audioProcessor.audioLevels)
                  .frame(height: 60)
                Text(audioProcessor.formattedElapsedTime)
                  .font(.system(size: 15, weight: .regular).monospacedDigit())
                  .foregroundStyle(Theme.textSecondary)
              }

              transcriptCard
            }
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 24)
        }

        recordButton
          .padding(.vertical, 16)
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
      Text("Record speech and convert it to text.\nLonger recordings might take a while to convert.")
        .font(.system(size: 15))
        .foregroundStyle(Theme.textSecondary)
        .multilineTextAlignment(.center)
    }
    .padding(.top, 8)
  }

  private var transcriptCard: some View {
    VStack(spacing: 16) {
      ScrollView {
        Text(verbatim: audioProcessor.transcribedText)
          .font(.system(size: 19))
          .foregroundStyle(Theme.textPrimary)
          .lineSpacing(4)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
      }
      .frame(maxHeight: 220)

      HStack(spacing: 12) {
        ActionButton(title: "Copy to clipboard", systemName: "doc.on.doc", tint: Theme.accent) {
          #if os(iOS)
          UIPasteboard.general.setValue(audioProcessor.transcribedText,
                                        forPasteboardType: UTType.plainText.identifier)
          #elseif os(macOS)
          NSPasteboard.general.setString(audioProcessor.transcribedText, forType: .string)
          #endif
        }
        ActionButton(title: "Delete text", systemName: "trash", tint: Theme.danger) {
          audioProcessor.transcribedText = ""
        }
      }
    }
    .cardSurface()
  }

  private var recordButton: some View {
    AnimatedRecordButton(
      isRecording: Binding(
        get: { audioProcessor.canStop },
        set: { _ in }
      ),
      onStart: {
        Task {
          audioProcessor.canStop = true
          do {
            try audioProcessor.startRealTimeProcessingAndPlayback()
          } catch {
            print("Error starting real-time processing and playback: \(error.localizedDescription)")
          }
        }
      },
      onStop: {
        Task {
          audioProcessor.stopRecord()
          audioProcessor.canStop = false
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
