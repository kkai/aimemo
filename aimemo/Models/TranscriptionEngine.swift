//
//  TranscriptionEngine.swift
//  aimemo
//
//  Enum representing available transcription engines
//

import Foundation

enum TranscriptionEngine: String, CaseIterable, Identifiable {
  case whisper = "whisper"
  case appleSpeech = "apple_speech"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .whisper: return "Whisper Models"
    case .appleSpeech: return "Apple Speech"
    }
  }

  var description: String {
    switch self {
    case .whisper:
      return "Offline, multilingual, highest accuracy"
    case .appleSpeech:
      return "Fast, system-integrated transcription"
    }
  }

  // Persist selected engine using UserDefaults
  static var selected: TranscriptionEngine {
    get {
      guard let rawValue = UserDefaults.standard.string(forKey: "selectedTranscriptionEngine"),
            let engine = TranscriptionEngine(rawValue: rawValue) else {
        return .whisper  // Default to Whisper for existing users
      }
      return engine
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "selectedTranscriptionEngine")
    }
  }
}
