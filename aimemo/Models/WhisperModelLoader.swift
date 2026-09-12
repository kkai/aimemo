//
//  WhisperModelLoader.swift
//  aimemo
//
//  Resolves bundled GGML models and builds contexts
//

import Foundation

/// Finds model files in the app bundle and constructs `WhisperContext`s.
///
/// Extracted from `RealTimeWhisper` so the free/Pro fallback rule can be tested
/// without constructing an `@Observable` object or a microphone.
struct WhisperModelLoader: Sendable {

  /// Bundled URL for a model, or nil when this target does not ship it.
  func bundledURL(for model: WhisperModel) -> URL? {
    let name = model.resourceName
    return Bundle.main.url(forResource: name, withExtension: "bin", subdirectory: "models")
      ?? Bundle.main.url(forResource: name, withExtension: "bin", subdirectory: "Resources/models")
      ?? Bundle.main.url(forResource: name, withExtension: "bin")
  }

  /// Bundled URL, falling back to `base` — the one model every target ships.
  ///
  /// The free app bundles only `base`, so a selection persisted by a build that
  /// shipped more models must degrade rather than leave the app with no context.
  func resolvedURL(for model: WhisperModel) -> URL? {
    if let url = bundledURL(for: model) { return url }
    guard model != .base else { return nil }
    print("Model \(model.resourceName) not in bundle; falling back to base")
    return bundledURL(for: .base)
  }

  func makeContext(for model: WhisperModel) throws -> WhisperContext {
    guard let url = resolvedURL(for: model) else {
      throw WhisperError.couldNotInitializeContext
    }
    return try WhisperContext(path: url)
  }
}
