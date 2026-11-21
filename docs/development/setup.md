<!-- ORIX Clean / File: docs/development/setup.md / Author: Simon-Pierre Boucher / Contact: contact@spboucher.ai -->
# Development setup

How to build, run and extend ORIX Clean from a clone of the repository.

## Requirements

| Tool | Needed for | Notes |
|---|---|---|
| macOS with Xcode | Everything | Developed with Xcode 27.2 and Swift 6.4.2 on macOS 27.0. The package declares `swift-tools-version: 6.0`; the deployment target is macOS 15.0. Older Xcode versions were not tried |
| XcodeGen (`xcodegen`) | Generating `ORIXClean.xcodeproj` from `project.yml` | The project file is generated; edit `project.yml`, not the project |
| Python 3 (`python3`) | `Scripts/localize.py` | Standard library only |
| `hdiutil` | UI tests and some core tests | Part of macOS |
| `create-dmg` | `Scripts/package.sh` only | Falls back to a plain `hdiutil` image when it fails |
| Developer ID Application identity, `notarytool` keychain profile | Release only | See `docs/release/` |

No third-party Swift package is used. Debug builds are signed ad hoc (`CODE_SIGN_IDENTITY: "-"`), so no
developer account is needed to build, run or test.

## Repository layout

```
App/                 SwiftUI application (Sources, Resources, Info.plist, entitlements)
Packages/ORIXCleanCore/   Core library, orix-bench CLI, tests
UITests/             XCUITest scenarios
Scripts/             build, check, localize, icon, screenshots, signing, notarization, packaging
design/icon/         Icon concepts and the 1024-pixel icon
docs/                This documentation
project.yml          XcodeGen definition
build/, dist/        Generated, ignored by git
```

## Building and running

`Scripts/build.sh` is the entry point. It changes to the repository root itself.

| Command | What it does |
|---|---|
| `Scripts/build.sh generate` | Runs `Scripts/localize.py` (when `translations-fr.json` exists), then `xcodegen generate` |
| `Scripts/build.sh debug` | `generate`, then `xcodebuild` for the `ORIXClean` scheme in Debug into `build/DerivedData` |
| `Scripts/build.sh core-test` | `swift test` in `Packages/ORIXCleanCore` |
| `Scripts/build.sh uitest` | Builds a disposable disk image with the sample home folder and runs the UI tests on it (see `testing.md`) |
| `Scripts/build.sh run` | Opens `build/DerivedData/Build/Products/Debug/ORIX Clean.app` |
| `Scripts/build.sh all` | `core-test`, then `debug`. This is the default |

The script prints a filtered summary (errors, build and test verdicts, failed test cases). The complete UI test
log is written to `build/uitest.log`.

To work in Xcode: `Scripts/build.sh generate`, then open `ORIXClean.xcodeproj`. The scheme `ORIXClean` builds
the application and the UI test bundle. The core package can also be opened on its own
(`Packages/ORIXCleanCore/Package.swift`).

`Scripts/check.sh` verifies repository hygiene and exits non-zero on any finding:

- the author header on every Swift, shell and Python file and on `project.yml`;
- no signing material (`.p8`, `.p12`, `.cer`, provisioning profiles, keychains, `.env`, `AuthKey_*`);
- no credential-like strings or private network addresses;
- no network code in `App/Sources` or the core library (`URLSession`, `NWConnection`, `CFSocket`,
  `import Network`, `URLRequest`, `WKWebView`);
- no privilege escalation or private API markers (`AuthorizationExecuteWithPrivileges`, `SMJobBless`,
  `NSAppleScript`, `/usr/bin/sudo`, `dlopen(`, `_CS`, `csrutil`).

## Project settings worth knowing

| Setting | Value |
|---|---|
| Bundle identifier | `ai.spboucher.orix.clean` |
| Deployment target | macOS 15.0 |
| Swift | language mode 6, strict concurrency `complete`, default actor isolation `MainActor` in the application target |
| Sandbox | off (`ENABLE_APP_SANDBOX: NO`) |
| Hardened Runtime | on |
| Entitlements | empty dictionary (`App/ORIXClean.entitlements`) |
| Debug | ad hoc signature, active architecture |
| Release | `Developer ID Application`, manual signing, `--timestamp`, `arm64 x86_64` |
| Version | `MARKETING_VERSION` 1.0.0, `CURRENT_PROJECT_VERSION` 1 |

## Launch arguments

The application reads these through `UserDefaults` (`LaunchOptions.fromProcess`), so each is passed as
`-Name value`. They exist for UI tests, screenshots and benchmarks; none changes what the engines measure.

| Argument | Value | Effect |
|---|---|---|
| `-ORIXHome` | directory | Uses this directory as the home folder for caches, developer data, Downloads, Trash, applications (`<home>/Applications` only), leftovers and the safety policy. Other volumes' Trashes and the Launch Services lookup are disabled |
| `-ORIXStore` | `memory` or a file path | History database: in memory, or at the given path. Default is the Application Support path |
| `-ORIXScanRoot` | directory | Starts a scan of this directory when the window appears |
| `-ORIXSection` | `overview`, `map`, `largeFiles`, `duplicates`, `similar`, `caches`, `developer`, `downloads`, `applications`, `trash`, `history`, `actions`, `reports` | Section shown at launch |
| `-ORIXAutoAnalyze` | `YES` | Runs the duplicate and similar-image searches as soon as the scan finishes |
| `-ORIXExportDir` | directory | Reports are written there without showing a save panel |
| `-ORIXAppearance` | `light` or `dark` | Overrides the appearance setting |
| `-ORIXSkipOnboarding` | `YES` | Does not show the first-launch sheet |
| `-ORIXWindowSize` | `WIDTHxHEIGHT`, for example `980x620` | Resizes the main window at launch |

Debug builds only, and only together with `-ORIXHome`: `-ORIXDemoSelect` (`duplicates`, `uninstall`, or any other value for caches and DerivedData),
`-ORIXDemoPreview YES` and `-ORIXDemoConfirm YES` drive the real engines into a state for screenshots
(`AppModel.runDemo`). This code is inside `#if DEBUG` and is not compiled into Release builds.

Useful standard arguments: `-onboarded NO` (show onboarding again), `-ApplePersistenceIgnoreState YES`,
`-AppleLanguages "(fr-CA)"`.

The temporary-items rule of the cache catalogue is skipped under `-ORIXHome` (the temporary folder belongs to
the real user), and the path displayed in Settings is always the default database path.

Example:

```sh
"build/DerivedData/Build/Products/Debug/ORIX Clean.app/Contents/MacOS/ORIX Clean" \
  -ORIXHome /tmp/orix-demo/home -ORIXStore memory -ORIXScanRoot /tmp/orix-demo/home \
  -ORIXSection map -ORIXSkipOnboarding YES -ORIXAutoAnalyze YES
```

## The sample folder (fixture generator)

`orix-bench fixture <dir> [scale]` writes a sample home folder with real files of real sizes.

```sh
cd Packages/ORIXCleanCore && swift build -c release
.build/release/orix-bench fixture /tmp/orix-demo/home        # scale 1: 182 files, 1.89 GB
.build/release/orix-bench fixture /tmp/orix-demo/home 0.25   # the scale used by the UI tests
```

**The target directory is deleted first** (`Fixture.build` removes it before writing). Point it at a new
directory under `/tmp`, never at a real folder.

Content, all generated with a seeded pseudo-random generator so that runs are reproducible:

- movies, music, documents and an archive, with modification dates set in the past;
- exact duplicates as real copies (a video in three places, a dataset, an audio file) and one APFS clone of a
  disk image;
- 18 generated pictures with resized, recompressed, PNG and edited versions for similar-image analysis;
- a Downloads folder with installers, disk images, archives, an extracted archive and an incomplete download;
- three applications with Library files, and leftovers of two applications that are not installed;
- developer data: DerivedData for three projects, an Xcode archive, device support, simulator caches,
  Homebrew, SwiftPM, npm and pip caches, a `node_modules` and a `.build` folder next to their manifests;
- three files in `.Trash` (one file and a folder of two).

`Scripts/shot.sh <out.png> <section> [dark|light] [extra args…]` launches an isolated instance on the sample
folder (`ORIX_DEMO_HOME`, default `/tmp/orix-demo/home`), waits `ORIX_WAIT` seconds (default 5) and captures
the window by window id.

Other `orix-bench` commands are described in `performance.md`.

## Adding or changing a string

1. Write the string in code as `L("English text")`, with `%@` and `%d` placeholders where needed. The English
   text is the key.
2. Add the same key with its French translation to `Scripts/translations-fr.json`.
3. Run `Scripts/build.sh generate` (or `python3 Scripts/localize.py`). It rewrites
   `App/Resources/Localizable.xcstrings` (en and fr-CA) and `InfoPlist.xcstrings`.

`localize.py` fails and lists the problem when a key has no French translation or when the placeholders of the
translation differ from those of the key. `python3 Scripts/localize.py --keys` prints the keys found in the
sources. A key that reaches `L()` through a variable is invisible to the extractor and must be added to the
`EXTRA` list in the script; sidebar group names are an example. Translations of the privacy usage strings are
in the `INFO` dictionary of the same script. At the time of writing the catalogue holds 683 keys.

## Adding a language

Not scripted. It would need a second translations file, an extra localization in `localize.py`'s output and
the language added to `CFBundleLocalizations` in `project.yml`.

## Conventions

- Every first-party source file starts with the three-line header (file path, description, author);
  `Scripts/check.sh` enforces the author line.
- Engines go in the core package and stay free of UI imports; anything that needs AppKit or SwiftUI goes in
  `App/Sources`.
- Destructive code paths are exercised only on temporary directories and disk images (see `testing.md`).
