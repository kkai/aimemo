//
//  AudioSessionEvent.swift
//  aimemo
//
//  What the system does to a recording from outside the app
//

import AVFoundation

/// Interruptions and route changes, reduced to the cases the recorder acts on.
///
/// The parsing is static and takes a plain `userInfo`, so the mapping from
/// AVAudioSession's notifications is unit-tested without posting any.
enum AudioSessionEvent: Equatable, Sendable {
  /// A call, Siri or an alarm took the audio session. The system has already
  /// stopped the engine.
  case interruptionBegan
  case interruptionEnded(shouldResume: Bool)
  /// An input device appeared or went away (headset, AirPods, a USB mic).
  /// AVAudioEngine stops when its input changes under it.
  case inputChanged
  /// The media server restarted; every audio object is invalid.
  case servicesReset

  #if os(iOS)
  static func interruption(from userInfo: [AnyHashable: Any]?) -> AudioSessionEvent? {
    guard let raw = userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: raw) else { return nil }
    switch type {
    case .began:
      // The stale "app was suspended" reason is no longer sent since iOS 16,
      // so every began on this deployment target is a live interruption.
      return .interruptionBegan
    case .ended:
      let options = AVAudioSession.InterruptionOptions(
        rawValue: userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
      return .interruptionEnded(shouldResume: options.contains(.shouldResume))
    @unknown default:
      return nil
    }
  }

  /// Only device arrivals and departures. Category changes are ignored: the
  /// app causes those itself every time capture starts.
  static func routeChange(from userInfo: [AnyHashable: Any]?) -> AudioSessionEvent? {
    guard let raw = userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return nil }
    switch reason {
    case .newDeviceAvailable, .oldDeviceUnavailable:
      return .inputChanged
    default:
      return nil
    }
  }
  #endif
}
