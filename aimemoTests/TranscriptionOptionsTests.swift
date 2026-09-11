//
//  TranscriptionOptionsTests.swift
//  aimemoTests
//
//  TranscriptionLanguage / TranscriptionOptions: catalogue, persistence, and
//  the Apple Speech locale resolution that used to be hardcoded to en-US.
//

import Foundation
import Speech
import Testing
@testable import aimemo

@Suite(.serialized)
final class TranscriptionOptionsTests {
  private static let languageKey = "selectedTranscriptionLanguage"
  private static let translateKey = "translateToEnglish"
  private static let vocabularyKey = "customVocabulary"

  private let saved = [languageKey, translateKey, vocabularyKey]
    .reduce(into: [String: Any?]()) { $0[$1] = UserDefaults.standard.object(forKey: $1) }

  deinit {
    for (key, value) in saved {
      if let value { UserDefaults.standard.set(value, forKey: key) }
      else { UserDefaults.standard.removeObject(forKey: key) }
    }
  }

  // MARK: - Language catalogue

  @Test func catalogueComesFromWhisperAndIsNonTrivial() {
    // Read from whisper at runtime, so it tracks the bundled models rather
    // than a hardcoded list that can drift.
    #expect(TranscriptionLanguage.allSpecific.count > 50)
  }

  @Test func catalogueIsSortedByDisplayNameAndHasNoDuplicates() {
    let names = TranscriptionLanguage.allSpecific.map(\.displayName)
    #expect(names == names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    #expect(Set(TranscriptionLanguage.allSpecific.map(\.code)).count == TranscriptionLanguage.allSpecific.count)
  }

  @Test func catalogueContainsTheLanguagesTheIntegrationTestCovers() {
    let codes = Set(TranscriptionLanguage.allSpecific.map(\.code))
    for code in ["en", "de", "es", "fr", "it", "ja"] {
      #expect(codes.contains(code), "whisper should know '\(code)'")
    }
  }

  @Test func automaticMapsToWhispersAutoSentinel() {
    #expect(TranscriptionLanguage.automatic.code == "auto")
  }

  @Test func displayNameIsLocalizedNotTheRawCode() {
    let german = TranscriptionLanguage.specific("de")
    #expect(german.displayName != "de")
    #expect(german.displayName.count > 2)
  }

  // MARK: - Language persistence

  @Test func languageDefaultsToAutomaticWhenUnset() {
    UserDefaults.standard.removeObject(forKey: Self.languageKey)
    #expect(TranscriptionLanguage.selected == .automatic)
  }

  @Test func languageRoundTrips() {
    TranscriptionLanguage.selected = .specific("de")
    #expect(TranscriptionLanguage.selected == .specific("de"))
    TranscriptionLanguage.selected = .automatic
    #expect(TranscriptionLanguage.selected == .automatic)
  }

  @Test func languageFallsBackToAutomaticOnUnknownCode() {
    // A code this whisper build does not know must not be pinned into params.
    UserDefaults.standard.set("klingon", forKey: Self.languageKey)
    #expect(TranscriptionLanguage.selected == .automatic)
  }

  // MARK: - Options

  @Test func defaultOptionsPreserveThePreviousHardcodedBehaviour() {
    // Before this change whisper always ran auto / no translation / no prompt.
    let options = TranscriptionOptions.default
    #expect(options.language == .automatic)
    #expect(options.translateToEnglish == false)
    #expect(options.initialPrompt == nil)
  }

  @Test func initialPromptIsNilWhenVocabularyIsBlank() {
    #expect(TranscriptionOptions(customVocabulary: "").initialPrompt == nil)
    #expect(TranscriptionOptions(customVocabulary: "   \n ").initialPrompt == nil)
  }

  @Test func initialPromptTrimsButPreservesContent() {
    let options = TranscriptionOptions(customVocabulary: "  Kunze, SwiftData, whisper.cpp \n")
    #expect(options.initialPrompt == "Kunze, SwiftData, whisper.cpp")
  }

  @Test func currentReadsEachSettingFromDefaults() {
    TranscriptionLanguage.selected = .specific("fr")
    TranscriptionOptions.translateToEnglishSetting = true
    TranscriptionOptions.customVocabularySetting = "Anthropic"

    let options = TranscriptionOptions.current
    #expect(options.language == .specific("fr"))
    #expect(options.translateToEnglish)
    #expect(options.initialPrompt == "Anthropic")
  }

  // MARK: - Apple Speech locale (S4)

  @Test func appleSpeechResolvesAPinnedLanguageRatherThanAlwaysEnUS() throws {
    let supported = SFSpeechRecognizer.supportedLocales()
    let german = try #require(
      supported.first { $0.language.languageCode?.identifier == "de" },
      "device has no German speech locale installed"
    )
    let resolved = AppleSpeechRecognizer.preferredLocale(for: .specific("de"))
    #expect(resolved.language.languageCode?.identifier == "de")
    #expect(supported.contains(resolved))
    _ = german
  }

  @Test func appleSpeechFallsBackToASupportedLocaleForUnknownLanguages() {
    // Whisper knows far more languages than Apple Speech does; an unsupported
    // pin must degrade to something the recognizer can actually construct.
    let resolved = AppleSpeechRecognizer.preferredLocale(for: .specific("yo"))
    let supported = SFSpeechRecognizer.supportedLocales()
    #expect(supported.contains(resolved) || resolved.identifier == "en-US")
  }

  @Test func appleSpeechAutomaticUsesTheDeviceLanguage() {
    let resolved = AppleSpeechRecognizer.preferredLocale(for: .automatic)
    let device = Locale.current.language.languageCode?.identifier
    let supportsDevice = SFSpeechRecognizer.supportedLocales()
      .contains { $0.language.languageCode?.identifier == device }
    if supportsDevice {
      #expect(resolved.language.languageCode?.identifier == device)
    } else {
      #expect(resolved.identifier == "en-US")
    }
  }
}
