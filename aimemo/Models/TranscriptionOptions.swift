//
//  TranscriptionOptions.swift
//  aimemo
//
//  User-configurable knobs handed to Whisper on every transcription run
//

import Foundation

/// Everything the user can change about how Whisper reads a recording.
///
/// Passed explicitly into `WhisperContext.fullTranscribe` rather than read from
/// `UserDefaults` down there, so transcription stays a pure function of its
/// inputs and can be tested without touching global state.
struct TranscriptionOptions: Equatable {
  var language: TranscriptionLanguage = .automatic

  /// Whisper's own `translate` flag. The models are trained to translate into
  /// English and only English, so this is a one-way switch: speak any of the
  /// ~99 supported languages, get English text, at no extra model cost.
  var translateToEnglish: Bool = false

  /// Free text seeded into whisper as `initial_prompt`, biasing the decoder
  /// toward spellings it would otherwise guess at — names, jargon, acronyms.
  var customVocabulary: String = ""

  /// `initial_prompt` value, or nil when there is nothing worth seeding.
  var initialPrompt: String? {
    let trimmed = customVocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  static let `default` = TranscriptionOptions()

  // MARK: - Persistence

  private static let translateKey = "translateToEnglish"
  private static let vocabularyKey = "customVocabulary"

  /// The options as currently configured in Settings.
  static var current: TranscriptionOptions {
    TranscriptionOptions(
      language: TranscriptionLanguage.selected,
      translateToEnglish: UserDefaults.standard.bool(forKey: translateKey),
      customVocabulary: UserDefaults.standard.string(forKey: vocabularyKey) ?? ""
    )
  }

  static var translateToEnglishSetting: Bool {
    get { UserDefaults.standard.bool(forKey: translateKey) }
    set { UserDefaults.standard.set(newValue, forKey: translateKey) }
  }

  static var customVocabularySetting: String {
    get { UserDefaults.standard.string(forKey: vocabularyKey) ?? "" }
    set { UserDefaults.standard.set(newValue, forKey: vocabularyKey) }
  }
}
