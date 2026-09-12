//
//  RealAudioWindowingTests.swift
//  aimemoTests
//
//  Window policy against the real recorded fixtures, with a fake engine, so
//  boundary behaviour on actual speech is diagnosable in milliseconds.
//

import Foundation
import Testing
@testable import aimemo

struct RealAudioWindowingTests {

  private static var sourceDir: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  }

  private static func fixture(_ base: String) -> [Float]? {
    let url = sourceDir.appendingPathComponent("Resources/audio/\(base).wav")
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try? WavFixture.load(url)
  }

  private static var canRun: Bool { fixture("en") != nil }

  @Test(.enabled(if: RealAudioWindowingTests.canRun))
  func realSpeechEnergyClearsTheSilenceThreshold() throws {
    let samples = try #require(Self.fixture("en"))
    let policy = TranscriptionWindow.Policy()
    let frame = policy.samplesPerFrame

    var speechFrames = 0
    var quietFrames = 0
    var maxEnergy: Float = 0
    var i = 0
    while i + frame <= samples.count {
      let energy = AudioSamples.energy(of: samples[i..<(i + frame)])
      maxEnergy = max(maxEnergy, energy)
      if energy >= policy.absoluteSilenceEnergy { speechFrames += 1 } else { quietFrames += 1 }
      i += frame
    }
    print("[energy] speech=\(speechFrames) quiet=\(quietFrames) max=\(maxEnergy) threshold=\(policy.absoluteSilenceEnergy)")
    #expect(speechFrames > 0, "no frame of real speech cleared the threshold")
    #expect(maxEnergy > policy.absoluteSilenceEnergy * 10)
  }

  @Test(.enabled(if: RealAudioWindowingTests.canRun))
  func gapsBetweenRepeatedFixturesAreDetectedAsPauses() throws {
    // This is the case the end-to-end pipeline test got wrong: three copies of
    // the fixture separated by a full second of digital silence should commit
    // three windows, not one.
    let fixture = try #require(Self.fixture("en"))
    let gap = TestSignals.silence(seconds: 1.0)
    let signal = fixture + gap + fixture + gap + fixture

    var window = TranscriptionWindow()
    var closed: [TranscriptionWindow.Closed] = []
    TestSignals.feed(signal, chunk: 1024) { chunk in
      var decision = window.append(chunk)
      while case .commit(let reason) = decision {
        closed.append(window.close(reason: reason))
        decision = window.append([])
      }
    }
    while case .commit(let reason) = window.prepareFlush() {
      closed.append(window.close(reason: reason))
    }

    print("[gaps] windows=\(closed.count) durations=\(closed.map { String(format: "%.2f", $0.duration) }) reasons=\(closed.map(\.reason))")
    #expect(closed.count == 3, "expected one window per fixture, got \(closed.count)")
  }

  @Test(.enabled(if: RealAudioWindowingTests.canRun))
  func aSingleFixtureCommitsExactlyOneWindow() throws {
    let fixture = try #require(Self.fixture("en"))
    var window = TranscriptionWindow()
    var closed: [TranscriptionWindow.Closed] = []
    TestSignals.feed(fixture, chunk: 1024) { chunk in
      var decision = window.append(chunk)
      while case .commit(let reason) = decision {
        closed.append(window.close(reason: reason))
        decision = window.append([])
      }
    }
    while case .commit(let reason) = window.prepareFlush() {
      closed.append(window.close(reason: reason))
    }
    print("[single] windows=\(closed.count) durations=\(closed.map { String(format: "%.2f", $0.duration) })")
    #expect(closed.count == 1)
  }

  @Test(.enabled(if: RealAudioWindowingTests.canRun))
  func pipelineCommitsOneDecodePerFixtureWithAFakeEngine() async throws {
    let fixture = try #require(Self.fixture("en"))
    let gap = TestSignals.silence(seconds: 1.0)
    let signal = fixture + gap + fixture + gap + fixture

    let fake = FakeWindowTranscriber(texts: ["one.", "two.", "three."])
    let core = StreamingTranscriber(transcriber: fake, options: .default)
    await core.start()
    TestSignals.feed(signal, chunk: 1024) { core.ingest($0) }
    let final = await core.finish()

    print("[fake pipeline] calls=\(await fake.callCount) text=\"\(final)\"")
    #expect(await fake.callCount == 3)
    #expect(final == "one. two. three.")
  }
}

/// Minimal 16-bit PCM WAV reader shared by the fixture-driven suites.
enum WavFixture {
  static func load(_ url: URL) throws -> [Float] {
    let bytes = [UInt8](try Data(contentsOf: url))
    func u32(_ i: Int) -> Int {
      Int(bytes[i]) | Int(bytes[i + 1]) << 8 | Int(bytes[i + 2]) << 16 | Int(bytes[i + 3]) << 24
    }
    var i = 12
    var dataOffset = -1, dataSize = 0
    while i + 8 <= bytes.count {
      let id = String(bytes: bytes[i..<i + 4], encoding: .ascii) ?? ""
      let size = u32(i + 4)
      if id == "data" { dataOffset = i + 8; dataSize = size; break }
      i += 8 + size + (size & 1)
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
}
