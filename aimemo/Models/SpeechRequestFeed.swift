//
//  SpeechRequestFeed.swift
//  aimemo
//
//  The recognition request the audio tap appends to, swappable across threads
//

import AVFoundation
import Speech

/// Holds the request the audio tap feeds. The tap runs on the render thread and
/// the request is replaced on main whenever a recognition task restarts, so the
/// slot is guarded by a lock. `nil` drops buffers (between tasks, after stop).
final class SpeechRequestFeed: @unchecked Sendable {
  private let lock = NSLock()
  private var request: SFSpeechAudioBufferRecognitionRequest?

  func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
    lock.lock()
    self.request = request
    lock.unlock()
  }

  /// `append` is documented as callable from any thread.
  func append(_ buffer: AVAudioPCMBuffer) {
    lock.lock()
    let current = request
    lock.unlock()
    current?.append(buffer)
  }
}
