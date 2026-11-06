# ai-Memo 2.6: submission runbook

Staged 2026-11-07 for both SKUs. Everything below is done except the last step, the
outward-facing submit, which is a deliberate choice.

| | ai-Memo | ai-Memo Pro |
|---|---|---|
| App Store Connect id | 6502860819 | 6503480155 |
| Bundle id | `de.kaikunze.aimemo` | `de.kaikunze.aimemo-pro` |
| 2.6 version id | `ea98a042-bb01-4de1-9941-a4b8a7325f22` | `a0259d5e-ba9d-4f06-be76-5c3bc2f5908a` |
| en-US localization | `cc68a36c-922e-4d4a-a9ad-3c4bec8aca7b` | `b3b1cae8-675d-4925-a762-2b7cbfa3b28e` |
| Attached build | 2.6 (2), `4734d3a3-2066-49bf-aa1d-97e16c981a5a` | 2.6 (2), `e847b926-8ef1-43a0-9487-a1e67eb408dd` |
| Review submission (draft) | `36ab32c3-2186-4fb5-8d32-d32fa92238d7` | `213f0bca-1b0c-46b2-b2f7-efec83331cc2` |
| State | READY_FOR_REVIEW, not submitted | READY_FOR_REVIEW, not submitted |
| Release type | AFTER_APPROVAL | AFTER_APPROVAL |

Build 1 of each (uploaded a few minutes earlier) lacks `LSSupportsOpeningDocumentsInPlace`
and is not attached. Leave it; builds cannot be deleted, only expired.

## What shipped

Build 2 was archived from commit `2ac9757` on `main`; the tag `v2.6` sits on the runbook commit right after it. In it: file import, segment timings, Markdown/SRT/WebVTT
export, the summary card, the App Intents, pause/resume, interruption handling, the Apple
Speech restart, the awake screen and the "No sound" cue, accessibility. Background recording
(plan step 2) is **not** in 2.6; it needs the device Metal spike and moves to 2.7. The listing
does not claim it.

## Steps, as run

All from the repo root, credentials read from `studio/appstoreconnect/credentials.txt`
(line 2 issuer id, line 4 key id), key at `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`.

1. **Merge and bump.** `main` fast-forwarded to `feature/2.6-export-intents-import`;
   `MARKETING_VERSION = 2.6`, `CURRENT_PROJECT_VERSION = 2` in `project.pbxproj`.
2. **Archive**, one per scheme:
   ```bash
   xcodebuild -project aimemo.xcodeproj -scheme aimemo -configuration Release \
     -destination 'generic/platform=iOS' -archivePath build/aimemo-2.6-b2.xcarchive \
     -allowProvisioningUpdates archive
   ```
   `appintentsnltrainingprocessor` prints `error: Could not archive SSU artifacts` after
   copying the Siri phrase metadata; the archive still succeeds and the intents work.
3. **Upload** with `ExportOptions.plist` (`destination: upload`):
   ```bash
   xcodebuild -exportArchive -archivePath build/aimemo-2.6-b2.xcarchive \
     -exportOptionsPlist ExportOptions.plist -exportPath build/aimemo-2.6-b2-export \
     -allowProvisioningUpdates -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8 \
     -authenticationKeyID <KEY_ID> -authenticationKeyIssuerID <ISSUER_ID>
   ```
   Build 1 came back with the warning *Missing Document Configuration*: an app with
   `CFBundleDocumentTypes` must also set `LSSupportsOpeningDocumentsInPlace`. It is `false`
   in both plists since 2.6 (2), because `ImportedFile.stage` copies the file.
4. **Versions and copy** via `studio/appstoreconnect/asc.py`: `POST appStoreVersions`
   (2.6, IOS, AFTER_APPROVAL), `PATCH appStoreVersionLocalizations/{id}` with
   `appstore/<sku>/{whats-new,description,promo}.txt`, `PATCH appStoreReviewDetails/{id}`
   with `review-notes.txt`.
5. **Screenshots.** iPhone 11 Pro Max simulator `BCB6EC16-DCF7-4985-839A-A36B45E890F7`
   (iOS 18.5, 1242×2688), Debug builds, `simctl status_bar … override --time 9:41`, dark
   appearance. The recording and share-menu shots use `-uiTestScriptedSession`; the import
   shot uses `-uiTestImportFile <wav>` with a 73 s clip from `say -v Samantha … --data-format=LEI16@16000`
   and a frame every 0.5 s (base finishes 73 s in about 4 s on an M-series Mac); Pro's
   History shot adds `-uiTestSeedHistory` and lets the import save first. Language and
   Settings shots are the 2.5 ones. Uploaded with
   `AppShip screenshots --bundle-id … --create-version 2.6 --iphone-dir screenshots/<sku>-2.6/iphone --replace`
   (iPad sets carried over from 2.5). The iPad Pro 12.9 6th-gen simulator is on iOS 17 and
   cannot run the app, so iPad was not recaptured.
6. **Attach the build**: `PATCH appStoreVersions/{id}/relationships/build`.
7. **Readiness gate**: `POST reviewSubmissions` then `POST reviewSubmissionItems`. Both
   passed first time (no age-rating gaps, screenshots already COMPLETE).

## To submit

```bash
cd studio/appstoreconnect
python3 asc.py PATCH reviewSubmissions/36ab32c3-2186-4fb5-8d32-d32fa92238d7 \
  '{"data":{"type":"reviewSubmissions","id":"36ab32c3-2186-4fb5-8d32-d32fa92238d7","attributes":{"submitted":true}}}'
python3 asc.py PATCH reviewSubmissions/213f0bca-1b0c-46b2-b2f7-efec83331cc2 \
  '{"data":{"type":"reviewSubmissions","id":"213f0bca-1b0c-46b2-b2f7-efec83331cc2","attributes":{"submitted":true}}}'
```

Or press Submit on each app's page in App Store Connect.

## After approval

- Push `main` and the `v2.6` tag to `origin`.
- Push `gh-pages` from `tools/aimemo-site` (commit `3152421` holds the 2.6 landing copy).
- Device checks still owed: summary generation on an Apple Intelligence phone, "Open in
  ai-Memo" from Voice Memos, the Shortcuts actions, a call during a recording.
