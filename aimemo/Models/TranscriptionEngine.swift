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
      return "Offline AI models with higher accuracy"
    case .appleSpeech:
      return "Fast, system-integrated transcription"
    }
  }

  var speedRating: String {
    switch self {
    case .whisper: return "Good"
    case .appleSpeech: return "Excellent (2.2x faster)"
    }
  }

  var accuracyRating: String {
    switch self {
    case .whisper: return "Excellent (1% WER)"
    case .appleSpeech: return "Good (8% WER)"
    }
  }

  var storageRequirement: String {
    switch self {
    case .whisper: return "75 MB - 1.5 GB"
    case .appleSpeech: return "0 MB (system-provided)"
    }
  }

  var languageSupport: String {
    switch self {
    case .whisper: return "English only (current models)"
    case .appleSpeech: return "10-60+ languages"
    }
  }

  var pros: [String] {
    switch self {
    case .whisper:
      return [
        "Higher accuracy (1% word error rate)",
        "Works completely offline",
        "Open source and transparent",
        "Better for technical/domain content"
      ]
    case .appleSpeech:
      return [
        "2.2x faster transcription",
        "Zero storage overhead",
        "Better battery efficiency",
        "Multi-language support",
        "Optimized for Apple hardware"
      ]
    }
  }

  var cons: [String] {
    switch self {
    case .whisper:
      return [
        "Slower processing",
        "Large model files (75MB-1.5GB)",
        "Higher battery usage",
        "Currently English only"
      ]
    case .appleSpeech:
      return [
        "Lower accuracy (8% word error rate)",
        "Requires speech recognition permission",
        "Less control over behavior",
        "Language support varies by device"
      ]
    }
  }

  var recommendedFor: String {
    switch self {
    case .whisper:
      return "Important recordings, interviews, technical content"
    case .appleSpeech:
      return "Quick notes, meetings, real-time transcription"
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
