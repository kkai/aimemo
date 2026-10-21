//
//  LaunchOptions.swift
//  aimemo
//
//  Launch arguments for UI tests and screenshots (DEBUG builds only)
//

import Foundation

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
