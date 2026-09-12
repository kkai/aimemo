# ai-Memo / ai-Memo Pro — Feature Brainstorm (v2.4 → next)

## Context

This document replaces the 2025-11-11 version, which predated `ROADMAP.md` and had
drifted (its revenue section proposed a subscription tier the roadmap has since
overruled, and it lists as "missing" several things that have shipped).

`ROADMAP.md` in the outer folder remains authoritative for committed priorities. This
file is the wider idea pool: it deliberately does **not** restate the roadmap, but
covers what it misses and re-sequences what it contains against what the code actually
does today.

**Where the app is (verified, v2.4, commit `44c8506`):** a single-screen offline
dictation pad. ~2,600 LOC, 20 source files. Whisper (4 bundled quantized multilingual
models) or Apple Speech. Pro adds a searchable text-only history plus the model picker —
that is the entire `PRO_VERSION` surface (5 guards, in `RecordingView.swift`,
`SettingsView.swift`, `RealTimeWhisper.swift:343`). No StoreKit, no widgets, no App
Intents, no file import, no iCloud, no stored audio, no analytics.

Three findings from this pass that neither planning doc records, and that reshape the
priority order:

1. **The free app ships ~780 MB of models it can never use.** `project.pbxproj:30-48`
   is a `PBXFileSystemSynchronizedRootGroup` excluding only `Info.plist`, so both targets
   bundle all four models — but `SettingsView.swift:47` hides the model picker behind
   `#if PRO_VERSION`, locking free users to `base` (57 MB).
2. **The live transcript stops being live, and memory is unbounded.**
   `RealTimeWhisper.swift:227-231` appends to `dataFloats` and re-transcribes *the entire
   accumulated buffer* on every accepted pass. Total CPU is **not** quadratic — the
   `canTranscribe` guard drops callbacks arriving mid-pass, so pass starts grow
   geometrically and work stays linear with a ~2.5x constant. What is unbounded is
   memory (~3.8 MB per recorded minute, ~230 MB peak at 30 minutes once the per-callback
   COW copy is counted) and the gap between UI updates, which *is* the pass duration:
   ~200 s at 10 minutes, ~600 s at 30. Every long-form feature is gated on fixing this.
3. **Zero accessibility modifiers and zero localization.** No `.accessibilityLabel`
   anywhere in `Views/` or `UI/`; no `.xcstrings`, no `.lproj`. The app transcribes ~99
   languages behind an English-only, screen-reader-hostile UI.

Scope: both SKUs, keeping the two-paid-SKU model and sharpening the split between
them. Ideas are ranked by ROI across the full effort range.

---

## Three structural unlocks

Most of the interesting ideas below depend on one of these. Doing them first turns a
dozen "hard" features into small ones.

| # | Unlock | Where | What it gates |
|---|--------|-------|---------------|
| **U1** | Chunked/incremental transcription — commit finished segments, keep a sliding window, stop re-transcribing history | `RealTimeWhisper.swift:227-231` | Long recordings, file import, background recording, battery, meetings |
| **U2** | Store the audio (m4a alongside the transcript) | `Recording.swift` + save path `RealTimeWhisper.swift:348` | Playback, re-transcription, audio export, trimming |
| **U3** | Turn timestamps on — `no_timestamps=false`, `single_segment=false`, plus `token_timestamps` / `max_len` / `split_on_word` | `LibWhisper.swift:38-47` | SRT/VTT export, synced highlighting, chapters, jump-to-word |

Note on U3: `ROADMAP.md` Phase 2 says synced playback can use "the segment timestamps
whisper already emits" — it currently emits none. They are explicitly disabled. The
vendored `whisper.h` does expose all the flags (`:492-496`), so it is a config change,
but it changes the streaming shape and needs the `RealTimeWhisper` state tests the
roadmap already calls for.

---

## Tier S — near-free wins (hours to a day each)

Ordered by value. Every one of these is small enough to batch into a single release.

**S0. Drop the unused models from the free target.** ~810 MB → ~80 MB download for the
top-of-funnel app. Add `Resources/models/ggml-tiny-q5_1.bin`, `ggml-small-q5_1.bin`,
`ggml-medium-q5_0.bin` to the free target's `membershipExceptions` in
`project.pbxproj:30-38`. Does not violate the "works out of the box" principle — free
never exposed those models. Biggest single conversion lever here, and it costs a
pbxproj edit.

**S1. Translate-to-English toggle.** `params.translate` (`LibWhisper.swift:42`) is
hardcoded `false`. Flipping it gives any-language → English transcription, free, using
the models already bundled. One boolean, one settings row, and a genuine App Store
headline: *"Record in any language. Get English text."*

**S2. Show the detected language.** `WhisperContext.detectedLanguage()` exists and is
never called from anywhere. Badge it on the recording screen and persist it on
`Recording`. The multilingual capability is currently invisible to users.

**S3. Language override picker.** Already scoped in `ROADMAP.md` Phase 1 and deferred.
`params.language` is already a `strdup`'d string, so this is a picker seeded from
`Locale.current` feeding one value. Fixes auto-detect misfiring on short clips.

**S4. Fix Apple Speech's hardcoded locale.** `AppleSpeechRecognizer.swift` constructs
`SFSpeechRecognizer(locale: Locale(identifier: "en-US"))`; `setLanguage(_:)` and
`availableLanguages()` exist but are never called. The App Store copy advertises
multi-language for this engine. Wire S3's picker to it.

**S5. Custom vocabulary via `initial_prompt`.** `whisper.h:512` exposes it.
A settings text field of names/jargon/acronyms, passed through on each call.
`feature_suggestions.md` rates this "High complexity (14-21 days)" — it is roughly
20 lines. Real accuracy win for technical, medical and name-heavy dictation.

**S6. ASO keyword fix.** `appstore/aimemo/keywords.txt` leads with **"text to speech"** —
the opposite of what the app does — burning the most valuable slot in a 100-char field.
Replace with speech-to-text / transcribe / dictation / voice to text / offline.

**S7. Ship the dead share sheet.** `RecordingsListView` declares `showingShareSheet`
and `shareItems` and presents a `ShareSheet`, but nothing ever sets them. Also add share
from the live recording screen (`ROADMAP.md` Phase 2 asks for this).

**S8. Ask for App Store reviews.** No `requestReview` anywhere. Trigger after the Nth
successful save. Free ratings lift on an app with no other growth instrumentation.

**S9. Landscape and iPad multitasking.** Both plists are portrait-only with
`UIRequiresFullScreen = true`, which contradicts the `NavigationSplitView` iPad design
and blocks Slide Over / Stage Manager. (Build settings already declare landscape keys,
but `GENERATE_INFOPLIST_FILE = NO` means the explicit plists win.)

**S10. `PrivacyInfo.xcprivacy`.** Absent. Required-reason API manifest, and a
privacy-first app should be showing the strongest possible nutrition label.

**S11. Strip stale strings.** `TranscriptionEngine.swift:55` still returns
*"English only (current models)"* months after the multilingual refresh. Also delete the
dead `Secrets.xcconfig.template` AdMob keys and `REGISTER_APP_GROUPS = YES`.

---

## Tier A — differentiators (days to ~2 weeks each)

**A1. Transcribe imported audio and video files.** ★ Highest-ROI differentiator.
Share extension + Files import + Open-In, with `AVAssetReader` pulling the audio track
out of mp4/mov. This converts the product from "a recorder" into "a transcription tool",
which is what people actually search the App Store for — *transcribe audio file*,
*mp3 to text*, *video to text*. Currently impossible: there are no document types, no
extension target, and no import path at all. **Needs U1** to be practical on a
90-minute file.

**A2. SRT / WebVTT / timestamped-Markdown export.** Needs U3. Pairs directly with A1:
drop in a video, get subtitles, entirely offline. Podcasters and YouTubers are an
underserved segment and nothing offline serves them well.

**A3. Foundation Models structured extraction.** The FM plumbing in
`SummaryGenerator.swift` is proven for summary + title, so extending it is close to
free: `@Generable` structs for action items, decisions, key points and participants;
"rewrite as email / meeting minutes"; transcript cleanup (remove filler, fix
punctuation). **Watch out:** there is no chunking today, so long transcripts will blow
FM's context window — a map-reduce pass is the real work here.

**A4. Live Activity / Dynamic Island + Control Center control + Action Button.** All
greenfield (no widget or extension target exists). Turns "start a memo" into one press
from anywhere, and makes recording state visible when the app is backgrounded.

**A5. App Intents / Shortcuts / Siri.** "Take a memo", "Transcribe this file",
"Summarize my last memo". Also exposes transcripts to Apple Intelligence and Spotlight
actions. Listed in `feature_suggestions.md`; still zero implementation.

**A6. Background recording.** `UIBackgroundModes` is absent from both plists, so
recording dies the moment you leave the app — a dealbreaker for lectures and meetings,
which is the exact use case the App Store copy sells. Plist + audio-session work,
entangled with U1.

---

## Tier B — depth for existing users

Mostly the roadmap's own Phase 2/3, re-ordered by what unblocks what, plus three items
it does not cover.

- **B1. Stored audio + synced playback** with transcript highlighting and speed control (U2 + U3).
- **B2. Pause/resume** — roadmap-correct approach: orchestrator state tests *first*.
- **B3. Editable transcripts** — `RecordingDetailView.swift:47` renders a read-only `Text`.
- **B4. Tags, favorites, `#Predicate` search — and Spotlight indexing.** Search today is
  an in-memory `contains` over every fetched row (`RecordingsViewModel.swift:19-41`).
  `CSSearchableItem` indexing so transcripts surface in system search is in neither doc
  and is a strong, cheap Pro hook.
- **B5. iCloud sync** — roadmap's headline Pro differentiator. No CloudKit entitlement today.
- **B6. Re-transcribe with a larger model** (U2) — turns the Pro model picker from a
  setting into an actual workflow.
- **B7. Richer export** — Markdown, PDF, batch, and auto-export to a Files/iCloud Drive
  folder (the Obsidian/plain-text-notes crowd).
- **B8. Accessibility pass + a "Live Captions" mode.** Zero accessibility modifiers
  exist. Beyond fixing that: a large-text, hand-the-phone-over conversation mode is a
  distinct product mode, a real market (hard-of-hearing users), and an App Store feature
  story — an offline transcription app is unusually well-placed to serve it.
- **B9. Localize the UI and the store listings.** No `.xcstrings`, no `.lproj`. An app
  that transcribes 99 languages with an English-only interface. Localized DE/ES/FR/JA/PT
  listings are the cheapest discovery lever available and compound with S1-S4.

---

## Tier C — big bets

- **C1. Offline dictation keyboard extension.** The "replace iOS dictation, fully
  offline" play from `topwhisper/PDR.md` §5.2. Nothing on the App Store does offline
  Whisper dictation into arbitrary apps. **Risk:** keyboard extensions run under a hard
  memory cap (~60 MB); `tiny-q5_1` is 31 MB, so it is plausible but tight — do a
  memory-footprint spike before committing.
- **C2. Speaker diarization.** Genuinely hard. A cheap approximation: pause-based turn
  breaks using `PauseDetector.swift`, which is already written and unit-tested but never
  instantiated in the app.
- **C3. `large-v3-turbo`.** Blocked as the roadmap says — the vendored whisper.cpp is
  pre-turbo (flat layout, `GGML_USE_CUBLAS`) and needs a bump to ≥ v1.7.1 plus a Metal
  rebuild. Also unblocks C1 by way of better small-model options.
- **C4. Mac app.** Build settings already claim `macosx`; `RealTimeWhisper` has a macOS
  stub that prints a placeholder. A menu-bar dictation app with a global hotkey is the
  `PDR.md` vision and the natural home for C1's engine.
- **C5. Apple Watch capture** → hand off to the phone for transcription.

---

## Sharpening the free/Pro split

Pro is currently "history + model picker". That is thin for a paid-to-paid upsell, and
the free app is simultaneously too heavy (S0) and too weak to earn ratings.

**Make free genuinely good** (drives ratings, word of mouth, and the upsell):
S0-S4 language work, S7 share, S8 review prompt, A4 Live Activity, S5 custom vocabulary.

**Make Pro clearly worth it:** A1 file import, A2 subtitle export, B1 playback,
B4 organization + Spotlight, B5 sync, A3 AI extraction beyond the basic summary,
and eventually C1.

Both fit the existing `PRO_VERSION` flag boundary, so no structural change to the
two-SKU model.

---

## Suggested slate

| Release | Theme | Contents |
|---|---|---|
| **2.5** | *Multilingual, for real* | S0-S11 — one batch of small, independent wins |
| **2.6** | *Capture you can trust* | U1 + orchestrator tests, A6 background, B2 pause/resume, U2 stored audio, B1 playback |
| **2.7** | *From recorder to transcription tool* | U3 timestamps, A1 import, A2 SRT/VTT, A5 App Intents |
| **3.0** | *Dictate anywhere* | C1 spike → keyboard, A4 surfaces, C4 Mac |

B9 localization should land alongside 2.5 (it is store-listing work more than code) and
B8 accessibility alongside 2.6.

---

## Verification

Per `AGENTS.md` / `CLAUDE.md`, from `aimemo/` (the git root):

```bash
# Both targets must build — the PRO_VERSION flag is the only thing separating them
xcodebuild -project aimemo.xcodeproj -scheme aimemo \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5' build
xcodebuild -project aimemo.xcodeproj -scheme aimemo-pro \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5' build

# Tests — pin OS=18.5, unpinned picks the newest installed runtime
xcodebuild test -project aimemo.xcodeproj -scheme aimemo \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5'
```

Feature-specific checks:

- **S0 (app size):** archive the free target and compare against
  `build/aimemo-2.4.xcarchive`; confirm the three excluded `.bin` files are absent from
  `Products/Applications/aimemo.app/Resources/models/` and that free-app transcription
  still works (it must fall back to `base`). Also confirm Pro still ships all four.
- **S1-S5 (language):** extend the existing multilingual integration test — the suite
  already transcribes en/de/es/fr/it/ja fixtures in `aimemoTests/`. Add a `translate`
  case asserting a non-English fixture yields English, and an `initial_prompt` case
  asserting a seeded proper noun is spelled correctly.
- **U1:** needs the `RealTimeWhisper` start→pause→resume→stop state tests the roadmap
  already calls for. Measure peak memory and wall-clock on a 30-minute recording before
  and after.
- **On device, not simulator:** anything touching Metal (the simulator uses the CPU
  fallback) and anything touching Foundation Models — `ROADMAP.md` flags that the FM
  positive path has *never* run, since simulators report the model unavailable.

---

*Revised 2026-09-11 against v2.4 (`44c8506`). Supersedes the 2025-11-11 v1.0.*
