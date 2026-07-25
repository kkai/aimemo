//
//  MultilingualTranscriptionTests.swift
//  aimemoTests
//
//  Integration test proving the bundled multilingual Whisper model auto-detects
//  and transcribes several languages (no language picker; runs on `auto`).
//
//  Audio fixtures in Resources/audio/ were generated with macOS `say` and
//  converted to 16 kHz mono Int16 WAV (afconvert). Model + fixtures are resolved
//  from the source tree via #filePath (the iOS simulator can read the host FS),
//  falling back to the test bundle.
//

import Testing
import Foundation
@testable import aimemo

private final class BundleToken {}

struct MultilingualTranscriptionTests {

  /// file base, expected whisper language code, and lowercase keywords that must
  /// appear in the transcript (proves the audio was transcribed in that language).
  static let languages: [(file: String, expected: String, keywords: [String])] = [
    ("en", "en", ["fox", "seashore"]),
    ("de", "de", ["fuchs", "hund", "wochenende"]),
    ("es", "es", ["playa", "perezoso", "zorro"]),
    ("fr", "fr", ["mer", "chien", "renard"]),
    ("it", "it", ["volpe", "mare", "piace"]),
    ("ja", "ja", ["キツネ", "週末", "犬"]),
  ]

  // MARK: - Fixture / model resolution

  private static var sourceDir: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent()  // aimemoTests/
  }

  private static func audioURL(_ base: String) -> URL? {
    let src = sourceDir.appendingPathComponent("Resources/audio/\(base).wav")
    if FileManager.default.fileExists(atPath: src.path) { return src }
    return Bundle(for: BundleToken.self).url(forResource: base, withExtension: "wav")
  }

  private static var modelURL: URL? {
    // Use the same file the app bundles, via the enum so the test tracks it.
    let name = WhisperModel.base.resourceName
    let src = sourceDir
      .deletingLastPathComponent()                 // repo root (…/aimemo)
      .appendingPathComponent("aimemo/Resources/models/\(name).bin")
    if FileManager.default.fileExists(atPath: src.path) { return src }
    return Bundle.main.url(forResource: name, withExtension: "bin", subdirectory: "models")
      ?? Bundle.main.url(forResource: name, withExtension: "bin")
  }

  private static var canRun: Bool {
    guard let m = modelURL, FileManager.default.fileExists(atPath: m.path) else { return false }
    return languages.allSatisfy { audioURL($0.file) != nil }
  }

  // MARK: - Minimal 16-bit PCM WAV decoder → normalized mono Float

  private static func loadWavMono16(_ url: URL) throws -> [Float] {
    let bytes = [UInt8](try Data(contentsOf: url))
    func u32(_ i: Int) -> Int {
      Int(bytes[i]) | Int(bytes[i + 1]) << 8 | Int(bytes[i + 2]) << 16 | Int(bytes[i + 3]) << 24
    }
    // Walk RIFF chunks to find "data".
    var i = 12
    var dataOffset = -1, dataSize = 0
    while i + 8 <= bytes.count {
      let id = String(bytes: bytes[i..<i + 4], encoding: .ascii) ?? ""
      let size = u32(i + 4)
      if id == "data" { dataOffset = i + 8; dataSize = size; break }
      i += 8 + size + (size & 1)  // chunks are word-aligned
    }
    guard dataOffset >= 0 else { return [] }
    let end = min(dataOffset + dataSize, bytes.count)
    var floats = [Float]()
    floats.reserveCapacity((end - dataOffset) / 2)
    var j = dataOffset
    while j + 1 < end {
      let raw = Int16(bitPattern: UInt16(bytes[j]) | UInt16(bytes[j + 1]) << 8)
      floats.append(max(-1.0, min(1.0, Float(raw) / 32768.0)))
      j += 2
    }
    return floats
  }

  // MARK: - Test

  @Test(.enabled(if: MultilingualTranscriptionTests.canRun))
  func detectsAndTranscribesMultipleLanguages() async throws {
    let model = try #require(Self.modelURL)
    let context = try WhisperContext(path: model)

    var transcribedOK = 0
    var detectedOK = 0
    for lang in Self.languages {
      let url = try #require(Self.audioURL(lang.file))
      let samples = try Self.loadWavMono16(url)
      #expect(samples.count > 16_000, "\(lang.file): expected >1s of audio, got \(samples.count) samples")

      await context.fullTranscribe(samples: samples)
      let detected = await context.detectedLanguage()
      let text = await context.getTranscription().trimmingCharacters(in: .whitespacesAndNewlines)
      let lower = text.lowercased()
      let hit = lang.keywords.first(where: { lower.contains($0.lowercased()) })

      if hit != nil { transcribedOK += 1 }
      if detected == lang.expected { detectedOK += 1 }
      print("[multilingual] \(lang.file): detected=\(detected ?? "nil") keyword=\(hit ?? "MISS") text=\"\(text)\"")

      // Primary proof: the clip was transcribed in its own language.
      #expect(hit != nil,
              "\(lang.file): none of \(lang.keywords) found in transcript \"\(text)\"")
      // Secondary: whisper auto-detected the language.
      #expect(detected == lang.expected,
              "\(lang.file): expected detected language '\(lang.expected)', got '\(detected ?? "nil")'")
    }

    // The explicit requirement: at least 4 languages transcribed correctly.
    #expect(transcribedOK >= 4, "Only \(transcribedOK)/\(Self.languages.count) languages transcribed correctly")
    print("[multilingual] transcribed OK: \(transcribedOK)/\(Self.languages.count), detected OK: \(detectedOK)/\(Self.languages.count)")
  }
}
