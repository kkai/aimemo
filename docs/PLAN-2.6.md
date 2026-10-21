# ai-Memo 2.6 "A recorder you can trust": plan

Written 2026-10-21. Covers both SKUs: ai-Memo (6502860819) and ai-Memo Pro (6503480155).
Both have been on 2.5 since 2026-09-17.

**Status, 2026-10-22:** steps 0, 1, 3 and 4 are built and tested on this branch (`f3b109d`, `5b73810`, `d2815a3`, `8b5b2bf`). Steps 2 and 5 are next and start with the device spike. Nothing is pushed or uploaded.

## Why

2.5 made long recordings work: windowed decoding gives flat memory and live
text at any length. The app around that core still loses recordings in
ordinary situations, and the main reason to use it (meetings, lectures,
interviews) is exactly where it fails:

| Today | Where in the code |
|---|---|
| Locking the phone stops the recording | `Info.plist` / `Info.pro.plist` have no `UIBackgroundModes` |
| A phone call, Siri or an alarm silently ends capture; the UI keeps saying "Recording" | No `AVAudioSession.interruptionNotification` observer anywhere |
| Unplugging AirPods mid-recording stops the tap; the converter still expects the old input format | No `AVAudioEngineConfigurationChange` handling in `MicrophoneCapture` |
| There's no Pause button | `RealTimeWhisper.pause()/resume()` are built and tested, but nothing calls them |
| An Apple Speech recording that is paused and resumed loses everything said before the pause | `AppleSpeechTranscriptionSession.commitWhatWasHeard()` replaces the transcript, and `AppleSpeechRecognizer.startRecording()` clears `transcribedText`. The bug is hidden only because nothing can pause yet |
| No VoiceOver labels; 14 fixed `.system(size:)` fonts | `UI/`, `Views/RecordingView.swift` |
| There's no way to transcribe a file you already have | No `fileImporter`, no document types |

2.6 fixes the first six, then adds file import as the headline feature. Pro's
stored audio is 2.7 (see "Next").

## Scope

1. Recording keeps going with the screen locked.
2. Interruptions (calls, Siri, alarms, route changes) pause and resume cleanly.
3. Pause/Resume button, plus the Apple Speech pause fix.
4. Accessibility pass with an audit test target.
5. Transcribe an audio or video file, free on both SKUs. Pro also saves it to History.

Out of scope for 2.6:
- stored audio and playback
- SRT/VTT export
- App Intents, Live Activity, Control Center
- interface localization
- iCloud sync
- the whisper.cpp bump and large-v3-turbo
- chunked summaries

## Work, in order

Each step is a commit on `release-2.6`, with tests passing before the next step starts.

### 0. Apple Speech pause keeps earlier text

- `AppleSpeechTranscriptionSession` keeps the text committed before each pause.
- `commitWhatWasHeard()` appends the current run (`transcript.commit(heard)`, which already joins) instead of rebuilding `LiveTranscript()`.
- The mirror shows the committed text followed by the current run as provisional.
- Test: extend `FakeTranscriptionSession` or put a seam over `AppleSpeechRecognizer` (`transcribedText`, `startRecording`, `stopRecording`). Then: speak, pause, resume, speak, finish. Both parts must be in the result.

### 1. Interruptions and route changes

New `Models/Streaming/AudioSessionEvents.swift`:
- Observes `AVAudioSession.interruptionNotification`, `routeChangeNotification` and `mediaServicesWereResetNotification`.
- Publishes an `AsyncStream<AudioSessionEvent>` (`.interruptionBegan`, `.interruptionEnded(shouldResume:)`, `.inputLost`, `.servicesReset`).
- It is engine-agnostic, so Whisper and Apple Speech get the same behaviour.

New pure `InterruptionPolicy` (a `Sendable` struct, like `PauseDetector`):

| Event | State | Action |
|---|---|---|
| began | recording | pause, mark `pausedBySystem` |
| ended(shouldResume: true) | paused by system | resume |
| ended(shouldResume: false) | paused by system | stay paused; the pill reads "Paused by a call", Resume is offered |
| any | paused by the user | nothing (never auto-resume a user's pause) |
| input lost (route change: old device unavailable) | recording | restart capture on the new route: `pause()` then `resume()`, which commits the open window so the seam isn't glued |
| services reset | recording/paused | stop and save what's committed, with an error line |

- No special case for stale `.appWasSuspended` interruptions: iOS stopped sending that reason in 16, and the app targets 18.5.
- `RealTimeWhisper` consumes the stream alongside `session.updates` and applies the policy. It also gains `pauseReason: PauseReason?` (`.user`, `.interruption`).
- `MicrophoneCapture`: observe `AVAudioEngineConfigurationChange` and rebuild the converter on restart. `start()` already reads `inputFormat` fresh, so a pause/resume cycle covers it.
- Tests: an `InterruptionPolicy` table test, and `RealTimeWhisperStateTests` with a fake event stream (call during recording, call during a user pause, resume refused).

### 2. Background recording

- Add `UIBackgroundModes = [audio]` to both plists. The session is already `.playAndRecord`; keep it active for the whole recording.
- **Metal can't be used in the background.** `WhisperContext` uses the GPU on device (`use_gpu` is false only on the simulator), and iOS refuses GPU command buffers from a backgrounded app. The vendored 2024 ggml-metal may abort or return garbage rather than fail cleanly. The plan is to **defer decoding while backgrounded**:
  - `StreamingTranscriber.setDecodingSuspended(_:)`. While suspended, closed windows go into a FIFO instead of being decoded, stored as `Int16`: 115 MB per hour, against 230 MB as `Float`.
  - Capture, the window policy and the timer keep running.
  - On foreground, the queue is decoded in order, and the transcript card shows "Catching up…" with a count.
  - `stopRecord()` while backgrounded is possible from the Dynamic Island/Lock Screen in a later release; in 2.6 stop happens in the foreground, and `finish()` drains the queue first.
  - Safety cap: at 3 hours of queued audio, oldest-first eviction is **not** acceptable. Stop capture, pause, and say why.
  - Driven by `scenePhase` in `RecordingView`, which tells `RealTimeWhisper`, which tells the session.
- **Day-one spike on a device**, before building the above:
  1. Record with Whisper, lock for 2 minutes, unlock: does the decode crash, error or silently pass?
  2. Same with Apple Speech on-device: does recognition continue in the background? It should, since the audio mode keeps the engine running.
  3. Interruption ended in the background: does `setActive(true)` plus `engine.start()` succeed, or fail with `cannotStartRecording`?

  If (3) fails, the fallback is to stay paused and show "Paused by a call, tap to resume" on return. That is still much better than today.
- Alternative, rejected for 2.6: a second CPU-only `WhisperContext` for the background. It doubles model memory, and medium on CPU is slower than real time, which risks the background CPU watchdog. Revisit with `BGContinuedProcessingTask` (iOS 26) later.
- Tests: `StreamingTranscriberTests` for suspend/resume ordering, `finish()` draining a suspended queue, and Int16 round-trip accuracy within tolerance on the real fixtures.

### 3. Pause button and states

- `RecordingStatus` gains `.paused` (and `.catchingUp`, `.importing`). The pill reads "Paused", or "Paused by a call".
- The recording bar becomes Pause/Resume beside Stop, and is visible only while recording. The elapsed time freezes while paused (already correct in the model).
- Cancel, which exists in the model, stays hidden. It's not worth a confirmation dialog in 2.6.
- Haptic on pause and resume.

### 4. Accessibility

Same method as the puzzle family (`just-puzzles/shikaku/docs/ACCESSIBILITY.md`).

**Test target and scripted session:**
- New `aimemoUITests` target, added with the `xcodeproj` gem and then patched into the synchronized group, as in the puzzle apps (objectVersion 77).
- A DEBUG-only `ScriptedTranscriptionSession` in the app target, selected by the launch argument `-uiTestScriptedSession`. It plays a fixed transcript and levels, so recording screens can be audited without a microphone. The simulator mic is unreliable; see memory `aimemo-screenshot-capture`.

**Audits:** `performAccessibilityAudit()` on these screens:
- idle
- recording
- paused
- catching up
- importing
- Settings
- History and Detail (on the `aimemo-pro` scheme, which gets a test action)
- idle again at AX5

**Labels and announcements:**
- Header buttons: "Settings", "History".
- Record: "Start recording" / "Stop recording".
- Pause: "Pause" / "Resume".
- The waveform is hidden.
- The timer reads "Elapsed 1 minute 5 seconds".
- The language badge reads "Detected language: German".
- Copy/Share/Clear already have text.
- Announce state changes ("Recording", "Paused by a call", "Saved"), but never every transcript update. The transcript gets `.updatesFrequently`.

**Visuals:**
- Dynamic Type: replace the 14 fixed sizes with text styles. The title becomes `.largeTitle` in the serif design. The record button glyph uses `@ScaledMetric`.
- Contrast: compute every `Theme` pair, light and dark.
- Touch targets ≥ 44 pt.
- Reduce Motion: the record button's spring and pulse.

**Docs:** write `docs/ACCESSIBILITY.md` with the findings table and the Nutrition Label claims.

### 5. Transcribe a file

**Reader:** `Models/Import/AudioFileReader.swift`.
- `AVAssetReader` with `AVAssetReaderAudioMixOutput` set to 16 kHz mono Float32 LPCM, so one path handles m4a, mp3, wav, caf, aac, mov and mp4, and the asset does the resampling.
- Yields chunks of about 10 s, plus duration and progress.
- Errors: no audio track, DRM-protected, unreadable.

**Feeding the transcriber:**
- `StreamingTranscriber.feed(_:) async` is a back-pressured sibling of `ingest`. It awaits `handle` directly, so a one-hour file never sits in memory as floats.
- The same window policy applies, since pauses in recorded speech are pauses too.

**State and engines:**
- `RealTimeWhisper.transcribe(file:)` with state `.importing(progress:)`.
- It reuses `transcribedText`/`provisionalText`, the language pinning and the Pro save.
- **Whisper only.** If Apple Speech is the selected engine, import still uses the loaded Whisper model, and the sheet says so. `SFSpeechURLRecognitionRequest` is a later option.

**Entry points:**
- A "Transcribe a file" header button with `.fileImporter([.audio, .movie])` and security-scoped access.
- `CFBundleDocumentTypes` for `public.audio` and `public.movie` at `LSHandlerRank = Alternate`, handled by `.onOpenURL`. ai-Memo then appears in the share sheet of Files, Voice Memos and Mail.
- A share extension is not needed for 2.6; its memory limit wouldn't fit a Whisper model anyway.

**Behaviour:**
- Progress on the pill ("Transcribing 42%"), plus Cancel.
- The background rule from step 2 applies: decode pauses while backgrounded and resumes in the foreground.

**Pro:**
- `Recording` gets an optional `sourceFileName: String?`, which SwiftData's lightweight migration adds without a manual step.
- Duration is the file's duration, and the default title is the file name. The auto-title still runs if the name is generic (e.g. `New Recording 12.m4a`).
- Pro gains no other differences: import is free, to keep the funnel.

**Tests:**
- Reader against fixtures converted from the existing `aimemoTests/Resources/audio` WAVs: m4a (`afconvert`), mp3, a mov with an audio track, and a mov without one.
- Back-pressure: memory stays bounded with the fake transcriber.
- A gated end-to-end test: a real m4a through Whisper base gives the same text as the WAV path.

### 6. Version, listing, release

**Version and checks:**
- MARKETING_VERSION 2.6 on both app targets; CURRENT_PROJECT_VERSION stays 1, which is new for 2.6.
- Re-check the privacy manifest. It has no new required-reason APIs; file access through `fileImporter` doesn't need one.

**Listing and review:**
- What's New for each SKU in `appstore/aimemo*/whats-new.txt`, run through the humanizer.
- The description gains a file-import paragraph.
- Review notes justify background audio: "Recording continues with the screen locked. To test, start recording, lock the device, speak, then unlock: the transcript catches up."
- Screenshots: add an import screen. Recapture the recording screen with the Pause button.

**Site and docs:**
- Site (`tools/aimemo-site`, gh-pages worktree): add the file-import and lock-screen lines.
- Submission runbook `docs/SUBMISSION-2.6.md`, same shape as the puzzle ones.
- Close the items in the outer `ROADMAP.md`'s "Cross-cutting follow-ups" that this release completes.

## Verification

**Simulator (iPhone 16 Pro, iOS 18.5, `-parallel-testing-enabled NO`):**
- All existing 184 tests plus the new ones.
- UI audits on both schemes.
- Import of every fixture type through the UI.

**Device (needs your iPhone; none of this can be faked in the simulator):**
- [ ] The step-2 spike (Metal in the background, Apple Speech in the background, resume after a call).
- [ ] A 30-minute Whisper recording with the phone locked for 20 of it, then catch-up.
- [ ] A real incoming call during a recording, answered and then hung up. Same with a declined call. Same with Siri.
- [ ] AirPods connected and disconnected mid-recording.
- [ ] Import a Voice Memos recording via the share sheet, and a one-hour lecture m4a. Check memory in Instruments stays flat.
- [ ] VoiceOver: record, pause, resume, stop, copy, eyes closed.

## Risks

| Risk | Mitigation |
|---|---|
| ggml-metal in the vendored whisper.cpp crashes, not errors, on background submission | Suspension happens on `scenePhase == .background` *before* the next decode, plus the day-one spike. If it can't be made safe, fall back to "recording pauses when locked", which is still honest |
| App Review questions `UIBackgroundModes audio` for a recorder | Standard use. The review note explains how to test it |
| Background CPU from capture alone triggers the watchdog | Capture plus the window policy is light: no decode, no conversion beyond the tap |
| Apple Speech on server-based locales fails in the background | Detect the failure. Pause with "Apple Speech needs the app open for this language" |
| The queue grows on very long locked recordings | Int16 storage and a 3-hour cap with a clear stop |

## Next (2.7, Pro)

Store the audio with the transcript. The `Int16` queue from step 2 and the
reader from step 5 are both groundwork for it.
- AAC on save.
- Playback where tapping a word jumps there (segment timestamps already exist).
- Re-transcribe with a bigger model.
- SRT/VTT export.

After that, App Intents (Action Button, Control Center) plus a Live Activity
that can stop a locked recording.
