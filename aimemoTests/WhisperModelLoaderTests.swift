//
//  WhisperModelLoaderTests.swift
//  aimemoTests
//
//  Bundle resolution and the free/Pro fallback rule.
//

import Testing
@testable import aimemo

struct WhisperModelLoaderTests {
  private let loader = WhisperModelLoader()

  @Test func baseIsAlwaysBundled() {
    // The one model every target ships; the free app ships only this.
    #expect(loader.bundledURL(for: .base) != nil)
  }

  @Test func everyModelListedAsBundledResolves() {
    for model in WhisperModel.bundled {
      #expect(loader.bundledURL(for: model) != nil,
              "\(model.resourceName).bin is listed as bundled but is not in the app")
    }
  }

  @Test func unbundledModelsFallBackToBase() {
    // Guards the project.pbxproj membership split: a selection persisted by a
    // build that shipped more models must degrade, not leave a nil context.
    let baseURL = loader.bundledURL(for: .base)
    for model in WhisperModel.allCases where !model.isBundled {
      #expect(loader.bundledURL(for: model) == nil)
      #expect(loader.resolvedURL(for: model) == baseURL,
              "\(model.resourceName) should fall back to base")
    }
  }

  @Test func resolvedURLPrefersTheModelItself() {
    for model in WhisperModel.bundled {
      #expect(loader.resolvedURL(for: model) == loader.bundledURL(for: model))
    }
  }

  @Test func makeContextLoadsTheDefaultModel() throws {
    // Smoke test for the load path, replacing the one that used to live in
    // AudioSampleConversionTests via a shared RealTimeWhisper instance.
    _ = try loader.makeContext(for: .base)
  }
}
