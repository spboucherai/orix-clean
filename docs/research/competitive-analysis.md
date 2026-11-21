<!-- ORIX Clean / File: docs/research/competitive-analysis.md / Author: Simon-Pierre Boucher / Contact: contact@spboucher.ai -->
# Competitive analysis

A comparison of approaches in the macOS storage-utility space, and the choices ORIX Clean makes within it.

## Scope and caveats

- This document compares **categories of approach**. Products are named only as familiar examples of a category.
- Every statement about a third-party product is **to the best of public knowledge; not verified here**. No
  third-party product was installed, measured or tested for this document, and no version was pinned.
- No prices, licence terms, feature lists or performance figures of other products are given: they change, and
  none were checked.
- Statements about ORIX Clean are taken from its source code and can be checked there.

## Categories

| Category | Familiar examples | What the category is for | Typical way of working |
|---|---|---|---|
| Disk visualizers | DaisyDisk, GrandPerspective | Show where space goes | Scan a volume or folder, draw a sunburst or treemap, let the user drill down and remove items |
| General cleaners | CleanMyMac | Free space with little effort | Scan known categories of "junk", present a total, offer a single cleaning action, often alongside maintenance and protection modules |
| Uninstallers | AppCleaner | Remove an application with its support files | Match Library files to a bundle by identifier and name, list them, delete on confirmation |
| Duplicate finders | Gemini, dupeGuru | Find redundant files | Group by content hash or by similarity, suggest which copy to remove |

(Examples to the best of public knowledge; not verified here.)

## Where the approaches differ

The interesting differences are not in feature lists but in a handful of design questions.

| Question | Common answers in the field | ORIX Clean |
|---|---|---|
| What does a size mean? | Usually one number per item | Three measured numbers per file: content size, size on disk, and the APFS private size. Recoverable space is a range, minimum to maximum |
| What does "you will free X" mean? | Usually a single figure | A range when files share blocks; exact only when the filesystem reports nothing shared. Moving to the Trash is stated as freeing nothing until the Trash is emptied |
| Who decides what is removed? | Varies from fully manual to one-click or scheduled cleaning | Always the user, in a preview that lists the exact items. No one-click cleaning, no schedule, nothing preselected |
| How is the user motivated? | Varies; some products use health scores, alerts or reminders | Facts with their evidence. No score, no alarm styling, no countdown |
| How are protected locations reached? | Some utilities install a privileged helper or ask for an administrator password | No helper and no elevation. What the user cannot remove is reported as such |
| Does the utility use the network? | Commonly for updates, licensing or telemetry | No network code at all in 1.0; updates are manual downloads |
| Where is the result kept? | Varies | Scan results in memory only; a small local SQLite file for history and logs |

(Left-hand answers to the best of public knowledge; not verified here.)

## What ORIX Clean deliberately does differently

### Measured sizes, and recoverable space as a range

Sizes come from `getattrlistbulk(2)` during the scan. Each file carries its logical size, its allocated size
and, on APFS, the private size the filesystem reports. `RecoverableEstimate` keeps a minimum (sum of private
sizes) and a maximum (sum of allocated sizes) and is displayed as "A to B" unless both are equal. Hard-linked
copies in a duplicate group are stated to free nothing; clone groups are labelled as sharing storage. The
rationale is in `docs/architecture/storage-accounting.md`: on a copy-on-write filesystem a single figure is
either wrong or lucky.

### No urgency in the interface

`InfoBanner` is documented in the code as "never styled as an alarm". Recommendations are produced only from
data that has actually been analysed (`Findings` fields are optional and nil means "not analysed yet"), each
with a sentence of evidence, the measured size and the consequence. The low-space recommendation states the
measured percentage. The growth recommendation states that it is "a projection from past samples, not a
forecast". There is no health score.

### No automatic cleanup

- Nothing is ticked by default in any list; a UI test asserts it for the cache list.
- Removal requires a `CleanupAuthorization`, and the application creates one in a single place: the confirm
  button of the cleanup preview.
- Saved workflows (Actions) cannot skip the preview: `Workflow.validate` rejects a removal step that does not
  directly follow a review step.
- Permanent deletion exists only for items already in the Trash, behind a typed confirmation.
- There is no scheduler and no background agent; the app does nothing when it is not open.

### No privileged helper

The app runs as the user, with the Hardened Runtime and an empty entitlements file. It does not use
EndpointSecurity, a launch daemon or an authorization prompt. The cost is explicit: root-owned items and other
users' files cannot be removed, and the app says so per item instead of working around it.

### No network

There is no network code in the application or the core package; `Scripts/check.sh` fails the repository check
if `URLSession`, `NWConnection`, `CFSocket`, `import Network`, `URLRequest` or `WKWebView` appears in the
sources. Consequences: no account, no telemetry, no licence check, no crash upload, and no automatic updater.
Sparkle was evaluated and deferred because an updater requires network access, which contradicts the rule for
1.0. Similar-image analysis runs locally with the Vision framework.

### Conservative association and inference

- Uninstall: each associated file carries a confidence (`identifier`, `sharedGroup`, `nameMatch`). Anything
  below an exact identifier match is classed high risk and needs an explicit acknowledgement.
- Leftovers: reported only when the name looks like a reverse-DNS identifier, no installed application shares
  the identifier or its vendor prefix, and Launch Services does not know it. The item states that it is
  "inferred from the name only. Not proof that the item is orphaned."
- Caches: `~/Library/Caches` entries beginning with `com.apple.` and a list of system service folders are never
  offered.

## What ORIX Clean does not do

Stated plainly, because several of these are common in the categories above (to the best of public knowledge;
not verified here):

- No malware scanning, no memory or CPU "optimization", no login-item or extension management.
- No whole-volume sunburst; the map is a treemap of the scanned folder.
- No snapshot management and no control over purgeable space.
- No removal of system applications, simulator runtimes or Docker data (these are measured and explained).
- No cloud, mail-attachment or photo-library internal cleanup.
- No automatic updates.
- No Mac App Store distribution: the app is not sandboxed, by design, so that it can measure what the user asks
  it to measure.

## Trade-offs accepted

| Choice | Cost |
|---|---|
| Range instead of one figure | Less satisfying to read; requires a sentence of explanation in the interface |
| Preview before every removal | More clicks than a one-button cleaner |
| No helper | Some items can only be reported, not removed |
| No network | Updates are manual; no crash reports reach the author |
| Scan results in memory only | Every session starts with a new scan |
