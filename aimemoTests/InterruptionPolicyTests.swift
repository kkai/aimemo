//
//  InterruptionPolicyTests.swift
//  aimemoTests
//
//  The decision table for calls, Siri, alarms and route changes, and the
//  recorder carrying it out against a fake session.
//

import AVFoundation
import Foundation
import Testing
@testable import aimemo

struct InterruptionPolicyTests {

  private func action(_ event: AudioSessionEvent, _ state: RealTimeWhisper.State,
                      _ reason: PauseReason? = nil) -> InterruptionPolicy.Action {
    InterruptionPolicy.action(for: event, state: state, pauseReason: reason)
  }

  @Test func aCallPausesARecording() {
    #expect(action(.interruptionBegan, .recording) == .pause)
  }

  @Test func aCallWhileIdleOrPausedChangesNothing() {
    #expect(action(.interruptionBegan, .idle) == .ignore)
    #expect(action(.interruptionBegan, .paused, .user) == .ignore)
    #expect(action(.interruptionBegan, .stopping) == .ignore)
  }

  @Test func theEndOfACallResumesWhatTheCallPaused() {
    #expect(action(.interruptionEnded(shouldResume: true), .paused, .interruption) == .resume)
  }

  @Test func withoutShouldResumeTheRecordingStaysPaused() {
    #expect(action(.interruptionEnded(shouldResume: false), .paused, .interruption) == .ignore)
  }

  @Test func aUsersPauseIsNeverResumedByTheSystem() {
    #expect(action(.interruptionEnded(shouldResume: true), .paused, .user) == .ignore)
  }

  @Test func aNewInputRestartsCaptureOnlyWhileRecording() {
    #expect(action(.inputChanged, .recording) == .restartCapture)
    #expect(action(.inputChanged, .paused, .user) == .ignore)
    #expect(action(.inputChanged, .idle) == .ignore)
  }

  @Test func aServicesResetStopsAndSaves() {
    #expect(action(.servicesReset, .recording) == .stop)
    #expect(action(.servicesReset, .paused, .interruption) == .stop)
    #expect(action(.servicesReset, .idle) == .ignore)
  }

  // MARK: - Parsing AVAudioSession's userInfo

  @Test func parsesABeganInterruption() {
    let info: [AnyHashable: Any] = [
      AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue,
    ]
    #expect(AudioSessionEvent.interruption(from: info) == .interruptionBegan)
  }

  @Test func parsesAnEndedInterruptionWithAndWithoutResume() {
    let resume: [AnyHashable: Any] = [
      AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
      AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue,
    ]
    let noResume: [AnyHashable: Any] = [
      AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
    ]
    #expect(AudioSessionEvent.interruption(from: resume) == .interruptionEnded(shouldResume: true))
    #expect(AudioSessionEvent.interruption(from: noResume) == .interruptionEnded(shouldResume: false))
  }

  @Test func onlyDeviceChangesCountAsRouteChanges() {
    func event(_ reason: AVAudioSession.RouteChangeReason) -> AudioSessionEvent? {
      AudioSessionEvent.routeChange(from: [AVAudioSessionRouteChangeReasonKey: reason.rawValue])
    }
    #expect(event(.newDeviceAvailable) == .inputChanged)
    #expect(event(.oldDeviceUnavailable) == .inputChanged)
    #expect(event(.categoryChange) == nil, "the app changes the category itself on every start")
    #expect(event(.override) == nil)
  }

  @Test func garbageUserInfoIsIgnored() {
    #expect(AudioSessionEvent.interruption(from: nil) == nil)
    #expect(AudioSessionEvent.routeChange(from: ["x": 1]) == nil)
  }
}

/// The recorder applying the policy. Events are delivered by calling
/// `handle(_:)` directly, which is what the live stream's consumer does.
@MainActor
@Suite(.serialized)
struct RecorderInterruptionTests {

  private func makeRecorder(_ session: FakeTranscriptionSession) -> RealTimeWhisper {
    RealTimeWhisper(makeSession: { _, _, _ in session }, sessionEvents: AsyncStream { _ in })
  }

  @Test func aCallPausesAndItsEndResumes() async {
    let session = FakeTranscriptionSession()
    let recorder = makeRecorder(session)
    await recorder.start()

    await recorder.handle(.interruptionBegan)
    #expect(recorder.state == .paused)
    #expect(recorder.pauseReason == .interruption)
    #expect(session.pauseCount == 1)

    await recorder.handle(.interruptionEnded(shouldResume: true))
    #expect(recorder.state == .recording)
    #expect(recorder.pauseReason == nil)
    #expect(session.resumeCount == 1)
  }

  @Test func aCallDuringAUserPauseLeavesItAlone() async {
    let session = FakeTranscriptionSession()
    let recorder = makeRecorder(session)
    await recorder.start()
    await recorder.pause()

    await recorder.handle(.interruptionBegan)
    await recorder.handle(.interruptionEnded(shouldResume: true))
    #expect(recorder.state == .paused)
    #expect(recorder.pauseReason == .user)
    #expect(session.resumeCount == 0)
  }

  @Test func theUserCanResumeAfterACallEndsWithoutShouldResume() async {
    let session = FakeTranscriptionSession()
    let recorder = makeRecorder(session)
    await recorder.start()
    await recorder.handle(.interruptionBegan)
    await recorder.handle(.interruptionEnded(shouldResume: false))
    #expect(recorder.state == .paused)

    await recorder.resume()
    #expect(recorder.state == .recording)
    #expect(recorder.pauseReason == nil)
  }

  @Test func aRefusedResumeStaysPausedWithAMessage() async {
    let session = FakeTranscriptionSession()
    let recorder = makeRecorder(session)
    await recorder.start()
    await recorder.handle(.interruptionBegan)
    session.resumeError = FakeTranscriptionSession.FakeError.cannotStart

    await recorder.handle(.interruptionEnded(shouldResume: true))
    #expect(recorder.state == .paused)
    #expect(recorder.errorMessage != nil)
  }

  @Test func aNewInputRestartsCaptureWithoutAVisiblePause() async {
    let session = FakeTranscriptionSession()
    let recorder = makeRecorder(session)
    await recorder.start()

    await recorder.handle(.inputChanged)
    #expect(recorder.state == .recording)
    #expect(session.pauseCount == 1)
    #expect(session.resumeCount == 1)
  }

  @Test func aFailedRestartHoldsTheRecordingPaused() async {
    let session = FakeTranscriptionSession()
    let recorder = makeRecorder(session)
    await recorder.start()
    session.resumeError = FakeTranscriptionSession.FakeError.cannotStart

    await recorder.handle(.inputChanged)
    #expect(recorder.state == .paused)
    #expect(recorder.pauseReason == .interruption)
    #expect(recorder.canStop)
  }

  @Test func aServicesResetStopsAndKeepsTheText() async {
    let session = FakeTranscriptionSession(finalText: "kept")
    let recorder = makeRecorder(session)
    await recorder.start()

    await recorder.handle(.servicesReset)
    #expect(recorder.state == .idle)
    #expect(recorder.transcribedText == "kept")
    #expect(recorder.errorMessage != nil)
  }
}
