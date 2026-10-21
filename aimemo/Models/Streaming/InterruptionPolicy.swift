//
//  InterruptionPolicy.swift
//  aimemo
//
//  What the recorder does when the system interrupts it
//

import Foundation

/// Why a recording is paused. Only a pause the system caused may be undone
/// by the system; a pause the user chose is never resumed behind their back.
enum PauseReason: Equatable, Sendable {
  case user
  case interruption
}

/// Pure decision table, so every case is tested without audio hardware.
///
/// Before this, nothing listened: a phone call stopped the tap silently and
/// the screen went on saying "Recording" over a dead microphone.
struct InterruptionPolicy: Sendable {

  enum Action: Equatable, Sendable {
    case ignore
    /// Pause and mark the pause as the system's.
    case pause
    case resume
    /// Stop and restart capture on the new input. The open window is
    /// committed first, so audio either side of the switch is not glued.
    case restartCapture
    /// Save what was transcribed and stop; the audio objects are gone.
    case stop
  }

  static func action(for event: AudioSessionEvent,
                     state: RealTimeWhisper.State,
                     pauseReason: PauseReason?) -> Action {
    switch event {
    case .interruptionBegan:
      return state == .recording ? .pause : .ignore

    case .interruptionEnded(let shouldResume):
      guard state == .paused, pauseReason == .interruption, shouldResume else { return .ignore }
      return .resume

    case .inputChanged:
      // A paused recording picks up the new input when it resumes anyway.
      return state == .recording ? .restartCapture : .ignore

    case .servicesReset:
      return state == .recording || state == .paused ? .stop : .ignore
    }
  }
}
