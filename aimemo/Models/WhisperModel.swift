//
//  WhisperModel.swift
//  aimemo
//
//  Enum representing available Whisper models with metadata
//

import Foundation

enum WhisperModel: String, CaseIterable, Identifiable {
  case tiny = "ggml-tiny.en"
  case base = "ggml-base.en"
  case small = "ggml-small.en"
  case medium = "ggml-medium.en"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .tiny: return "Tiny"
    case .base: return "Base"
    case .small: return "Small"
    case .medium: return "Medium"
    }
  }

  var fileName: String {
    "\(rawValue).bin"
  }

  var fileSize: String {
    switch self {
    case .tiny: return "75 MB"
    case .base: return "142 MB"
    case .small: return "466 MB"
    case .medium: return "1.5 GB"
    }
  }

  var quality: String {
    switch self {
    case .tiny: return "Fast"
    case .base: return "Good"
    case .small: return "Better"
    case .medium: return "Best"
    }
  }

  var description: String {
    switch self {
    case .tiny: return "Fast transcription, lower accuracy"
    case .base: return "Balanced performance - recommended"
    case .small: return "High accuracy for important recordings"
    case .medium: return "Highest quality, requires more resources"
    }
  }

  var memoryRequirement: String {
    switch self {
    case .tiny: return "~390 MB RAM"
    case .base: return "~500 MB RAM"
    case .small: return "~1 GB RAM"
    case .medium: return "~2.5 GB RAM"
    }
  }

  // Persist selected model using UserDefaults
  static var selected: WhisperModel {
    get {
      guard let rawValue = UserDefaults.standard.string(forKey: "selectedWhisperModel"),
            let model = WhisperModel(rawValue: rawValue) else {
        return .tiny  // Default model
      }
      return model
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "selectedWhisperModel")
    }
  }
}
