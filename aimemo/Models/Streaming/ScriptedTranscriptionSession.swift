//
//  ScriptedTranscriptionSession.swift
//  aimemo
//
//  DEBUG only: a recording that plays a fixed script, for UI tests and
//  screenshots without a microphone
//

#if DEBUG
import Foundation

/// Plays a transcript word by word with a moving meter, honouring pause and
/// resume. The simulator microphone only works after a reboot, so UI audits
/// of the recording screen run against this instead.
@MainActor
final class ScriptedTranscriptionSession: LiveTranscriptionSession {

  static let script = """
    Here is the plan for Thursday. We move the design review to ten, \
    and Maria shares the new onboarding screens before lunch.
    """

  let updates: AsyncStream<TranscriptionUpdate>
  private let continuation: AsyncStream<TranscriptionUpdate>.Continuation
  private let words = ScriptedTranscriptionSession.script.split(separator: " ").map(String.init)
  private var spoken = 0
  /// Words before this index are committed; the rest of `spoken` is open.
  private var committedUpTo = 0
  private var transcript = LiveTranscript()
  private var player: Task<Void, Never>?

  init() {
    var sink: AsyncStream<TranscriptionUpdate>.Continuation!
    self.updates = AsyncStream(bufferingPolicy: .unbounded) { sink = $0 }
    self.continuation = sink
  }

  func start() async throws {
    continuation.yield(.detectedLanguage("en"))
    play()
  }

  /// Commits the open sentence, as the Whisper session commits its window.
  func pause() async {
    player?.cancel()
    player = nil
    commitOpenWords()
    continuation.yield(.transcript(transcript))
  }

  func resume() async throws { play() }

  func finish() async -> String {
    player?.cancel()
    spoken = words.count
    commitOpenWords()
    continuation.yield(.transcript(transcript))
    continuation.finish()
    return transcript.committed
  }

  func finalSegments() async -> [TranscriptSegment] { transcript.committedSegments }

  func cancel() async {
    player?.cancel()
    continuation.finish()
  }

  /// Words arrive every 300 ms, so the script has a timeline of its own.
  private static let secondsPerWord: TimeInterval = 0.3

  private func commitOpenWords() {
    let text = words[committedUpTo..<spoken].joined(separator: " ")
    let segment = TranscriptSegment(text: text,
                                    start: Double(committedUpTo) * Self.secondsPerWord,
                                    end: Double(spoken) * Self.secondsPerWord)
    transcript.commit(text, segments: text.isEmpty ? [] : [segment])
    committedUpTo = spoken
  }

  private func play() {
    player = Task { [weak self] in
      var tick = 0
      while let self, !Task.isCancelled {
        tick += 1
        self.continuation.yield(.level(Float(0.25 + 0.6 * abs(sin(Double(tick) / 3)))))
        // A word every 300 ms; a committed sentence every eight words.
        if tick % 3 == 0, self.spoken < self.words.count {
          self.spoken += 1
          if self.spoken - self.committedUpTo == 8 {
            self.commitOpenWords()
          } else {
            let open = self.words[self.committedUpTo..<self.spoken]
            self.transcript.setProvisional(open.joined(separator: " "), confidence: 0.9)
          }
          self.continuation.yield(.transcript(self.transcript))
        }
        try? await Task.sleep(for: .milliseconds(100))
      }
    }
  }
}
#endif
