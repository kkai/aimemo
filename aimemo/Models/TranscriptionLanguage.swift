//
//  TranscriptionLanguage.swift
//  aimemo
//
//  Language selection for transcription: automatic detection or a fixed language
//

import Foundation
import whisper

/// The language Whisper should transcribe in.
///
/// Whisper auto-detects by default, which is right for most recordings but
/// misfires on short clips — a two-second German note is easily read as Dutch.
/// Picking a language pins `whisper_full_params.language` instead.
///
/// The catalogue is read from whisper at runtime (`whisper_lang_max_id`,
/// `whisper_lang_str`), never hardcoded, so it cannot drift from what the
/// bundled models actually support.
enum TranscriptionLanguage: Hashable, Identifiable {
  case automatic
  /// ISO 639-1 code, spelled the way whisper spells it.
  case specific(String)

  var id: String { code }

  /// The value handed to `whisper_full_params.language`.
  var code: String {
    switch self {
    case .automatic: return "auto"
    case .specific(let code): return code
    }
  }

  var displayName: String {
    switch self {
    case .automatic:
      return "Automatic"
    case .specific(let code):
      return Self.localizedName(for: code)
    }
  }

  /// Language name in the user's own locale, falling back to whisper's English
  /// name and finally to the raw code.
  static func localizedName(for code: String) -> String {
    if let name = Locale.current.localizedString(forLanguageCode: code), name != code {
      return name.localizedCapitalized
    }
    let id = whisper_lang_id(code)
    if id >= 0, let full = whisper_lang_str_full(id) {
      return String(cString: full).localizedCapitalized
    }
    return code.uppercased()
  }

  /// Every language whisper knows, alphabetised by display name.
  static let allSpecific: [TranscriptionLanguage] = {
    let maxId = whisper_lang_max_id()
    guard maxId >= 0 else { return [] }
    return (0...maxId)
      .compactMap { whisper_lang_str($0).map { TranscriptionLanguage.specific(String(cString: $0)) } }
      .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
  }()

  /// The device's own language, when whisper supports it — offered near the top
  /// of the picker since it is the most likely manual choice.
  static var deviceLanguage: TranscriptionLanguage? {
    guard let code = Locale.current.language.languageCode?.identifier,
          whisper_lang_id(code) >= 0 else { return nil }
    return .specific(code)
  }

  // MARK: - Persistence

  private static let key = "selectedTranscriptionLanguage"

  static var selected: TranscriptionLanguage {
    get {
      guard let stored = UserDefaults.standard.string(forKey: key), stored != "auto" else {
        return .automatic
      }
      // A code that this whisper build does not know must not be pinned.
      guard whisper_lang_id(stored) >= 0 else { return .automatic }
      return .specific(stored)
    }
    set {
      UserDefaults.standard.set(newValue.code, forKey: key)
    }
  }
}
