<!-- ORIX Clean / File: RELEASE-REPORT.md / Author: Simon-Pierre Boucher / Contact: contact@spboucher.ai -->
# ORIX Clean 1.0.0 (1) — Release Report

Date: 2026-11-21. Build machine: MacBook Pro Mac17,6 (Apple M5 Max, 18 cores, 48 GB), macOS 27.0 (26A5425a), Xcode 27.2, Swift 6.4.2.

Everything below was observed on that machine. What was not observed is listed under "Not verified".

## 1. Summary

| Item | Value |
|---|---|
| Version / build | 1.0.0 / 1 |
| Bundle identifier | `ai.spboucher.orix.clean` |
| Minimum macOS | 15.0 |
| Architectures | arm64, x86_64 (universal) |
| Repository | Public since 2026-11-21, at the owner's request: https://git.spboucher.ai/orix-clean |
| Commit | see `git log -1` (the report is part of the release commit) |
| Developer ID signing | Valid — Developer ID Application: Simon-Pierre Boucher (3YM54G49SN), Hardened Runtime (`flags=0x10000(runtime)`), secure timestamp, empty entitlements, no `get-task-allow` |
| Notarization — app | **Accepted** — submission `c2e7cbaa-9410-466f-b912-b9666f5a02b7`, 0 issues in Apple's log, stapled and validated |
| Notarization — DMG | **Accepted** — submission `ff776146-c989-45d6-99de-c93bb217d8c1`, stapled and validated |
| Gatekeeper | `accepted`, `source=Notarized Developer ID` for the app, the DMG, and the app extracted from the ZIP |
| DMG | `ORIXClean-1.0.0.dmg`, 5,133,225 bytes, SHA-256 `c7a8b13f3db143e80d2902882d8fe069d68b6e89a1de212411dffdb7334bcd34` |
| ZIP | `ORIXClean-1.0.0.zip`, 4,032,161 bytes, SHA-256 `126a980dd974136fc958ff7ab9a9b735d68aa2cc162d2729fa4f7d55a03da9fd` |
| SPB Git release URL | https://git.spboucher.ai/orix-clean/releases — assets under https://git.spboucher.ai/releases/orix-clean/v1.0.0/ |
| Release tag | `v1.0.0` = `aad1fa5` (the commit the binaries were built from; later commits change documentation only) |

## 2. Implemented features

| Feature | State | Notes |
|---|---|---|
| Storage analysis engine | Implemented, tested | `getattrlistbulk`, logical / allocated / private sizes, hard links once, clones and sparse files flagged, boundaries, cancel, pause |
| Interactive storage map | Implemented | Squarified treemap in Canvas, drill-down, breadcrumb, pinch zoom, drag pan, hover, search, context actions, list equivalent. Sunburst not implemented |
| Large-file discovery | Implemented | Files and folders; size, age, type, name, package filters |
| Duplicate detection | Implemented, tested | Size → sampled hash → SHA-256 → byte verification before removal |
| Similar images | Implemented, tested on generated pictures | Difference hash + Vision feature prints, fast and thorough modes |
| Cache cleanup | Implemented, tested | 12 documented rules, exclusions for system and stateful caches |
| Developer cleanup | Implemented, tested | 23 documented rules + build folders next to their manifest; simulators, runtimes, Docker reported only |
| Downloads cleanup | Implemented, tested | Installers, disk images, archives, incomplete downloads |
| Trash analysis | Implemented, tested | Home and per-volume Trash; emptying with typed confirmation |
| Uninstall assistant | Implemented, tested | Signature facts, associated files by certainty |
| Leftover detection | Implemented, tested | Name-based inference, labelled as such |
| Cleanup preview | Implemented, tested (UI) | The only entry to removal |
| Safe deletion engine | Implemented, tested | Authorization, safety policy, revalidation, five outcomes, Put Back |
| Storage intelligence | Implemented, tested | Evidence-based rules |
| Storage history | Implemented, tested | Samples while the app runs; watched folders; cleanup log |
| ORIX Clean Actions | Implemented, tested | Four built-in workflows, editor, review rule enforced |
| Reports | Implemented, tested | Nine report types; PDF, CSV, JSON, Markdown |
| Localization | Implemented | English, Canadian French (684 strings); no plural variants |
| Automatic updates | **Not implemented** | Evaluated (Sparkle) and deferred: the product has no network code |
| Pause/resume of duplicate and image analyses | **Not implemented** | Cancel only |
| Permanent deletion outside the Trash | **Deliberately absent** | |

## 3. Verified functionality

- **Core tests:** 56 tests in 10 suites, all passing (`swift test`, about 8 s). Core line coverage 86.7 % (2,662 / 3,070).
- **UI tests:** 8 XCUITest scenarios, all passing, on a sample home folder stored on a disposable disk image. One scenario performs a real cleanup (preview → cancel → confirm → results → Put Back) and checks the filesystem at each step. See section 10 for the caveat on reruns.
- **Release build smoke test:** the signed Release application was launched on a sample folder, scanned it and rendered the map; no crash report was produced. The debug-only screenshot hooks are absent from the Release binary (checked with `strings`).
- **Repository hygiene:** `Scripts/check.sh` passes — author headers, no signing material, no credential pattern, no networking API and no privilege-escalation API in the product sources.

## 4. Storage accuracy

- Allocated total of a 31,259-object tree (`~/Library/Developer/Xcode`) equals `du -sk` exactly: 2,412,920,832 bytes.
- A test compares scanner totals with `stat` sums and with `du` on every run.
- Hard-linked files are counted once (test); APFS clones report private sizes under 100 KB for a 4 MB clone (test); a 200 MB sparse file reports under 1 MB allocated (test).

## 5. APFS limitations

- Private sizes are reported per file by APFS; a folder's private size is the sum of its files' and is therefore a lower bound of what removing the whole folder frees.
- Local snapshots are not enumerated. Space held by a snapshot is not returned until the snapshot expires.
- Purgeable space is shown as macOS reports it and is not attributed to files.
- Moving to the Trash frees nothing until the Trash is emptied. On a full test volume, moving to the Trash still succeeds (it is a rename) — tested.
- On filesystems that do not report sharing (the fallback path), recoverable space equals allocated size and the report says so. This path was exercised only through the API fallback, not on a real non-APFS volume.

## 6. Cleanup safety validation

| Property | Evidence |
|---|---|
| Nothing is removed without authorization | `nothingIsRemovedWithoutAuthorization`; UI scenario checks the file still exists after selection and after cancelling the preview |
| High-risk items need a separate acknowledgement | `highRiskNeedsExplicitAcknowledgement` |
| Protected paths are refused whatever asks | `protectedLocationsAreDenied` (39 paths, including volume Trash folders, temporary roots and credential dot-folders), engine test on a substitute home |
| Items changed since the scan are left alone | `revalidationSkipsVanishedReplacedAndChangedItems` |
| A duplicate is removed only if byte-identical to the kept copy | `duplicatesAreVerifiedAgainstTheKeptCopy` |
| A duplicate group is never emptied | `aGroupIsNeverEmptied` |
| No silent permanent deletion | `partialFailureIsReportedPerItem` (no-Trash volume → manual action), permanent mode refused outside the Trash category |
| Restore never overwrites | `restoreRefusesToOverwrite` |
| Workflows cannot remove without review | `validationForbidsRemovalWithoutReview`, `duplicateWorkflowKeepsOneCopyAndStopsWhenReviewIsDeclined`, UI scenario |
| Read-only and full volumes | `readOnlyVolumeFailsCleanlyAndFullVolumeStillTrashes` |

No destructive test touches real user data: temporary directories and test disk images only. One core test moves a temporary folder to the real user Trash and restores it immediately.

## 7. Performance benchmarks

Release build of `orix-bench`, warm file cache, internal APFS SSD.

| Measurement | Result |
|---|---|
| Scan `~/Library/Developer` (985,558 files, 699,525 folders, 8 threads) | 17.4 s, 96,757 objects/s, 105 CPU-s, 202 MB peak RSS |
| Scan `/Applications` (448,727 files, 64,278 folders) — 1 / 2 / 3 / 4 / 6 / 8 threads | 3.45 / 3.49 / 3.04 / 2.92 / 2.96 / 4.07 s; 3.4 / 6.8 / 8.9 / 11.2 / 16.7 / 23.4 CPU-s |
| Scan `/System/Library` (296,089 files, 159,923 folders) | 3.27 s; 68 unreadable folders reported |
| Treemap layout (467,907 nodes, 1600×1000) | 0.162 ms, 1,798 cells |
| Duplicate search on the sample folder | 685 MB hashed in 0.069 s (warm cache) |
| Similar images on the sample folder | 31 images in 0.21 s |
| Signed application bundle | 13 MB |

The default thread count (3; 1 in Low Power Mode or under thermal pressure) was chosen from the `/Applications` series. Application overhead while idle, cold-cache hashing throughput, cleanup latency on large selections and battery impact were **not** measured.

## 8. Supported Mac configurations

| Configuration | Status |
|---|---|
| macOS 27.0, Apple Silicon (M5 Max) | Built, tested, run |
| macOS 15 and 26 | Deployment target allows them; **never run** |
| Intel Macs | x86_64 slice is in the binary; **never run** |
| Non-APFS, network and large external volumes | Small APFS disk images only; **otherwise not tested** |

## 9. Publication and approvals

- The brief asked for a private repository by default. The source was first pushed to a private SSH-only location; on 2026-11-21 the owner asked for a public repository and a release, and both were done the same day.
- Release assets: `ORIXClean-1.0.0.dmg`, `ORIXClean-1.0.0.zip`, `SHA256SUMS.txt`, each with a `.sha256` sidecar.
- Verification after upload: the three files were downloaded from the public URLs; sizes and SHA-256 match `dist/`, `stapler validate` succeeds on the downloaded DMG and `spctl` answers `accepted, source=Notarized Developer ID`.
- README on the forge: the served page contains the 12 Mermaid blocks and every one of the 20 local images is served with HTTP 200. It was not inspected visually in a browser.
- Apple Developer web pages (developer.apple.com, App Store Connect) were not opened: signing and notarization used the Developer ID identity and the notarytool keychain profile already installed. No agreement was accepted and no credential was created or changed.
- Nothing is outstanding. The earlier private copy (`gitsrv:srv/git-private/orix-clean.git`) still exists and can be deleted.

## 10. Not verified

- README rendering in a real browser (checked from the served HTML only).
- Installation on a second, clean Mac. Gatekeeper was assessed with `spctl` on the build Mac only.
- VoiceOver with a real user, Voice Control, measured contrast ratios.
- French screens other than the storage map (strings are complete and checked for placeholders; layout was viewed on one screen).
- Full-disk scan of this Mac in the application (the engine was run on folders up to 1.7 million objects).
- Full Disk Access granted to ORIX Clean itself: the application was run without it; the protected-folder paths were exercised through permission-denied tests only.
- UI test stability: the 8 scenarios passed, but during development several runs failed or hung because another application's test window took focus on the same Mac. The last full run is recorded below.

Final UI runs on the released code: a full run passed 7 of 8 scenarios (the eighth failed with "Failed to activate application" while another application's UI tests were running on the same Mac); that scenario then passed when run alone. The previous full run, one commit earlier, passed 8 of 8 in a single run. The final signed and notarized binary was launched once from `dist/` and stayed up for five seconds without a crash report; the full scan smoke test was done on the Release build made before the last fixes.

## 11. Known limitations

See README, section 33. The main ones: one tested configuration; memory proportional to the number of objects; scan results not persisted; recoverable space is an estimate; associations and leftovers are inferences; root-owned items cannot be removed; history only while the app runs; similar-image thresholds calibrated on generated pictures; no plural forms in strings; no automatic updates; not sandboxed.

## 12. Remaining work

- Run on macOS 15, macOS 26 and an Intel Mac.
- Try the app on a real home folder with Full Disk Access and on a real photo collection.
- Plural-aware strings; background sampling; layered icon for macOS 26 and later.
