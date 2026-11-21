<!-- ORIX Clean / File: docs/release/checklist.md / Author: Simon-Pierre Boucher / Contact: contact@spboucher.ai -->
# Release checklist

Quality gates for a release of ORIX Clean. Copy this list for each release and tick the boxes as each gate is
actually passed, with the evidence (command output, submission id, checksum) kept next to it. All boxes are
unchecked here on purpose: this file is the template, not a record.

Release: `____________`  Version / build: `______ (____)`  Date: `____________`  Machine: `____________`

## 1. Source state

- [ ] Working tree is clean and committed; the commit to release is identified.
- [ ] `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` are set for this release.
- [ ] `Scripts/check.sh` prints `clean`: author headers present, no signing material, no credentials, no
      network code, no privilege-escalation or private-API markers.
- [ ] `App/ORIXClean.entitlements` is still an empty dictionary.
- [ ] `ENABLE_APP_SANDBOX: NO`, `ENABLE_HARDENED_RUNTIME: YES` and the macOS 15.0 deployment target are
      unchanged in `project.yml`, or the change is intended and documented.

## 2. Localization

- [ ] `python3 Scripts/localize.py` succeeds: no `MISSING` key and no `PLACEHOLDERS DIFFER` line.
- [ ] Every new string was reviewed in French (fr-CA), including the five privacy usage descriptions.
- [ ] The application was launched once in French and once in English and the main sections were looked at
      for truncation.

## 3. Tests

- [ ] `Scripts/build.sh core-test`: all core tests pass. Number of tests executed: `____`.
- [ ] `Scripts/build.sh debug`: `** BUILD SUCCEEDED **` with no new warnings.
- [ ] `Scripts/build.sh uitest` on an otherwise idle machine: all 8 scenarios pass.
- [ ] Any UI test failure was rerun alone (`ORIX_ONLY=<name>`) and explained (focus theft or real regression).
- [ ] `/tmp/orix-uitest` is detached and `/tmp/orix-uitest.dmg` is gone after the run.

## 4. Safety review

- [ ] No change weakens `SafetyPolicy`; any new rule has a test in `SafetyPolicyTests`.
- [ ] `CleanupAuthorization` is still created in exactly one place in Release code (`AppModel.confirm`).
- [ ] Every new catalogue rule has a reason, a consequence and a regeneration note (`everyRuleIsDocumented`).
- [ ] No list preselects items; permanent deletion is still limited to Trash items and requires typing
      `DELETE`.
- [ ] Manual pass on the sample folder (`orix-bench fixture` in `/tmp`): select, preview, cancel, confirm,
      Put Back, and one workflow with the review declined.
- [ ] Manual pass with Full Disk Access off, then on: unreadable folders are reported, the Trash banner
      appears and disappears, nothing crashes.

## 5. Performance and accuracy

- [ ] `orix-bench scan` on a large folder: the allocated total equals `du -sk` on a tree that is not changing.
- [ ] Scan throughput and memory per object are in line with `docs/development/performance.md`; any
      regression is explained.
- [ ] If numbers in the documentation were updated, they are measurements with their environment stated.

## 6. Accessibility

- [ ] Full keyboard pass: every section reachable, cleanup preview operable, shortcuts work.
- [ ] VoiceOver pass over the sidebar, the list beside the storage map, a candidate list and the cleanup
      preview. Result recorded honestly in `docs/ACCESSIBILITY.md`.
- [ ] Light and dark appearance, both map palettes, Reduce Motion and Increase Contrast looked at.

## 7. Build and signing

- [ ] `Scripts/sign.sh` ends with `RESULT: … is built and signed`.
- [ ] `codesign --verify --deep --strict --verbose=2 "dist/ORIX Clean.app"` succeeds.
- [ ] `codesign -dvv` shows the expected `Developer ID Application` authority, team identifier and a timestamp.
- [ ] Flags include `runtime`; entitlements are empty; no `get-task-allow`.
- [ ] `lipo -archs` lists both `arm64` and `x86_64`.
- [ ] Bundle identifier is `ai.spboucher.orix.clean`; version and build match section 1.

## 8. Notarization

- [ ] `Scripts/notarize.sh` ends with `RESULT: dist/ORIX Clean.app is notarized by Apple (submission …) and
      stapled.` Submission id: `____________`.
- [ ] `Scripts/package.sh` built the DMG with artwork (no "falling back to a plain image" message) and the ZIP.
- [ ] `Scripts/notarize.sh dist/ORIXClean-<version>.dmg dmg` ends with the notarized-and-stapled result.
      Submission id: `____________`.
- [ ] `xcrun notarytool info <id>` reports `Accepted` for both submissions.
- [ ] `package.sh` was **not** run again after the DMG was notarized.

## 9. Final verification

- [ ] `Scripts/finalize.sh` completes: Gatekeeper accepts the application, the image and the application
      extracted from the ZIP; `stapler validate` succeeds on all three.
- [ ] `dist/SHA256SUMS.txt` and `dist/release.json` exist; version, build, minimum macOS and architectures in
      `release.json` are correct and both submission ids are non-empty.
- [ ] On a second Mac that never saw the build: download, verify the checksum, open the image, install,
      launch. The first-launch dialog is the standard one for a notarized application.
- [ ] On that Mac: onboarding appears, a scan of a folder completes, one item is moved to the Trash and put
      back.
- [ ] Intel Mac and macOS 15 / 26 smoke test done, or the release notes state that they were not run.

## 10. Documentation

- [ ] `docs/release/RELEASE_NOTES.md` describes this version and its known limitations.
- [ ] `README.md` and `RELEASE-REPORT.md` are updated by their owner.
- [ ] `docs/PRIVACY.md` still matches what the application reads and stores.
- [ ] Capability matrix and architecture documents updated for any behaviour that changed.
- [ ] No document claims a signature, notarization, measurement or test result that was not obtained for this
      release.

## 11. Publication

- [ ] Artifacts uploaded: DMG, ZIP, `SHA256SUMS.txt`.
- [ ] The published checksums equal those in `dist/SHA256SUMS.txt`.
- [ ] The download was fetched back from its public location and verified once more with `shasum` and `spctl`.
- [ ] The release commit is tagged.
- [ ] No credential, keychain profile content or private path appears in anything published.

## 12. After release

- [ ] `build/notary/*.json` and the notary logs are archived with the release evidence.
- [ ] Follow-up issues opened for every gate that was passed with a stated exception.
