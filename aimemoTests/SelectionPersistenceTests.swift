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

  @Test func modelDefaultsToBaseWhenUnset() {
    UserDefaults.standard.removeObject(forKey: Self.modelKey)
    #expect(WhisperModel.selected == .base)
  }

  @Test func modelFallsBackToBaseOnGarbageValue() {
    UserDefaults.standard.set("ggml-nonexistent", forKey: Self.modelKey)
    #expect(WhisperModel.selected == .base)
  }

  @Test func selectedModelRoundTrips() {
    // `base` is the one model bundled in every build, so it round-trips
    // regardless of which target hosts this suite.
    WhisperModel.selected = .base
    #expect(WhisperModel.selected == .base)
    #expect(UserDefaults.standard.string(forKey: Self.modelKey) == "base")
  }

  @Test func selectedModelRoundTripsForEveryBundledModel() {
    for model in WhisperModel.bundled {
      WhisperModel.selected = model
      #expect(WhisperModel.selected == model)
      #expect(UserDefaults.standard.string(forKey: Self.modelKey) == model.rawValue)
    }
  }

  @Test func selectedModelClampsToBaseWhenNotBundled() {
    // The free target ships only `base`. A value persisted by a build that
    // shipped more models must not leave the app pointing at a missing .bin.
    for model in WhisperModel.allCases where !model.isBundled {
      UserDefaults.standard.set(model.rawValue, forKey: Self.modelKey)
      #expect(WhisperModel.selected == .base)
    }
  }

  // MARK: WhisperModel legacy migration
  //
  // Migration is independent of which models this target bundles, so these
  // exercise `model(fromStored:)` directly rather than going through
  // `selected`, which additionally clamps to `bundled`.

  @Test func modelMigratesLegacyEnglishValue() {
    // Users upgrading from the English-only build have a legacy filename stored.
    #expect(WhisperModel.model(fromStored: "ggml-medium.en") == .medium)
    #expect(WhisperModel.model(fromStored: "ggml-tiny.en") == .tiny)
    #expect(WhisperModel.model(fromStored: "ggml-base.en") == .base)
    #expect(WhisperModel.model(fromStored: "ggml-small.en") == .small)
  }

  @Test func modelMigratesLegacyMultilingualValue() {
    #expect(WhisperModel.model(fromStored: "ggml-medium") == .medium)
    #expect(WhisperModel.model(fromStored: "ggml-base") == .base)
  }

  @Test func modelMigrationRejectsUnknownValue() {
    #expect(WhisperModel.model(fromStored: "ggml-nonexistent") == nil)
  }

  @Test func everyBundledModelHasAFileInTheBundle() {
    // Guards the free/pro resource split in project.pbxproj: if a model is
    // listed as bundled, its .bin must actually ship.
    for model in WhisperModel.bundled {
      let url = Bundle.main.url(forResource: model.resourceName, withExtension: "bin", subdirectory: "models")
        ?? Bundle.main.url(forResource: model.resourceName, withExtension: "bin")
      #expect(url != nil, "\(model.resourceName).bin missing from the app bundle")
    }
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
