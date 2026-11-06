//
//  RecorderIntentBridge.swift
//  aimemo
//
//  How App Intents reach the recorder the app is running
//

import Foundation

/// The recorder lives in `aimemoApp`'s state; intents run in the same
/// process but have no view hierarchy. The app registers its recorder here at
/// launch, and intents leave a request that the recording screen carries out
/// once the scene is active, because audio can only start in the foreground.
@MainActor
@Observable
final class RecorderIntentBridge {
  static let shared = RecorderIntentBridge()

  enum Request: Equatable {
    case startRecording
    case transcribe(ImportedFile)
  }

  @ObservationIgnored weak var recorder: RealTimeWhisper?
  /// Set by an intent, consumed by `RecordingView`.
  private(set) var pending: Request?

  func request(_ request: Request) {
    pending = request
  }

  /// Hands the request to the caller and clears it, so a scene activation
  /// later cannot replay it.
  func take() -> Request? {
    defer { pending = nil }
    return pending
  }
}
