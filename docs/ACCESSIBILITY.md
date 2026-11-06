# Accessibility audit: ai-Memo and ai-Memo Pro (iOS)

Audit and fixes on branch `release-2.6`, 2026-10-22. Before this, the app had no
accessibility work at all: no labels, fixed font sizes and no audit tests.

## Method

Same method as the Just Puzzles apps (`just-puzzles/shikaku/docs/ACCESSIBILITY.md`).

1. **Common tasks.** Record, pause, resume, stop, copy, share. Change the
   engine, model and language in Settings. Pro adds: open History, open a
   recording, copy it.
2. **Automated.** `aimemoUITests/AccessibilityAuditTests.swift` runs
   `performAccessibilityAudit()` (all audit types) once per screen. Each issue
   is printed as an `AUDIT |` line in the test log.
   - Recordings play a fixed script (`-uiTestScriptedSession`, DEBUG only),
     because the simulator microphone only works after a reboot.
   - Pro screens use an in-memory history with three recordings
     (`-uiTestSeedHistory`).
3. **Contrast.** WCAG ratios for every text/background pair in `UI/Theme.swift`,
   with opacity composited. The app is dark-only. Targets: 4.5:1 for body
   text, 3:1 for large text and non-text UI.
4. **Dynamic Type.** Screens checked at
   `accessibility-extra-extra-extra-large` (AX5).
5. **VoiceOver order and labels.** Read with
   `studio/idb-venv/bin/idb ui describe-all`.
6. **Code review** for Reduce Motion, colour-only state, touch targets and
   announcements.

### Running the audits

```bash
# Free app (the test target's host)
xcodebuild test -project aimemo.xcodeproj -scheme aimemo \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5' \
  -parallel-testing-enabled NO -only-testing:aimemoUITests

# Pro: build and install aimemo-pro on the same simulator first, then
TEST_RUNNER_AIMEMO_APP=pro xcodebuild test … (same arguments)
```

A test bundle installs only its host app, the free one, so the Pro run
launches the Pro app by bundle id and needs it installed beforehand. The
History tests skip without `AIMEMO_APP=pro`.

**Trap:** build Pro into the *default* DerivedData (`xcodebuild build -scheme
aimemo-pro`, no `-derivedDataPath`) before installing it. When it was built
elsewhere, the test run put back an older `aimemo-pro.app` from the default
products folder, and the Pro audits silently tested stale code. Check the
installed binary's timestamp with `simctl get_app_container` if Pro results look
like old code.

## Findings

Severity: 🔴 blocks a common task, 🟠 puts a feature claim at risk, 🟡
friction, 🟢 polish.

| # | Sev | Finding | Status |
|---|---|---|---|
| 1 | 🔴 | **Interruptions were invisible.** A call stopped the microphone while the screen still said "Recording", and nothing was spoken. | **Fixed** (2.6 step 1). The recording pauses. The label reads "Paused by a call or alarm", and it's announced. |
| 2 | 🔴 | **Errors were never shown or spoken.** `errorMessage` was set (microphone refused, input unavailable) but no view read it, so the record button did nothing. | **Fixed.** A line above the controls, with a red icon and full-contrast text. It's announced when set. |
| 3 | 🟠 | **Icon buttons read their symbol names.** Settings read as "gearshape", History as "clock.arrow.circlepath". | **Fixed.** "Settings", "History", "Start recording" / "Stop recording", "Pause" / "Resume". |
| 4 | 🟠 | **No state was announced.** Starting, pausing and stopping changed only the picture. | **Fixed.** Announced: "Recording", "Paused", "Paused by a call or alarm", "Recording resumed", "Stopped. The transcript is ready." The live transcript is *not* announced, because it changes every few seconds; it carries `.updatesFrequently` instead. |
| 5 | 🟠 | **Text didn't follow Dynamic Type.** 14 fixed `.system(size:)` fonts: title, subtitle, timer, language, status, transcript, the action buttons, the Pro card. | **Fixed.** Text styles throughout. The wordmark and the transcript card's height scale with `@ScaledMetric`. |
| 6 | 🟠 | **Contrast:** blue text on the Copy/Share buttons was 4.35:1. | **Fixed.** `Theme.accent` is `#3A88FF` (was `#2F80FF`): 4.68:1 on its button, 5.4:1 on a card. |
| 7 | 🟡 | **Touch targets under 44 pt:** the circle buttons (40), the transcript buttons (~42) and "Get ai-Memo Pro" (18 pt of text). | **Fixed.** All are at least 44 pt. The circle buttons grow with text size up to 64 pt (unbounded, they reached 120). |
| 8 | 🟡 | **The timer read as "00:65 dot English".** | **Fixed.** One element: "Elapsed 1 minute, 5 seconds, detected language English". |
| 9 | 🟡 | **The provisional tail was shown only by dimming.** | **Fixed.** The transcript's value says "The last words are still being transcribed" while there is a dimmed tail. |
| 10 | 🟡 | **Selection by colour or symbol only:** the engine and model rows marked the choice with a checkmark image. | **Fixed.** Rows carry `.isSelected`. The images are hidden. |
| 11 | 🟡 | **Copy gave no feedback** on the recording screen, seen or heard. | **Fixed.** "Transcript copied" is announced (on Detail too). |
| 12 | 🟡 | **The waveform was read** as a hundred unlabelled images. | **Fixed.** Hidden: it's a meter, and the status label carries the meaning. |
| 13 | 🟡 | **Reduce Motion:** the record button's glyph springs and scales, and Detail's "Copied" toast slides in. | **Fixed.** Both fade. |
| 14 | 🟡 | **History rows read as loose fragments**, and the duration badge said "2:05". | **Fixed.** One element per row. The duration reads "2 minutes, 5 seconds". Headings on Detail carry `.isHeader`. |
| 15 | 🟢 | **The subtitle had a hard line break**, so at large sizes it broke mid-phrase, and the audit reported it as clipped. | **Fixed.** It wraps by width. |
| 16 | 🟢 | **The Pro card sat above a live transcript**, pushing its buttons below the fold. | **Fixed.** It sits below the transcript and hides during a take. |
| 17 | 🟢 | **The waveform ran past the right margin** (a 2 pt bar floor × 100 bars). | **Fixed.** 1 pt floor. |
| 18 | 🟠 | **Pro's model picker:** the "Better" and "Best" badges were blue and purple text on a 20% tint of themselves (3.6–3.7:1). The descriptions and sizes used the app's grey on a Form row, which the audit flagged at caption size. | **Fixed.** Badge text is `textPrimary` on a 30% tint (10:1 or better). Descriptions and sizes use the system secondary colour, like the rest of Settings (5.9:1). |

### Contrast table (dark, composited)

| Pair | Ratio | Needs |
|---|---|---|
| textPrimary on background / card | 18.1 / 17.1 | 4.5 |
| textSecondary on background / card (subtitle, timer, provisional text) | 6.09 / 5.74 | 4.5 |
| accent on card | 5.40 | 4.5 |
| accent text on its 12% button | 4.68 | 4.5 |
| danger text on its 12% button | 4.81 | 4.5 |
| accent / danger text on its 14% status pill | 4.94 / 5.06 | 4.5 |
| white glyph on the record button (large graphic) | 3.55 | 3 |
| record button against background | 5.52 | 3 |

### Accepted, with reasons

- **The live recording tests excuse contrast and one unattributed
  "inaccessible text".** While the script plays, the timer ticks and the
  transcript grows between the audit's captures, and it reports whatever
  moved. `testPaused` audits the identical screen standing still and passes.
  The colours are in the table above.
- **System Form and List screens** (Settings, History): the audit reports
  Dynamic Type and clipping on standard rows, picker values and the nav-bar
  Done button. These are system components and scale at AX5. The two audit
  types are excused on those screens only.
- **The record button is a fixed 96 pt drawing.** It's already more than
  twice the minimum target, and its label is spoken.

## Result

`xcodebuild test` (iPhone 16 Pro, iOS 18.5, serial), 2026-10-22:
- **unit tests:** 206 pass;
- **free app audits:** 8 pass, and 2 (History, Detail) are skipped because
  they are Pro-only;
- **Pro app audits:** all 10 pass.

2026-11-06, same destination: 276 unit tests pass; 10 free audits pass and 2
skip. New screens: **importing** (`testImporting`, driven by
`-uiTestImportFile <path>`, with the same live-content tolerance as a running
take because the transcript grows under the audit, plus one more: the audit
sometimes reports "Hit area is too small" on the elapsed label while a file is
decoding, because the label's frame changes between its two captures when the
language badge appears; the label is static text, so this is accepted for
labels beginning with "Elapsed" under the same live-content flag) and the **Share menu**
(`testFinishedShareMenuOffersTextAndMarkdown`). New labels: "Transcribe a
file" (header), "Cancel transcription" (controls), "Share" with the hint
"Share as text, Markdown or subtitles", and the announcements "Transcribing
the file" / "File transcribed. The transcript is ready."

## Accessibility Nutrition Labels (for App Store Connect)

Claimable once 2.6 ships, on both SKUs:
- **VoiceOver:** yes. Record, pause, resume, stop, copy and share all work
  by label, and state changes are spoken. Pro: History and Detail too.
- **Voice Control:** yes. Every control has a visible or spoken name.
- **Larger Text:** yes.
- **Sufficient Contrast:** yes.
- **Dark Interface:** yes (the app is dark-only).
- **Reduced Motion:** yes.
- **Differentiate Without Color Alone:** yes. Status is text, selection is a
  trait, and the dimmed transcript tail has a spoken value.

Not applicable: Captions and Audio Descriptions (the app has no media of
its own).

**Not yet verified on a device:** an eyes-closed VoiceOver pass on an iPhone,
and the "Paused by a call or alarm" announcement during a real call. Both are
in `docs/PLAN-2.6.md` §Verification.
