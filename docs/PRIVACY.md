<!-- ORIX Clean / File: docs/PRIVACY.md / Author: Simon-Pierre Boucher / Contact: contact@spboucher.ai -->
# Privacy

What ORIX Clean reads, what it stores and where, what it never does, and which permissions it asks for. This is
a technical description of the 1.0.0 code, written so that each statement can be checked against the sources.

## Summary

- Everything happens on the Mac. The application contains no network code.
- A scan reads names, sizes, dates and filesystem flags. File contents are read only in the specific cases
  listed below.
- Scan results are kept in memory and are gone when the application quits or a new scan starts.
- One small local database stores free-space samples, sizes of folders you chose to watch, the log of your
  cleanups and your saved actions.
- There is no account, no analytics, no advertising, no crash reporting and no automatic update check.

## What is read

### During a scan

For each file and folder under the location you chose, the scanner asks the filesystem
(`getattrlistbulk`) for:

| Data | Used for |
|---|---|
| Name | Display, search, file-type category from the extension |
| Type (file, folder, symbolic link, other) | Traversal and counting |
| Content size, size on disk, APFS private size | All size figures |
| Modification date | Age filters and display |
| Flags: dataless, compressed, sparse, may share blocks; clone identifier | Accurate accounting and labels |
| Link count, inode number, device number | Counting hard links once; detecting other volumes; checking that an item is still the same before removing it |

**A scan does not open files.** Symbolic links are never followed. Files that are in iCloud but not on the Mac
are detected from their metadata and never read, so nothing is downloaded.

### Without a scan: what is measured when a section opens

Some measurements do not wait for a scan. They read names and sizes only, and select nothing.

| When | What is measured |
|---|---|
| The Overview appears (at first launch, only after the welcome sheet is dismissed) | Cache and log folders in `~/Library/Caches` and `~/Library/Logs`, known browser caches, old items in your temporary folder, the documented developer locations, the top level of `~/Downloads`, and the Trash. These feed the recommendations |
| Caches & Logs, Developer, Downloads or Trash is opened | The same locations for that section |
| Applications is opened | Applications in `/Applications`, `~/Applications` and `/System/Applications`, then, for the application you select, its files in your Library |
| At launch and every 15 minutes | The volume list and the Full Disk Access probe |

Because the Overview measures `~/Downloads`, macOS can show the Downloads consent prompt as soon as the
welcome sheet is dismissed, before you start any scan. Nothing is read while the welcome sheet is shown.

### File contents: the complete list of cases

| When | What is read | Why |
|---|---|---|
| You run the duplicate search | Files that have the same size as another file: three 16 KiB samples, then the whole file for those still matching | SHA-256 comparison. Only the digest is kept, in memory |
| A duplicate you confirmed is about to be removed | That file and the copy that stays | Byte-for-byte check that they are still identical |
| You run the similar-image search | Image files (jpg, png, heic, tiff, gif, bmp, webp) of 8 KiB or more | A thumbnail of at most 448 pixels is decoded to compute a 64-bit hash and, when needed, a Vision feature print. Computed on the Mac; thumbnails and vectors are kept in memory only |
| A list shows a thumbnail, or you choose Quick Look | The file concerned | Standard macOS Quick Look |
| The Applications section is opened | Each application's `Info.plist` and code signature; Spotlight's last-used date | Name, identifier, version, signer; the application is not executed |

Files inside application bundles, photo libraries and other packages are not hashed or analysed unless you
turn on the corresponding option for duplicates; similar-image analysis never looks inside packages.

### Other information

| Data | Source | Used for |
|---|---|---|
| Mounted volumes: name, UUID, format, capacity, free space | `FileManager`, `statfs` | Overview, history samples |
| Bundle identifiers of running applications | `NSWorkspace` | Refusing to clean data of an application that is running |
| Whether an identifier is registered with Launch Services | `LSCopyApplicationURLsForBundleIdentifier` | Avoiding false "leftover" reports |
| Whether Full Disk Access is granted | An attempt to open three protected paths (the TCC database, Safari bookmarks, the Mail folder); the descriptor is closed immediately and nothing is read from it | Showing the state in Settings and in reports |

## What is stored, and where

### The history database

`~/Library/Application Support/ORIX Clean/history.sqlite` (with its `-wal` and `-shm` companion files while
the application is open). It is a plain SQLite file, not encrypted beyond the protection of your disk.

| Table | Content | Contains file paths |
|---|---|---|
| `volume_samples` | Time, volume UUID, volume name, capacity, free space. At most one sample per volume per 15 minutes while the application is open, and after scans and cleanups. Network volumes are not sampled | No |
| `watched` | Folders you asked to watch | Yes: those folder paths |
| `folder_samples` | Time, path, content size, size on disk and file count of each watched folder | Yes: those folder paths |
| `operations` | One record per cleanup: for each item its original path, its path in the Trash, sizes, category, outcome and explanation; start and end time; free space before and after | **Yes: the paths of items you cleaned or tried to clean** |
| `documents` | Actions you saved, including a folder path if the action scans one | Yes, if you entered one |

The database never contains the scan tree, the list of your files, duplicate groups, image fingerprints or any
file content.

### Preferences

The application's user defaults (`ai.spboucher.orix.clean`) hold interface choices only: `appearance`,
`density`, `mapPalette`, `sizeKind`, `showPackageContents` and `onboarded`.

### In memory only

The scan tree (names and sizes), duplicate and similar-image results, candidate lists and the cleanup
selection. They are discarded when the application quits; a new scan replaces the previous tree.

### Files you create

- **Reports** (PDF, CSV, JSON, Markdown) are written only where you save them. They contain file paths and
  sizes. Treat them as you would the folder listing itself before sharing them.
- **Copy Path** places the path of one item on the clipboard when you choose it.

### Kept by macOS, not by the application

Your consent decisions for protected folders and Full Disk Access (System Settings > Privacy & Security), the
window state, and Quick Look's own thumbnail cache are managed by the system.

## What never happens

- **No network connection.** There is no networking code in the application or its core library, and no web
  view. `Scripts/check.sh` fails the repository check if `URLSession`, `NWConnection`, `CFSocket`,
  `import Network`, `URLRequest` or `WKWebView` appears in the sources.
- **No account, sign-in or licence check.**
- **No analytics, telemetry, advertising identifiers or third-party SDK.** The application has no third-party
  dependency.
- **No crash or diagnostic upload** by the application. (macOS may offer its own crash reporting to Apple,
  according to your system settings.)
- **No update check.** Updates are manual downloads.
- **No background activity.** There is no helper, launch agent or login item; nothing runs when the
  application is closed.
- **No privilege escalation.** No administrator password is requested, no privileged helper is installed, no
  private API is used.
- **No removal without your confirmation.** Items leave their place only after you confirm the exact list in
  the cleanup preview, and they go to the Trash. Permanent deletion exists only for items already in the Trash
  and requires typing a confirmation.
- **No modification of your files.** Apart from moving confirmed items to the Trash, putting them back, and
  emptying the Trash on request, the application writes only its database, its preferences and the reports you
  export.

## Permissions

The application is not sandboxed. macOS still protects certain locations and asks you before the application
can read them.

| Permission | When macOS asks | If you refuse |
|---|---|---|
| Desktop folder | First time a scan or analysis reaches it | The folder is listed as not readable and is missing from totals |
| Documents folder | Same | Same |
| Downloads folder | Same, or when the Overview or the Downloads section opens | Same; the Downloads section explains how to allow it |
| Removable volumes | First scan of an external volume | The volume cannot be scanned |
| Network volumes | First scan of a network volume | The volume cannot be scanned |
| Full Disk Access | Never asked by a prompt; you add the application yourself in System Settings | Mail, Safari and Messages data, other applications' containers and the Trash are not read. The application says what was not read |

The texts shown in these prompts are in `App/Info.plist`; each ends with "Nothing leaves this Mac."

Full Disk Access is optional. It does not allow the application to read other users' files, to modify system
files, or to remove items you could not remove yourself. Every permission can be revoked at any time in
System Settings > Privacy & Security.

The application requests no access to the camera, microphone, contacts, calendars, photos library API,
location, Bluetooth, local network or automation of other applications.

## Your controls

| Action | How |
|---|---|
| See where the database is | Settings > Privacy & Access > Local database > Reveal |
| Erase recorded samples and the cleanup log | Settings > Privacy & Access > Erase History… This deletes volume samples, folder samples and cleanup records. It keeps the list of watched folders and your saved actions |
| Stop watching a folder | History > the minus button next to the folder |
| Delete a saved action | Actions > the action's menu > Delete |
| Remove everything | Quit the application and delete `~/Library/Application Support/ORIX Clean/` and the preferences of `ai.spboucher.orix.clean` |
| Revoke access | System Settings > Privacy & Security > Files and Folders, and Full Disk Access |

## Limits of this statement

- It describes version 1.0.0 as read in the source code. It is not a legal privacy policy.
- "No network code" is enforced by a source-level check for the listed APIs, not by a network sandbox.
- Behaviour was observed on macOS 27.0 only.

Contact: contact@spboucher.ai
