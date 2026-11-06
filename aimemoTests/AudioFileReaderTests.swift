//
//  AudioFileReaderTests.swift
//  aimemoTests
//
//  The file reader against a real m4a, and its failure modes.
//

import Foundation
import Testing
@testable import aimemo

struct AudioFileReaderTests {

  private static var fixtures: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Resources/audio")
  }
  private static var m4a: URL { fixtures.appendingPathComponent("en.m4a") }
  private static var canRun: Bool { FileManager.default.fileExists(atPath: m4a.path) }

  @Test(.enabled(if: AudioFileReaderTests.canRun))
  func durationComesFromTheContainer() async throws {
    let duration = try await AudioFileReader(url: Self.m4a).duration()
    #expect(abs(duration - 4.67) < 0.1)
  }

  @Test(.enabled(if: AudioFileReaderTests.canRun))
  func decodesToSixteenKilohertzMonoInOrderedChunks() async throws {
    let reader = AudioFileReader(url: Self.m4a, chunkDuration: 1)
    var chunks: [[Float]] = []
    for try await chunk in reader.samples() { chunks.append(chunk) }

    let total = chunks.reduce(0) { $0 + $1.count }
    // 4.67 s at 16 kHz, give or take the AAC encoder's priming frames.
    #expect(abs(total - 74_683) < 4_096)
    // Whole 1 s chunks, then a tail.
    #expect(chunks.dropLast().allSatisfy { $0.count == 16_000 })
    #expect(chunks.count == 5)
    // It is speech, not zeros: well above the silence floor somewhere.
    let peak = chunks.flatMap { $0 }.map(abs).max() ?? 0
    #expect(peak > 0.05)
    #expect(peak <= 1.0)
  }

  @Test(.enabled(if: AudioFileReaderTests.canRun))
  func matchesTheWavWithinCodecTolerance() async throws {
    let wav = try WavFixture.load(Self.fixtures.appendingPathComponent("en.wav"))
    var decoded: [Float] = []
    for try await chunk in AudioFileReader(url: Self.m4a).samples() { decoded.append(contentsOf: chunk) }
    // Same loudness envelope: compare RMS of the whole clip.
    func rms(_ x: [Float]) -> Float { (x.reduce(0) { $0 + $1 * $1 } / Float(max(x.count, 1))).squareRoot() }
    #expect(abs(rms(wav) - rms(decoded)) < 0.02)
  }

  @Test func aFileWithoutAudioIsReported() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("not-audio-\(UUID()).txt")
    try "hello".write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }

    await #expect(throws: AudioFileReader.ImportError.self) {
      for try await _ in AudioFileReader(url: url).samples() {}
    }
  }

  @Test func aMissingFileIsReported() async {
    let url = URL(fileURLWithPath: "/nonexistent/\(UUID()).m4a")
    await #expect(throws: AudioFileReader.ImportError.self) {
      for try await _ in AudioFileReader(url: url).samples() {}
    }
  }

  // MARK: - Staging

  @Test func stagingCopiesTheFileAndKeepsItsName() throws {
    let source = FileManager.default.temporaryDirectory.appendingPathComponent("Lecture 4 \(UUID()).m4a")
    try Data([1, 2, 3]).write(to: source)
    defer { try? FileManager.default.removeItem(at: source) }

    let staged = try ImportedFile.stage(source)
    defer { staged.discard() }
    #expect(staged.displayName == source.lastPathComponent)
    #expect(staged.url != source)
    #expect(FileManager.default.contentsEqual(atPath: staged.url.path, andPath: source.path))
    #expect(FileManager.default.fileExists(atPath: source.path), "a picked file is left where it was")
  }

  @Test func discardRemovesTheCopy() throws {
    let source = FileManager.default.temporaryDirectory.appendingPathComponent("x-\(UUID()).m4a")
    try Data([1]).write(to: source)
    defer { try? FileManager.default.removeItem(at: source) }
    let staged = try ImportedFile.stage(source)
    staged.discard()
    #expect(!FileManager.default.fileExists(atPath: staged.url.path))
  }

  @Test(arguments: [
    ("New Recording 12.m4a", nil),
    ("Recording.m4a", nil),
    ("IMG_2041.mov", nil),
    ("audio-2025-11-06.mp3", nil),
    ("Lecture 4.m4a", "Lecture 4"),
    ("Recording of the board meeting.m4a", "Recording of the board meeting"),
    (".m4a", nil),
  ])
  func genericNamesMakeNoTitle(name: String, expected: String?) {
    let file = ImportedFile(url: URL(fileURLWithPath: "/tmp/\(name)"), displayName: name)
    #expect(file.suggestedTitle == expected)
  }
}
