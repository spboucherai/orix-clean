<!-- ORIX Clean / File: docs/ACCESSIBILITY.md / Author: Simon-Pierre Boucher / Contact: contact@spboucher.ai -->
# Accessibility

What ORIX Clean 1.0.0 implements for accessibility, taken from the code, and an explicit list of what has not
been verified. Implementing an accessibility API is not the same as being usable with assistive technology;
the second half of this document matters as much as the first.

## Implemented

### Structure and labels

- The interface is built from standard SwiftUI controls (lists, buttons, pickers, toggles, sheets, forms,
  menus), which expose their roles and states to assistive technology without extra code.
- Decorative images are hidden from accessibility: status glyphs, file icons, thumbnails, chevrons and the
  proportion bars. A bar is always accompanied by its value as text.
- Icon-only buttons have explicit labels: "Enclosing folder", "Reset zoom", "Show the list", "Measure again",
  "Details", "More", "Remove step", "Stop watching *path*", "Scan *volume*".
- Rows that are made of several texts are combined into one element so that they are read as one item:
  section titles (with the header trait), stat tiles, the volume summary in the sidebar, preview rows,
  duplicate and similar-image rows, report kinds, cleanup log entries. Candidate rows, which hold several
  controls, are grouped as containers instead.
- The selection checkbox (`Checkbox`) is a button with a label naming the item ("Select *name* for cleanup"),
  a value ("Selected" / "Not selected") and the toggle trait.
- `RiskBadge` reads as its title ("Low risk", "Review required", "High risk").
- The history chart has a label ("Used space over time") and a value summarizing the number of samples and
  the range; the small per-folder sparklines are hidden and their figures are given as text.
- Tooltips (`.help`) explain controls and labels whose meaning is not obvious, for example "may share blocks".
- All of these strings are localized (English and Canadian French).

### The storage map and its equivalent list

A treemap drawn in a `Canvas` is a picture; its individual blocks are not accessibility elements. The map is
therefore exposed as a single element:

- label: "Storage map of *folder*";
- value: "*n* regions. Use the list next to the map to browse with VoiceOver."

**The list beside the map is the accessible equivalent.** It shows the children of the folder currently in
focus, largest first, each with its name, its size, a checkbox for the cleanup selection and, where relevant,
the text "not readable", "other volume" or "in iCloud". Each row has an "Open in Map" accessibility action and
the same item in its context menu, so drilling down does not require the pointer. The breadcrumb above the map
is a row of buttons, and "Enclosing folder" goes up one level. Searching by name turns the list into the list
of matches.

Everything that can be done on the map (open a folder, select an item for cleanup, reveal in Finder, Quick
Look, copy the path) can be done from the list.

Limits of the equivalent: the list shows at most 600 children of a folder and at most 300 search matches, and
it is hidden if the user turns off "Show the list".

### Keyboard

Shortcuts defined in the code:

| Shortcut | Action | Where |
|---|---|---|
| ⌘O | Scan Folder… | File menu |
| ⌘R | Scan Home Folder | File menu |
| ⌘↩ | Review Cleanup Selection… | File menu and the selection bar |
| ⇧⌘⌫ | Clear Cleanup Selection | File menu |
| ⌘1 … ⌘9 | Overview, Storage Map, Large Files, Duplicates, Similar Images, Caches & Logs, Developer, Downloads, Applications | Go menu |
| ⌘↑ | Enclosing folder | Storage Map |
| ↩ | Default button: Get Started, Done, Save | Onboarding, results sheet, action editor |
| esc | Cancel | Cleanup preview, action editor |
| ⌘, | Settings | Standard application menu |

Trash, History, Actions and Reports are in the Go menu without a shortcut. Lists, the sidebar, pickers and
sheets use the standard macOS keyboard behaviour.

The cleanup preview cannot be dismissed by accident: interactive dismissal is disabled, the confirm button is
never the default button, and permanent deletion requires typing `DELETE`.

### Colour

- **Risk never depends on colour alone.** Each level has its own symbol shape (circle with a check mark,
  circle with an eye, triangle) and its title in text. Cleanup outcomes likewise each have a distinct symbol
  and a text status.
- **Colour-blind map palette.** Settings > General > Storage map colours offers "Colour-blind friendly", built
  on the Okabe–Ito palette (see `docs/design/design-system.md`). On its yellow, labels switch to dark text.
- **Colour is not the only carrier in the map.** Blocks carry their name and size as text when large enough;
  the footer and the list give the same information as text; the legend names each category.
- Light and dark appearances are both supported, with separate colour values for each.

### Motion

The application reads `accessibilityReduceMotion`. The only explicit animation, the 0.25-second transition
when the storage map changes folder, is not performed when Reduce Motion is on. There is no parallax, no
auto-playing animation and no animated progress beyond the system progress indicators.

### Density and size

- Settings > General > List density: Comfortable or Compact. In 1.0.0 it affects the Large Files list (row
  padding, icon size, and whether the path line is shown).
- Text uses system text styles. The minimum window size is 980 by 620; the layout is checked by a UI test at
  that size and at 1800 by 1100.

### Language

English and Canadian French, following the system language. Numbers, sizes and dates are formatted for the
current locale.

### Wording

Messages state what happened and what can be done, in plain sentences, without codes. Errors from macOS are
attributed to macOS. See `docs/design/brand-guidelines.md`.

## Not verified

None of the following has been done. Until it is, the statements above describe code, not a tested experience.

- **No VoiceOver session with a real user.** Nobody who relies on VoiceOver has used the application. Reading
  order, verbosity of the combined rows, rotor navigation and the usability of the map's list equivalent are
  unverified.
- **No Voice Control testing.** Whether every control can be reached by name or by number overlay is unknown.
- **No Switch Control or Full Keyboard Access testing.** The keyboard shortcuts above exist; a complete pass
  with Full Keyboard Access on, including the storage map and the preview sheet, was not recorded.
- **Contrast was not measured with an instrument.** The colour pairs were chosen by eye. No contrast ratio was
  computed for text on surfaces, for white labels on map colours, or for the tertiary text colour. Some
  combinations may fall below common thresholds.
- **The colour-blind palette was not tested with colour-blind users or a simulator.** It follows a published
  palette, extended with three values of the author's choosing.
- **Increase Contrast, Reduce Transparency and Differentiate Without Colour** are not read by the code. The
  Settings window says that contrast follows the system setting; this holds for system controls and
  materials, but the custom colour tokens and the map do not change. Not verified in either state.
- **Larger text.** macOS has no application-level Dynamic Type; behaviour with a larger system text size was
  not checked, and the labels painted in the map are fixed at 10.5 and 9.5 points.
- **macOS 15 and 26, and Intel Macs,** were not run at all, so nothing is known about assistive technology
  behaviour there.
- **French with VoiceOver** (pronunciation of mixed English product terms) was not checked.

The UI tests locate elements by accessibility identifier. That shows the elements exist in the accessibility
tree; it does not show that they are well described.

## Known gaps

| Gap | Detail |
|---|---|
| Map zoom and pan are pointer-only | Pinch to zoom and drag to pan have no keyboard equivalent. Drilling down through the list reaches the same content |
| Hover details | The footer shows details of the block under the pointer; for keyboard users it shows the selected item instead |
| Map blocks are not individual elements | By design; the list is the equivalent, with the limits stated above |
| Sections 10 to 13 have no shortcut | Trash, History, Actions, Reports |
| Rescan has no shortcut | ⌘R scans the home folder, not the last scanned location |
| Density applies to one list | Other lists use fixed spacing |
| Custom colours ignore Increase Contrast | See above |
| Similar-image comparison is visual | Groups are presented as thumbnails with dimensions, size and path as text; no image description is generated |
| Typed confirmation | Emptying the Trash requires typing `DELETE`, in English in both languages |

## Reporting a problem

Accessibility problems are treated as defects. Contact: contact@spboucher.ai
