//
//  SelectionPersistenceTests.swift
//  aimemoTests
//
//  WhisperModel.selected / TranscriptionEngine.selected read
//  UserDefaults.standard directly (no injection seam), so this suite runs
//  serialized and restores the host app's defaults after every test.
//

import Foundation
import Testing
@testable import aimemo

@Suite(.serialized)
final class SelectionPersistenceTests {
  private static let modelKey = "selectedWhisperModel"
  private static let engineKey = "selectedTranscriptionEngine"

  private let savedModel = UserDefaults.standard.string(forKey: modelKey)
  private let savedEngine = UserDefaults.standard.string(forKey: engineKey)

  deinit {
    // Class suite: a fresh instance per test, so deinit restores after each.
    restore(Self.modelKey, savedModel)
    restore(Self.engineKey, savedEngine)
  }

  private func restore(_ key: String, _ value: String?) {
    if let value {
      UserDefaults.standard.set(value, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }

  // MARK: WhisperModel.selected

  @Test func modelDefaultsToTinyWhenUnset() {
    UserDefaults.standard.removeObject(forKey: Self.modelKey)
    #expect(WhisperModel.selected == .tiny)
  }

  @Test func modelFallsBackToTinyOnGarbageValue() {
    UserDefaults.standard.set("ggml-nonexistent", forKey: Self.modelKey)
    #expect(WhisperModel.selected == .tiny)
  }

  @Test func selectedModelRoundTrips() {
    WhisperModel.selected = .base
    #expect(WhisperModel.selected == .base)
    #expect(UserDefaults.standard.string(forKey: Self.modelKey) == "ggml-base.en")
  }

  // MARK: TranscriptionEngine.selected

  @Test func engineDefaultsToWhisperWhenUnset() {
    UserDefaults.standard.removeObject(forKey: Self.engineKey)
    #expect(TranscriptionEngine.selected == .whisper)
  }

  @Test func engineFallsBackToWhisperOnGarbageValue() {
    UserDefaults.standard.set("bogus_engine", forKey: Self.engineKey)
    #expect(TranscriptionEngine.selected == .whisper)
  }

  @Test func selectedEngineRoundTrips() {
    TranscriptionEngine.selected = .appleSpeech
    #expect(TranscriptionEngine.selected == .appleSpeech)
    #expect(UserDefaults.standard.string(forKey: Self.engineKey) == "apple_speech")
  }
}
