//
//  TranscriptionWindow.swift
//  aimemo
//
//  The open, uncommitted audio plus the rule for closing it
//

import Foundation

/// Buffers incoming audio and decides when enough of it forms a window worth
/// handing to whisper.
///
/// Time is derived from sample counts, never from a clock: 16 000 samples *is*
/// one second. Every decision is therefore a pure function of the ingested
/// sample sequence, which is what makes the commit policy testable without a
/// microphone, a model, or a single `sleep`.
struct TranscriptionWindow: Sendable {

  struct Policy: Equatable, Sendable {
    var sampleRate: Double = 16_000

    /// whisper returns *zero* segments below 1000ms (whisper.cpp:5253-5259),
    /// silently. This floor plus margin keeps every window decodable.
    var minimumDuration: TimeInterval = 1.2

    /// Force-commit ceiling. Comfortably inside whisper's 30s frame, so a
    /// window is always one encoder pass.
    var maximumDuration: TimeInterval = 22

    /// Contiguous trailing silence that closes a window early.
    var pauseDuration: TimeInterval = 0.6

    /// Silence classification granularity. Chunk-size independence rests on
    /// classifying whole frames of this size and nothing else.
    var frameDuration: TimeInterval = 0.02

    /// Mean-square floor, and the multiple of the tracked noise floor a frame
    /// must exceed to count as speech.
    var absoluteSilenceEnergy: Float = 1e-5
    var relativeSilenceMultiplier: Float = 6

    /// Trailing silence kept in a committed window. A little decay helps
    /// whisper close the sentence; a lot is just encoder cost.
    var retainedSilence: TimeInterval = 0.25

    static let `default` = Policy()

    var framesPerSecond: Double { 1 / frameDuration }
    var samplesPerFrame: Int { Int((sampleRate * frameDuration).rounded()) }
    var minimumSamples: Int { Int((sampleRate * minimumDuration).rounded()) }
    var maximumSamples: Int { Int((sampleRate * maximumDuration).rounded()) }
    var pauseSamples: Int { Int((sampleRate * pauseDuration).rounded()) }
    var retainedSilenceSamples: Int { Int((sampleRate * retainedSilence).rounded()) }
  }

  /// What the caller should do after the most recent `append`.
  enum Decision: Equatable, Sendable {
    case wait
    case commit(Reason)
  }

  enum Reason: Equatable, Sendable {
    /// Trailing silence closed the window at a natural boundary.
    case pause
    /// The window hit `maximumDuration` mid-speech.
    case maximumDuration
    /// Recording stopped or paused; whatever is buffered must be decoded.
    case flush
  }

  struct Closed: Equatable, Sendable {
    /// Window samples, zero-padded up to `minimumDuration` when short.
    let samples: [Float]
    /// True captured duration, before any padding.
    let duration: TimeInterval
    let reason: Reason
  }

  let policy: Policy
  private let detector: PauseDetector

  /// The current window's audio.
  private var samples: [Float] = []
  /// Audio not yet classified into frames: sub-frame residue, plus any backlog
  /// that arrived while the window was already full. Never discarded.
  private var pending: [Float] = []
  /// Length of the current run of trailing quiet frames, in samples.
  private var trailingSilenceSamples = 0
  /// Offset just past the last frame classified as speech. The committed
  /// payload is cut here (plus a little decay), so a long pause is never
  /// handed to the encoder and the cut point cannot drift with chunk size.
  private var lastSpeechEnd = 0
  /// True once any frame in this window has been classified as speech.
  private var sawSpeech = false
  /// Adapts upward in a noisy room. Deliberately starts at the absolute floor
  /// and moves only on frames already judged quiet: letting it track speech
  /// energy creates a feedback loop that reclassifies quiet speech as silence.
  private var noiseFloor: Float

  init(policy: Policy = .default, detector: PauseDetector? = nil) {
    self.policy = policy
    self.noiseFloor = policy.absoluteSilenceEnergy
    self.detector = detector ?? PauseDetector(
      energyThreshold: policy.absoluteSilenceEnergy,
      sampleRate: Float(policy.sampleRate),
      bufferDuration: policy.frameDuration
    )
  }

  // MARK: - Observation

  var sampleCount: Int { samples.count }
  var duration: TimeInterval { Double(samples.count) / policy.sampleRate }
  var isEmpty: Bool { samples.isEmpty && pending.isEmpty }
  var containsSpeech: Bool { sawSpeech }
  var pendingCount: Int { pending.count }
  var trailingSilence: TimeInterval {
    Double(trailingSilenceSamples) / policy.sampleRate
  }

  // MARK: - Ingestion

  /// Appends 16 kHz mono samples and reports what to do next.
  ///
  /// Deterministic: the same sample sequence yields the same decisions no
  /// matter how it is chunked, because only whole frames are ever classified.
  mutating func append(_ chunk: [Float]) -> Decision {
    guard !chunk.isEmpty else { return decision() }
    pending.append(contentsOf: chunk)
    absorbPending()
    return decision()
  }

  /// Moves whole frames from `pending` into the window, stopping once the
  /// window is full so that a large chunk cannot overshoot `maximumDuration`.
  /// Whatever will not fit stays in `pending` for the next window.
  private mutating func absorbPending() {
    let frameSize = policy.samplesPerFrame
    var consumed = 0
    while pending.count - consumed >= frameSize {
      // Stop the instant a window is due. Evaluating per frame rather than per
      // append is what makes the cut points identical at any chunk size.
      if case .commit = decision() { break }
      absorb(pending[consumed..<(consumed + frameSize)])
      consumed += frameSize
    }
    if consumed > 0 {
      pending.removeFirst(consumed)
    }
  }

  /// Classifies one complete frame and folds it into the window.
  private mutating func absorb(_ frame: ArraySlice<Float>) {
    let energy = AudioSamples.energy(of: frame)
    let threshold = max(policy.absoluteSilenceEnergy,
                        noiseFloor * policy.relativeSilenceMultiplier)
    let isSpeech = energy >= threshold

    if !isSpeech {
      // Track the room, not the speaker.
      noiseFloor += (energy - noiseFloor) * 0.05
    }

    // A window never starts on silence: leading quiet is discarded so that
    // pure-silence stretches never accumulate and never reach whisper.
    guard isSpeech || sawSpeech else { return }

    if isSpeech {
      samples.append(contentsOf: frame)
      sawSpeech = true
      trailingSilenceSamples = 0
      lastSpeechEnd = samples.count
    } else {
      trailingSilenceSamples += frame.count
      // Buffer only as much trailing quiet as a commit could possibly keep.
      if samples.count - lastSpeechEnd < policy.retainedSilenceSamples {
        samples.append(contentsOf: frame)
      }
    }
  }

  private func decision() -> Decision {
    guard sawSpeech else { return .wait }

    if samples.count >= policy.maximumSamples {
      return .commit(.maximumDuration)
    }
    if lastSpeechEnd >= policy.minimumSamples,
       trailingSilenceSamples >= policy.pauseSamples {
      return .commit(.pause)
    }
    return .wait
  }

  // MARK: - Closing

  /// Empties the window and hands back its samples, padded past whisper's floor.
  ///
  /// `pending` survives: backlog that arrived while this window was full is
  /// immediately absorbed into the next one, so no audio is ever dropped.
  mutating func close(reason: Reason) -> Closed {
    let keep = min(samples.count, lastSpeechEnd + policy.retainedSilenceSamples)
    let captured = Array(samples.prefix(keep))
    let capturedDuration = Double(captured.count) / policy.sampleRate

    var payload = captured
    if payload.count < policy.minimumSamples {
      // Without this the last words of a recording vanish into whisper's
      // sub-second early return.
      payload.append(contentsOf: [Float](repeating: 0,
                                         count: policy.minimumSamples - payload.count))
    }

    samples.removeAll(keepingCapacity: true)
    trailingSilenceSamples = 0
    lastSpeechEnd = 0
    sawSpeech = false

    absorbPending()

    return Closed(samples: payload, duration: capturedDuration, reason: reason)
  }

  /// Decision at stop or pause. Drains `pending` first — including a final
  /// sub-frame residue — so trailing speech shorter than one frame is not lost.
  ///
  /// Call repeatedly until it returns `.wait`: a long backlog can hold more
  /// than one window's worth of audio.
  mutating func prepareFlush() -> Decision {
    absorbPending()

    if !pending.isEmpty, samples.count < policy.maximumSamples {
      // Residue shorter than a frame. Keep it only if this window already has
      // speech; otherwise it is trailing room tone and goes nowhere.
      if sawSpeech {
        samples.append(contentsOf: pending)
        lastSpeechEnd = samples.count
      }
      pending.removeAll(keepingCapacity: true)
    }

    return sawSpeech ? .commit(.flush) : .wait
  }
}
