<!-- ORIX Clean / File: docs/design/design-system.md / Author: Simon-Pierre Boucher / Contact: contact@spboucher.ai -->
# Design system

The tokens and components that the application actually uses. Everything here is taken from
`App/Sources/DesignSystem/Tokens.swift` and `Components.swift`; a value that is not in those files is not a
token.

## Principles

- **System first.** Standard SwiftUI controls, system fonts and text styles, SF Symbols, system materials
  (`.bar`, `.regularMaterial`). The design system adds colour roles, spacing, radii and a small set of
  components; it does not restyle controls.
- **Numbers are content.** Sizes and counts use monospaced digits so columns do not shift.
- **Meaning never depends on colour alone.** Risk levels have distinct shapes; bars always have the value as
  text next to them.
- **Calm.** No alarm styling; a banner states a fact and offers one action.

## Colour tokens

All colours are defined as light and dark pairs in sRGB through `Color(light:dark:)`, which resolves against
the current appearance (`.darkAqua` or `.aqua`).

| Token | Light | Dark | Role |
|---|---|---|---|
| `canvas` | `#F4F5FA` | `#0A0D18` | Window background behind grouped content; map background |
| `surface` | `#FFFFFF` | `#141828` | Cards, progress lines |
| `surfaceRaised` | `#FFFFFF` | `#1B2034` | Folder frames in the storage map |
| `hairline` | `#E3E6EF` | `#262C44` | Borders, bar tracks, small capsules |
| `textSecondary` | `#5A6072` | `#9AA2B8` | Secondary text |
| `textTertiary` | `#8A90A2` | `#6B738C` | Tertiary text, unchecked boxes |
| `accent` | `#0A9E96` | `#2DD4BF` | ORIX Clean accent ("clear water" teal); also the asset-catalogue `AccentColor` and the window tint |
| `accentSecondary` | `#5B5BF0` | `#8484FF` | ORIX family indigo; banners, folder glyphs |
| `low` | `#16A34A` | `#4ADE80` | Low risk |
| `review` | `#D97706` | `#FBBF24` | Review required; low free space on a volume bar |
| `high` | `#DC2626` | `#F87171` | High risk; the permanent-delete button |

`brandGradient` is a linear gradient from `#2DD4BF` through `#06B6D4` to `#5B5BF0`, top-leading to
bottom-trailing. Primary text uses the system primary colour.

## Spacing and radii

| Scale | Values (points) |
|---|---|
| `ORIX.Space` | `xs` 4, `s` 8, `m` 12, `l` 16, `xl` 24, `xxl` 32 |
| `ORIX.Radius` | `s` 6, `m` 10, `l` 14 |

Cards use radius `l` with continuous corners, banners and progress lines `m`, thumbnails `s`.

## Typography

There are no custom type tokens. The components use system text styles: `largeTitle` and `title3` in
onboarding, `title2` for sheet titles and stat values, `title3` semibold for section titles, `headline`,
`callout`, `caption` and `caption2`. Sizes, counts and dates add `.monospacedDigit()`. The storage map draws
labels at fixed sizes (10.5 and 9.5 points) because they are painted in a `Canvas`.

## Density

`Density` has two cases, stored under the `density` user default and chosen in Settings.

| Case | `rowPadding` |
|---|---|
| `comfortable` (default) | 7 |
| `compact` | 3 |

In 1.0.0 the setting is read by the Large Files list only (`LargeFilesView`), where compact rows also use a
smaller file icon (18 instead of 26 points) and omit the path line; the other lists use fixed spacing.

## Risk: colour and shape

| Risk | Title | Colour token | SF Symbol | Shape |
|---|---|---|---|---|
| `low` | Low risk | `low` | `checkmark.circle.fill` | circle with a check mark |
| `review` | Review required | `review` | `eye.circle.fill` | circle with an eye |
| `high` | High risk | `high` | `exclamationmark.triangle.fill` | triangle |

`RiskBadge` shows the symbol and the title in a capsule tinted at 13 % of the risk colour; its accessibility
label is the title. Deletion outcomes in the results sheet follow the same idea, each with its own symbol:
`trash.circle.fill`, `xmark.bin.circle.fill`, `arrow.uturn.right.circle`, `exclamationmark.octagon.fill`,
`hand.raised.circle.fill`.

## Storage map palettes

`MapPalette` assigns a base colour to each `FileCategory`. Two palettes exist; the choice is stored under
`mapPalette`.

| Category | Symbol | ORIX | Colour-blind friendly |
|---|---|---|---|
| Video | `film` | `#8B5CF6` | `#CC79A7` |
| Audio | `waveform` | `#EC4899` | `#D55E00` |
| Images | `photo` | `#F59E0B` | `#E69F00` |
| Archives | `archivebox` | `#64748B` | `#7F7F7F` |
| Disk images | `externaldrive` | `#0EA5E9` | `#56B4E9` |
| Installers | `shippingbox` | `#EF4444` | `#B34700` |
| Documents | `doc.text` | `#22C55E` | `#009E73` |
| Code | `chevron.left.forwardslash.chevron.right` | `#06B6D4` | `#0072B2` |
| Applications | `app.badge` | `#6366F1` | `#F0E442` |
| Other | `doc` | `#94A3B8` | `#A9A9A9` |

The colour-blind set is built on the Okabe–Ito palette: seven of its eight colours are used as published
(`#CC79A7`, `#D55E00`, `#E69F00`, `#56B4E9`, `#009E73`, `#0072B2`, `#F0E442`). Okabe–Ito black is not used;
three values were added for the remaining categories (two greys, and a darker orange `#B34700` for installers).

How the map applies a palette (`StorageMapView.draw`):

- each level of depth darkens the base colour by 3.5 %, up to seven levels;
- plain folders that are too small to open are drawn in `accentSecondary` at 55 % opacity, aggregated
  "smaller items" cells in `textTertiary` at 45 %;
- labels are white, except on the yellow Applications colour of the colour-blind palette, where they are
  near-black;
- when a search is active, non-matching cells drop to 22 % opacity;
- hover is a white outline with a dark inner line, selection a dashed accent outline, and cells in the cleanup
  selection a dashed white outline.

The legend in the map footer shows a swatch and the category name for all ten categories.

## Components

| Component | Purpose | Notes |
|---|---|---|
| `Card` | Grouped content | `surface` background, `hairline` border, radius `l`, padding `l` |
| `SectionTitle` | Title and optional subtitle | Combined accessibility element with the header trait |
| `RiskBadge` | Risk level | See above |
| `SizeText` | A byte count | `ByteFormat.string`, monospaced digits |
| `ProportionBar` | A fraction | Capsule track and fill, minimum 2 points wide; hidden from accessibility because the value is always given as text beside it |
| `EmptyState` | Nothing to show yet | Symbol, title, message, optional prominent action |
| `InfoBanner` | A fact and one action | `accentSecondary` at 8 % background; never styled as an alarm |
| `ProgressLine` | A running analysis | Title, determinate or indeterminate bar, detail line, optional Cancel |
| `FileIcon` | Finder icon of a path | `NSWorkspace.icon(forFile:)`, hidden from accessibility |
| `Thumbnail` | Quick Look thumbnail | `QLThumbnailGenerator`, falls back to the Finder icon |
| `PathText` | Parent folder of a path | Home abbreviated to `~`, middle truncation, full path in the tooltip |
| `FileMenu` | Context menu for any file | Reveal in Finder, Quick Look, Copy Path |
| `Checkbox` | Selection for cleanup | Plain button with a labelled toggle trait and a Selected / Not selected value |
| `StatTile` | A labelled figure | Combined accessibility element |

## Layout constants

| Element | Value |
|---|---|
| Main window | minimum 980 by 620, default 1280 by 820, unified toolbar |
| Sidebar | 190 to 260 points, ideal 212 |
| Cleanup preview sheet | minimum 820 by 600 |
| Results sheet | minimum 780 by 520 |
| Settings window | 640 by 430 |
| Map side list | 260 to 460 points |

## Appearance

Light and dark are both supported through the token pairs. Settings offers Match System, Light and Dark
(`appearance` default); the launch argument `-ORIXAppearance` overrides it for tests and screenshots.

## Not in the system

- No custom fonts, no custom control styles, no animation tokens. The only explicit animation is the 0.25 s
  transition when the map changes folder, and it is disabled under Reduce Motion.
- No high-contrast token set: contrast changes rely on system controls and materials.
- Contrast ratios of the token pairs have not been measured with an instrument (see `docs/ACCESSIBILITY.md`).
