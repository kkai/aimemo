//
//  WhisperModel.swift
//  aimemo
//
//  Enum representing available Whisper models with metadata
//

import Foundation

enum WhisperModel: String, CaseIterable, Identifiable {
  // Stable identities, persisted in UserDefaults. The bundled model file is
  // resolved separately via `resourceName` so the ggml build can change
  // (quantization, multilingual) without invalidating a user's saved choice.
  case tiny
  case base
  case small
  case medium

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .tiny: return "Tiny"
    case .base: return "Base"
    case .small: return "Small"
    case .medium: return "Medium"
    }
  }

  /// Bundled model file name without extension. These are the quantized,
  /// multilingual ggml builds shipped in Resources/models/.
  var resourceName: String {
    switch self {
    case .tiny: return "ggml-tiny-q5_1"
    case .base: return "ggml-base-q5_1"
    case .small: return "ggml-small-q5_1"
    case .medium: return "ggml-medium-q5_0"
    }
  }

  var fileName: String {
    "\(resourceName).bin"
  }

  var fileSize: String {
    switch self {
    case .tiny: return "31 MB"
    case .base: return "57 MB"
    case .small: return "181 MB"
    case .medium: return "514 MB"
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
    case .tiny: return "Fastest, multilingual, lower accuracy"
    case .base: return "Balanced multilingual model - recommended"
    case .small: return "High accuracy, multilingual"
    case .medium: return "Highest quality, multilingual, more resources"
    }
  }

  var memoryRequirement: String {
    switch self {
    case .tiny: return "~150 MB RAM"
    case .base: return "~250 MB RAM"
    case .small: return "~600 MB RAM"
    case .medium: return "~1.5 GB RAM"
    }
  }

  /// Maps a persisted UserDefaults value to a model, tolerating the legacy
  /// English-only filenames used before the multilingual model refresh.
  private static func model(fromStored stored: String) -> WhisperModel? {
    if let model = WhisperModel(rawValue: stored) {
      return model
    }
    switch stored {
    case "ggml-tiny.en", "ggml-tiny": return .tiny
    case "ggml-base.en", "ggml-base": return .base
    case "ggml-small.en", "ggml-small": return .small
    case "ggml-medium.en", "ggml-medium": return .medium
    default: return nil
    }
  }

  // Persist selected model using UserDefaults
  static var selected: WhisperModel {
    get {
      guard let stored = UserDefaults.standard.string(forKey: "selectedWhisperModel"),
            let model = model(fromStored: stored) else {
        return .base  // Default model (balanced, multilingual)
      }
      return model
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "selectedWhisperModel")
    }
  }
}
