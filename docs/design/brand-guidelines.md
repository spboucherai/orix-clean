<!-- ORIX Clean / File: docs/design/brand-guidelines.md / Author: Simon-Pierre Boucher / Contact: contact@spboucher.ai -->
# Brand guidelines

How ORIX Clean presents itself: name, tagline, voice and visual identity. The rules below describe what the
shipped strings and assets already do, so that new text and artwork stay consistent with them.

## Name and tagline

| Element | Form | Where it appears |
|---|---|---|
| Product name | **ORIX Clean** | Window title, bundle display name, disk image, report footers |
| Tagline | **ORIX Clean — Reclaim Space. Keep Control.** | Onboarding ("Reclaim space. Keep control."), disk-image background |
| Bundle identifier | `ai.spboucher.orix.clean` | `project.yml` |
| Category | Utilities (`public.app-category.utilities`) | `Info.plist` |
| Copyright | © 2026 Simon-Pierre Boucher | `Info.plist` |

Writing the name:

- "ORIX" is always in capitals; "Clean" has a capital C; there is a space between them. Not "Orix Clean",
  "ORIXClean" or "ORIX CLEAN" in prose. (`ORIXClean` without a space is used only in file names, the Xcode
  target and artifact names such as `ORIXClean-1.0.0.dmg`.)
- The name is not translated. In French text it stays "ORIX Clean".
- The tagline has two halves that belong together. "Reclaim Space" is the benefit; "Keep Control" is the
  condition under which the product delivers it. Do not use the first half alone.
- Feature names are plain descriptive words: Storage Map, Large Files, Duplicates, Similar Images,
  Caches & Logs, Developer, Downloads, Applications, Trash, History, Actions, Reports.

## ORIX family principles

ORIX Clean is one of the ORIX applications. The family shares a few commitments, which here take a concrete
form that can be checked in the code.

| Principle | In ORIX Clean |
|---|---|
| **Native** | SwiftUI and AppKit, system controls, SF Symbols, system fonts. No web views (the repository check rejects `WKWebView`) |
| **Local** | No account, no network code, no analytics. Image analysis runs on the Mac with Vision |
| **Honest** | Every figure is measured; what could not be read is stated; estimates are labelled as estimates and given as ranges |
| **The user decides** | Nothing preselected, nothing removed without a preview and a confirmation, removal goes to the Trash |
| **Quiet** | No notifications, no badges demanding attention, no background activity when the window is closed |
| **Shared visual base** | The family canvas, surface and hairline colours and the family indigo; each product adds its own accent |

## Tone of voice

**Factual. No urgency. No fear.**

The interface describes the state of the disk and the consequence of each action. It does not tell the user
how to feel about either.

### Rules

1. **State what was measured.** Give the number, the unit and the scope. "%d project folders in DerivedData
   use %@." is the pattern, not "Your Mac is cluttered".
2. **State the consequence of acting.** Every candidate has a consequence sentence: what will be slower, lost
   or downloaded again.
3. **State what is not known.** "Inferred from the name only. Not proof that the item is orphaned."
   "Perceptual similarity is not equality."
4. **No urgency.** No "now", "immediately", "before it is too late", countdowns or exclamation marks.
5. **No fear.** No "junk", "danger", "at risk", "infected", "critical", health scores or red alarm banners.
   A risk level describes the item, not the user's situation.
6. **No exaggeration.** No "boost", "optimize", "supercharge", "like new". The app reclaims space; it does not
   claim to make the Mac faster.
7. **Say who does what.** "macOS did not allow reading…", "macOS reports…", "ORIX Clean cannot know whether
   you still need it." Refusals are attributed to their source.
8. **Destructive actions are named exactly.** "Move 12 Items to Trash", "Delete Permanently". Never a vague
   "Clean" on the button that acts.
9. **Short sentences, second person, present tense.** Sentence case for text, title case for menu items and
   buttons, as on macOS.

### Examples from the shipped strings

| Situation | Text |
|---|---|
| Low free space | "%@ is running low on free space" with evidence "%@ free of %@ (%d%%)." |
| Growth trend | "A projection from past samples, not a forecast: growth may stop or accelerate." |
| Cache candidate | "The application rebuilds it the next time it needs it; the first launches may be slower." |
| Xcode archives | "The archived builds can no longer be re-exported, and their crash reports can no longer be symbolicated from this Mac." |
| After a cleanup | "%@ is now in the Trash and still occupies disk space. It is reclaimed when you empty the Trash." |
| Permission refused | "macOS did not allow reading the Trash. Grant Full Disk Access to ORIX Clean to see its content, or empty it from Finder." |
| Full Disk Access | "Optional. Without it ORIX Clean still works on everything macOS lets it read, and tells you what was not read." |
| Manual selection | "The item goes to the Trash. ORIX Clean cannot know whether you still need it." |

### Words

| Prefer | Avoid |
|---|---|
| size on disk, content size, estimated recoverable | wasted space, junk size |
| candidates, items, selection | junk, clutter, garbage |
| review, confirm | fix, repair, optimize |
| move to Trash, delete permanently | clean up now, wipe, shred |
| low risk, review required, high risk | safe, dangerous |
| could not be read, not counted | error, failure (unless it is one) |

### French (fr-CA)

The French interface follows the same rules. Translations live in `Scripts/translations-fr.json` and are
written for Canadian French: a space before a colon, « » quotation marks where quotes are needed, the
typographic apostrophe, macOS vocabulary as used in the French system (Corbeille, Téléchargements), and the
same absence of urgency. The tagline reads « Récupérez de l’espace. Gardez le contrôle. »

## Visual identity

| Element | Rule |
|---|---|
| Icon | The storage ring with a swept quarter; see `icon-design.md`. Use the supplied PNGs; do not redraw, recolour, rotate or crop |
| Accent | Teal: `#0A9E96` on light, `#2DD4BF` on dark |
| Secondary | Family indigo: `#5B5BF0` on light, `#8484FF` on dark |
| Brand gradient | `#2DD4BF` to `#06B6D4` to `#5B5BF0`, top-leading to bottom-trailing |
| Dark plate | `#1B2340` to `#070A16`, as on the icon and the disk-image background |
| Risk colours | Green, amber and red are reserved for risk levels and outcomes. Do not use red for emphasis or marketing |
| Typeface | The system font. No brand typeface |
| Symbols | SF Symbols only, in the weights the system provides |

The 1024-pixel artwork already includes its margin (the plate is inset 100 pixels on each side) and its drop
shadow; do not add another plate or shadow behind it. At small sizes use the matching asset from the asset
catalogue rather than scaling the large one at run time.

## Screenshots and marketing material

- Use the generated sample folder (`orix-bench fixture`) rather than a real home folder; never show real file
  names of a real person.
- Do not show a "space freed" figure that the application did not measure and display itself.
- Do not compare against named products with numbers that were not measured.
- Do not state that a build is signed, notarized or published unless the release checklist records it.

## What the brand is not

- Not a "Mac health" or security product.
- Not an optimizer; it makes no performance claim.
- Not an account-based service; the code contains no account system and no licence check.
