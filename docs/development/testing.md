<!-- ORIX Clean / File: docs/development/testing.md / Author: Simon-Pierre Boucher / Contact: contact@spboucher.ai -->
# Testing

Two layers: Swift Testing suites for the core package, and XCUITest scenarios that drive the built application
on a disposable disk image. This document lists what each test proves, as read from the test sources.

## Running

```sh
Scripts/build.sh core-test                       # swift test in Packages/ORIXCleanCore
Scripts/build.sh uitest                          # all UI scenarios on a fresh disk image
ORIX_ONLY=testReportExportWritesAFile Scripts/build.sh uitest   # a single UI scenario
```

## The safety rule

**Destructive tests run only on temporary directories and disk images.** No test removes, moves or modifies a
file in a real user folder.

- Core tests create a `Sandbox`: a new directory `orixclean-tests-<label>-<id>` under `NSTemporaryDirectory()`.
- Tests that need another volume create a `TestVolume`: an APFS disk image made with `hdiutil`, attached at a
  mount point inside the temporary directory, detached and deleted when the object is released.
- Most deletion tests inject a `FakeTrasher`, which moves items into a `bin` folder inside the sandbox instead
  of the user's Trash and can be told to fail for chosen paths.
- Two tests use the real `SystemTrasher` on purpose (`moveToTheRealTrashAndRestore`,
  `readOnlyVolumeFailsCleanlyAndFullVolumeStillTrashes`). They trash only files they created in the sandbox or
  on the test image; the first restores its item afterwards.
- `SafetyPolicy` is constructed with the sandbox as home, or with the fictitious `/Users/tester`.
- Read-only assertions are made against real system paths in a few places (the signature of
  `/System/Applications/Mail.app`, the presence of a startup volume); nothing is written there.
- UI tests launch the application with `-ORIXHome /tmp/orix-uitest/home`, a folder on a 900 MB APFS disk image
  created and destroyed by `Scripts/build.sh uitest`. Cleanup scenarios really move files to the Trash of that
  image. The history store is in memory (`-ORIXStore memory`).

## Core tests

`Packages/ORIXCleanCore/Tests/ORIXCleanCoreTests/` declares 56 `@Test` functions in 9 suites (counted in the
sources on 2026-11-21).

### ScannerTests (16)

| Test | What it proves |
|---|---|
| `sizesMatchTheKernel` | File and folder counts, logical and allocated totals equal the sums from `stat`, for sizes around the block boundary; the allocated total equals `du -sk` |
| `unicodeAndLongNames` | Accented, CJK, emoji, decomposed and 240-character names are returned exactly as on disk; extension parsing works |
| `pathsLongerThanPathMax` | A tree deeper than 1,500 bytes of path is scanned without issue through the `openat` fallback |
| `symlinkLoopsAreNotFollowed` | A link to the root, a link to a folder and a dangling link are recorded as links with no children; content is counted once |
| `hardLinksAreCountedOnce` | Three names of one inode count as three files but one file's worth of bytes; two are flagged duplicates |
| `apfsClonesReportSharedBlocks` | Clones are flagged as possibly sharing blocks, report full allocated size and near-zero private size, and share a clone id |
| `sparseFilesHaveSmallAllocation` | A 200 MB sparse file reports its logical size and a small allocated size equal to `stat` |
| `permissionDeniedIsReportedAndScanContinues` | An unreadable folder yields one `permissionDenied` issue and the `unreadable` flag; the rest is scanned |
| `missingAndNonDirectoryRoots` | The right `ScanError` is thrown for a missing root and for a file |
| `filesChangingAndDisappearingDuringScan` | 25 scans while another thread deletes and recreates folders: no crash, only `vanished` or `ioError` issues, and the root total always equals the sum over files |
| `largeDirectoryTree` | 32,000 files in 203 folders, including one folder of 12,000 entries, are all counted |
| `packagesAreFlagged` | `.app` and `.photoslibrary` are packages; their contents are hidden from "largest files" unless requested |
| `cancellationAndPause` | A cancelled scan returns `cancelled`; a paused scan makes no progress until resumed, then completes |
| `excludedPathsAndRemoval` | Excluded paths are flagged `skipped`; `markRemoved` subtracts sizes and counts from ancestors and hides the subtree |
| `mountedVolumeIsABoundaryAndRemovalIsAnError` | A volume mounted inside the root is a `boundary` and is not entered unless `stayOnDevice` is off; the volume can be scanned directly; after ejection the mount point is an empty folder |
| `queriesAndCategories` | Largest files and folders, filters by category, age, name and size, category totals, `Measure.item`, and volume lookup |

### TreemapTests (1)

| Test | What it proves |
|---|---|
| `areasAreProportionalAndInsideTheParent` | Cells stay inside the rectangle, areas are proportional to sizes, leaves do not overlap, 50 tiny files become one aggregate cell with the right count and size, and viewport culling reduces the cell count |

### DuplicateTests (9)

| Test | What it proves |
|---|---|
| `exactDuplicatesAreGroupedAndDifferentFilesAreNot` | Identical files are grouped, same-size different files are not, redundant size is correct, the digest equals `shasum -a 256`, and the minimum size filter works |
| `differencesOutsideTheSampledWindowsAreCaughtByTheFullHash` | One changed byte outside the three sampled windows passes the sample hash but is caught by the full hash and by the byte comparison |
| `collisionsInThePreliminaryFilterDoNotCreateFalseGroups` | With a sampler that always collides, groups are still decided by the full hash |
| `hardLinksAreOneFileNotDuplicates` | Two names of one inode are not a duplicate pair; with a real copy, the linked file lists its other name and removing it is estimated to free nothing |
| `clonesAreDuplicatesThatShareStorage` | A clone pair is one group flagged as sharing storage, with a recoverable range from near zero to the full size |
| `largeFilesAndUnreadableFiles` | Two 48 MB real copies are hashed in full and grouped; an unreadable file does not break the run |
| `aFileThatChangedSinceTheScanIsDropped` | A file whose size changed after the scan is excluded |
| `packageContentsAreSkippedUnlessAsked` | Identical files inside two applications are ignored by default and found when requested |
| `cancellationReturnsNoGroups` | A cancelled run returns no groups |

### SimilarImageTests (3)

| Test | What it proves |
|---|---|
| `resizedAndRecompressedCopiesAreGroupedAndUnrelatedImagesAreNot` | A picture, its resized recompressed JPEG and its PNG form one group; seven unrelated pictures form none |
| `thoroughModeFindsCrops` | Thorough mode groups a picture with its cropped version |
| `corruptImagesAreCountedNotCrashed` | An undecodable `.jpg` is counted as unreadable and nothing is grouped |

### SafetyPolicyTests (2)

| Test | What it proves |
|---|---|
| `protectedLocationsAreDenied` | 32 paths are refused: system areas, top-level and standard folders, another user's home, the keychain, volume roots, the inside of an application and of a photo library, relative paths, `..`, the Data-volume alias, `/tmp` |
| `ordinaryItemsAreAllowed` | 13 ordinary paths are allowed, including a whole application, a whole photo library, items inside the Trash and items on another volume |

### DeletionTests (11)

| Test | What it proves |
|---|---|
| `nothingIsRemovedWithoutAuthorization` | An item in the plan but not in the authorization is skipped and stays on disk |
| `highRiskNeedsExplicitAcknowledgement` | A high-risk item is skipped unless acknowledged |
| `moveToTheRealTrashAndRestore` | With the real Trash: the item leaves its place, exists at the reported Trash path, is restored with identical content, and cannot be restored twice |
| `restoreRefusesToOverwrite` | Restore returns `destinationOccupied` when a new item exists at the original path |
| `revalidationSkipsVanishedReplacedAndChangedItems` | Items that vanished, were replaced by another inode, or changed size are skipped |
| `duplicatesAreVerifiedAgainstTheKeptCopy` | A true duplicate is removed; a copy that drifted, one whose kept copy is missing, and a hard link of the kept copy are skipped |
| `aGroupIsNeverEmptied` | Two duplicates each naming the other as the kept copy: neither is removed |
| `partialFailureIsReportedPerItem` | One failure does not stop the run; a volume without Trash yields `requiresManualAction` and the item stays |
| `protectedPathsRunningAppsPermanentModeAndCancellation` | Home, Documents and Library are refused; data of a running application requires manual action; permanent mode is refused outside the Trash category and works inside it; a cancelled engine skips everything |
| `readOnlyVolumeFailsCleanlyAndFullVolumeStillTrashes` | On a read-only image nothing is removed and the failure is reported; on a full image the move to that volume's Trash still succeeds and the Trash inventory sees it |
| `planDeduplicatesNestedItems` | A folder listed twice together with items inside it yields one plan item with correct totals |

### CatalogTests (6)

| Test | What it proves |
|---|---|
| `cachesSectionListsOnlyDocumentedSafeLocations` | Application caches, a browser cache and logs are listed; `com.apple.*`, CloudKit, tiny entries and developer caches are not; owner, apps to close, risk and sizes are set; every item passes the safety policy |
| `developerSectionSplitsPerProjectAndMarksArchivesForReview` | DerivedData is one low-risk item per project; archives are `review`; npm and Homebrew caches are found; every item passes the safety policy |
| `everyRuleIsDocumented` | Every catalogue rule has a reason, a consequence and a regeneration note, and rule ids are unique |
| `buildArtifactsNeedTheirManifest` | `node_modules` and `.build` are proposed only next to their manifest; look-alikes are not |
| `downloadsAreClassified` | Disk image, installer, archive, incomplete download and other items are classified; hidden files are ignored; an extracted sibling is detected and mentioned |
| `trashInventory` | Items and sizes of a Trash folder are listed; an unreadable Trash is reported as not accessible |

### ApplicationTests (3)

| Test | What it proves |
|---|---|
| `discoveryAssociatedFilesAndUninstallPlan` | Bundle facts are read; associated files are matched with the right confidence; look-alike names are not matched; name-only matches become high risk; documents are never included |
| `systemApplicationsAreNeverOffered` | A system application yields no uninstall items; its signature is read as Apple and valid |
| `leftoversAreInferredConservatively` | Only the identifier with no installed application, no shared vendor prefix, no Apple prefix and no Launch Services registration is reported |

### HistoryAndReportTests (3)

| Test | What it proves |
|---|---|
| `historyStoreRoundTrip` | Samples, the 15-minute de-duplication, the trend slope, watched folders, folder samples, operations and documents round-trip; data survives reopening; erase empties samples and operations |
| `recommendationsComeOnlyFromEvidence` | Empty findings give no recommendation; low space, large DerivedData and a growth trend each appear only when their data is present |
| `reportRenderers` | Markdown escapes table pipes; CSV quotes fields and neutralizes formulas; JSON decodes with all sections; PDF output starts with `%PDF-`; cleanup results carry status and note |

### WorkflowTests (2)

| Test | What it proves |
|---|---|
| `validationForbidsRemovalWithoutReview` | Removal without review, removal after an intervening collection, a second removal after one review, duplicates without a scan and an empty workflow are all rejected; the built-in workflows are valid |
| `duplicateWorkflowKeepsOneCopyAndStopsWhenReviewIsDeclined` | A declined review removes nothing; an approved one removes two of three copies and leaves the unrelated file |

## UI tests

`UITests/ORIXCleanUITests.swift` has 8 scenarios. `Scripts/build.sh uitest` regenerates the project, creates
the disk image at `/tmp/orix-uitest`, builds `orix-bench` in release mode, writes the sample home folder at
scale 0.25, runs the tests, then detaches and deletes the image. Tests are skipped when the sample folder is
missing. The application is launched in English (`-AppleLanguages (en)`, `-AppleLocale en_CA`), and each
scenario keeps window screenshots as attachments.

| Scenario | What it checks |
|---|---|
| `testFirstLaunchShowsOnboardingAndNothingIsScanned` | Onboarding appears on first launch; after "Get Started" the Overview is shown with no scan and no selection |
| `testScanStorageMapSearchAndSidebarNavigation` | A scan produces the map and its list; search finds a file and shows a match count; Large Files lists the largest file |
| `testDuplicatesAndSimilarImages` | Duplicate groups appear with "3 copies" and a "shares storage" label; similar-image groups appear |
| `testCachesDeveloperDownloadsAndTrashLists` | Each of the four lists shows its expected fixture item; nothing is preselected |
| `testUninstallPreviewCancelThenRealCleanupAndPutBack` | Selecting removes nothing; cancelling the preview removes nothing; confirming moves the application to the Trash; Put Back restores it; the selection bar disappears |
| `testReportExportWritesAFile` | Exporting a report writes a file that starts with `%PDF-` |
| `testActionStopsWhenTheReviewIsDeclined` | Running the built-in cache action and cancelling its preview leaves the cache folder in place and logs "Nothing was removed" |
| `testSettingsLightModeHistoryAndWindowResize` | Light appearance, the History section, the Settings window, and the layout at 980 by 620 and at 1800 by 1100 |

## Known flakiness

- **Keyboard focus.** UI tests can fail when another process takes keyboard focus during a run (another
  automation session, a system dialog, a notification that activates an application). Typed text then goes to
  the wrong window or a click lands on an inactive one. The helpers reduce this: `tap` re-activates the
  application and retries up to four times, and `type` checks `hasKeyboardFocus` before typing. They do not
  eliminate it. Run UI tests on a machine that is otherwise idle, and rerun a single scenario with `ORIX_ONLY`
  before treating a failure as a regression.
- **Shared paths.** The image is always mounted at `/tmp/orix-uitest`, so two UI test runs cannot overlap on
  one machine.
- **Timing.** Scenarios wait up to 40 seconds for analyses; a heavily loaded machine can exceed that.
- **Core tests using `hdiutil`.** Two core tests create disk images. When `hdiutil` is unavailable they record
  an issue instead of passing silently.
- **Unreadable-file test.** `largeFilesAndUnreadableFiles` accepts either outcome for the locked file's listing,
  because the sampling stage can drop it before the full hash.

## What is not tested

- Intel execution, and macOS 15 and 26: tests were run on Apple silicon with macOS 27.0 only.
- Real TCC prompts and Full Disk Access transitions (the probe is exercised only against the current state).
- External disks, HDDs and network volumes; non-APFS filesystems.
- VoiceOver or Voice Control behaviour; UI tests use accessibility identifiers, which shows the elements are
  exposed but not that the experience is good.
- The French interface in UI tests.
- The release scripts (signing, notarization, packaging).
- Emptying the Trash through the UI (permanent mode is covered at engine level).
