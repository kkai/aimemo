//
//  LaunchOptions.swift
//  aimemo
//
//  Launch arguments for UI tests and screenshots (DEBUG builds only)
//

import Foundation
import SwiftData

enum LaunchOptions {
  /// `-uiTestScriptedSession`: recordings play a fixed script instead of
  /// using the microphone.
  static var usesScriptedSession: Bool {
    #if DEBUG
    ProcessInfo.processInfo.arguments.contains("-uiTestScriptedSession")
    #else
    false
    #endif
  }

  /// `-uiTestSeedHistory`: an in-memory history with three recordings, so
  /// History and Detail can be audited from a known state (Pro).
  static var seedsHistory: Bool {
    #if DEBUG
    ProcessInfo.processInfo.arguments.contains("-uiTestSeedHistory")
    #else
    false
    #endif
  }

  /// `-uiTestImportFile <path>`: transcribe this audio file as soon as the
  /// recording screen appears, so the importing screen can be audited and
  /// screenshotted without a file picker. The path is on the host; the
  /// simulator shares its file system.
  static var importFileAtLaunch: URL? {
    #if DEBUG
    let arguments = ProcessInfo.processInfo.arguments
    guard let index = arguments.firstIndex(of: "-uiTestImportFile"),
          index + 1 < arguments.count else { return nil }
    return URL(fileURLWithPath: arguments[index + 1])
    #else
    return nil
    #endif
  }

  /// The app's store. Under any UI-test argument it is in memory, so a test
  /// never reads or writes the history on the simulator.
  @MainActor
  static func makeModelContainer() -> ModelContainer {
    let inMemory = usesScriptedSession || seedsHistory || importFileAtLaunch != nil
    let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
    do {
      let container = try ModelContainer(for: Recording.self, configurations: configuration)
      #if DEBUG
      if seedsHistory { seed(container.mainContext) }
      #endif
      return container
    } catch {
      fatalError("Could not open the recordings store: \(error)")
    }
  }

  #if DEBUG
  @MainActor
  private static func seed(_ context: ModelContext) {
    let day: TimeInterval = 86_400
    let samples: [(String?, TimeInterval, TimeInterval, String)] = [
      ("Thursday planning", 0, 125,
       "Here is the plan for Thursday. We move the design review to ten, and Maria shares the new onboarding screens before lunch."),
      (nil, day, 47,
       "Reminder: call the landlord about the heating, and pick up the parcel from the post office before six."),
      ("Lecture notes, week 4", 3 * day, 2_710,
       "Today we look at how memory is organised in the cortex, starting from the classic experiments on place cells."),
    ]
    for (title, age, duration, text) in samples {
      context.insert(Recording(timestamp: Date().addingTimeInterval(-age), duration: duration,
                               transcriptText: text, title: title))
    }
    try? context.save()
  }
  #endif

  /// The recorder the app starts with.
  @MainActor
  static func makeRecorder() -> RealTimeWhisper {
    #if DEBUG
    if usesScriptedSession {
      return RealTimeWhisper(makeSession: { _, _, _ in ScriptedTranscriptionSession() })
    }
    #endif
    return RealTimeWhisper()
  }
}
