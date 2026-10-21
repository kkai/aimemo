//
//  AudioSessionEvents.swift
//  aimemo
//
//  AVAudioSession notifications as one async stream
//

import AVFoundation

/// Observes the shared audio session for as long as it lives.
///
/// Engine-agnostic on purpose: both Whisper and Apple Speech lose their input
/// the same way when a call comes in, so `RealTimeWhisper` handles it once,
/// above the sessions.
@MainActor
final class AudioSessionEvents {

  let events: AsyncStream<AudioSessionEvent>
  private let continuation: AsyncStream<AudioSessionEvent>.Continuation
  private var observers: [NSObjectProtocol] = []
  private let center: NotificationCenter

  init(center: NotificationCenter = .default) {
    self.center = center
    var sink: AsyncStream<AudioSessionEvent>.Continuation!
    self.events = AsyncStream(bufferingPolicy: .unbounded) { sink = $0 }
    self.continuation = sink

    #if os(iOS)
    let session = AVAudioSession.sharedInstance()
    observe(AVAudioSession.interruptionNotification, session) {
      AudioSessionEvent.interruption(from: $0.userInfo)
    }
    observe(AVAudioSession.routeChangeNotification, session) {
      AudioSessionEvent.routeChange(from: $0.userInfo)
    }
    observe(AVAudioSession.mediaServicesWereResetNotification, session) { _ in
      .servicesReset
    }
    #endif
  }

  deinit {
    for observer in observers { center.removeObserver(observer) }
    continuation.finish()
  }

  private func observe(_ name: Notification.Name, _ object: AnyObject,
                       map: @escaping @Sendable (Notification) -> AudioSessionEvent?) {
    let continuation = self.continuation
    // Mapped on the posting thread, so only the Sendable event crosses over.
    observers.append(center.addObserver(forName: name, object: object, queue: nil) { note in
      if let event = map(note) { continuation.yield(event) }
    })
  }
}
