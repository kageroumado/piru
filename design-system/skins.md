# Skins

A skin is a named visual identity: a palette, a surface treatment, and a type
design. It plugs into the colour system in `color/` rather than beside it.

## The shape of it

| Piece | Where | What it does |
|---|---|---|
| `Skin` | `Shared/Skin/Skin.swift` | The registry. One `case` per skin; each accessor switches on `self` and returns an Xcode-generated catalog symbol for that skin's namespace. Also `SkinSurface`, `SkinColorScheme`, `SkinDefaults`. |
| `SkinStore` | `Piru/Data/Services/SkinStore.swift` | `@Observable @MainActor` singleton. Holds the active skin + the light/dark override, persisted to the app-group suite (`SkinDefaults`). |
| `Theme` | `Piru/Theme.swift` | The five tokens views already use (`accent`, `secondaryLabel`, `background`, `cardBackground`, `inputBackground`) — now computed through `SkinStore.shared.current`. |
| `ThemedBackground` / `CardBackground` / `themeCard` | `Piru/Theme.swift` | The card treatment, branching on `Skin.surface`. |
| `SkinnedRoot` | `Piru/Theme.swift` | Wraps `ContentView` at the root: `tint`, `fontDesign`, `preferredColorScheme`. |
| Appearance settings | `Piru/Views/Settings/AppearanceSettingsView.swift` | The picker. |

**Why computed, not injected.** `Theme.*` has ~1,000 call sites. Observation tracks
a read of `SkinStore.shared.current` wherever it happens inside a `body`, so a
computed `static var` makes every one of them skin-reactive with no edits.
An environment key would have meant touching each site for nothing.

## Colours: a skin is a catalog namespace

Skin colours are generated the same way as every other token — add them to
`color/palette-generator-input.json` under `skin/<id>/…`, run
`generate_colorsets.py`, and Xcode emits `Color.Skin.<Id>.Surface.card` etc.
The generator already turns slashes into real `provides-namespace` folders.
Light, dark and high-contrast slots per skin are the catalog's job, exactly as
for the default; `ColorContrastTests` gates each skin against the same floors.

The default skin (`.piru`) reads the un-namespaced tokens the app shipped with.
`AccentColor` stays hand-authored and untouched.

Author in Oklch, never hex (root `CLAUDE.md`). A skin's `text` and `accent`
roles stay split: a colour that is a fine mark can still fail as small copy
(the whole reason `semantic/*/text` exists). Measure with `colorimetry.py`.

## What a skin never touches

- **Graphs.** The timeline spine, sparklines and PK charts read `series.color`
  and `Color.primary` with their own opacities and never see `Theme`. Keep it
  that way — a skin dresses the cards around a graph, not the graph.
- **L2 encoding scales** (routes, dose tiers, phases, categories) and
  **L3 identity** (per-substance colours). They carry meaning or belong to the
  user; only the chrome around them changes.
- **Copy.** Strings stay Piru's voice in every skin.

## Adding a skin

1. `Skin`: add the case, its name/tagline, `surface`, `fontDesign`.
2. Palette: add `skin/<id>/surface/{background,card,input}`, `skin/<id>/text/secondary`,
   `skin/<id>/accent`, and any `skin/<id>/semantic/*` overrides to
   `palette-generator-input.json`; regenerate; wire the accessors.
3. `ColorContrastTests`: add the skin's measured card colours to the surface
   table so its tokens are gated.
4. Nothing else. The picker lists `Skin.allCases`.

## Form: `Piru/Views/Components/SkinChrome.swift`

Colour is `Theme`'s; shape, stroke and shadow are this file's. Three primitives,
each branching on `Skin.surface`:

- `skinButtonStyle(_:)` — every standalone action. Glass skins keep
  `.glassProminent` / `.glass`; edged skins get `EdgedButtonStyle`, a sticker
  whose press sinks onto its hard shadow. Never write `.buttonStyle(.glass…)`
  directly again; the modifier is the one place the split lives.
- `skinChip` / `skinOutlineChip` — the badge grammar under `capsuleChip`,
  `heroChip`, `ROAPill`. A capsule tinted at 0.10 under glass (never higher —
  a colour on a tint of itself asymptotes around 4.5:1 in dark mode), a stroked
  square on the input surface under an edge. Takes a text style, not a `Font`,
  so the edged branch can set the skin's label face.
- `SkinSticker` — a group's label (the timeline day header). Material capsule,
  or the site's tab: accent fill, stroke, hard shadow in the eyebrow colour.

## Type: `Piru/Views/Components/SkinType.swift`

Two roles. **Display** (`largeTitle` … `headline`, and UIKit navigation titles
via the appearance proxy) takes `Skin.typeface.display`; **label** (chips,
eyebrows) takes `Skin.typeface.label`. Body copy is always the system face —
the CJK body fonts a skin might want run 4–9 MB per weight, and the app ships in
three scripts.

Fonts are built through UIKit (`UIFontDescriptor` family + weight, scaled by
`UIFontMetrics`) and wrapped, never `Font.custom`: on device, `Font.custom` and
`UIFont(name:)` both missed this variable font's named instances on first
render while the descriptor resolved them.

`Skin.fontDesign` (a root `.fontDesign`) is **exclusive with custom faces**: it
re-derives every SwiftUI font in the tree as a system font of that design,
wrapped custom faces included, so only the UIKit nav bar would show the display
face. A skin picks one or the other; `SkinTypeTests` enforces it.

Call sites say `.font(.piru(.headline))`; the helper hands back the plain system
style for non-display styles and for skins without a display face, so it is safe
anywhere. The few hand-sized hero titles (Library card titles, the substance
hero, the inventory readout) use `.font(.piru(size:weight:design:relativeTo:))`
instead of `.system(size:)`. Custom fonts are scaled by `UIFontMetrics` for a style, so
Dynamic Type keeps scaling them. Families live in `Piru/Fonts/` with their OFL
texts and are declared in `Piru/Info.plist` (`UIAppFonts`); `SkinTypeTests`
checks the bundle actually registers what each skin names.

## Widgets

`PiruWidget/WidgetColors.swift` resolves through `Skin.current`, which in the
extension falls back to the persisted app-group choice, and `SkinStore.setSkin`
reloads widget timelines so they re-render on a change. The Live Activity is
untouched: it draws per-substance colours (L3) on the system's Lock Screen
surfaces and carries no skin chrome.

## Decorations: `Piru/Views/Components/SkinBackdrop.swift`

The chaos layer. Every screen root says `.skinBackdrop()` instead of
`.background(Theme.background)`; for a skin whose `Skin.decorations` is
non-nil (and the Appearance toggle is on) that is the background colour plus a
seeded starfield, a warm glow at the top, and a field of glyph stickers on a
jittered grid — roughly one per 110pt cell, a few cells left empty — that bob,
sway, twinkle (sparkles) and turn (sparkles, flowers, crosses), all from one
`TimelineView` clock. Glyph colours are the skin's own tokens. Positions are
seeded by screen size, so a screen is stable across appearances. Blinkies were
tried and dropped: text in the background competes with text in the content.
Motion stops under Reduce Motion. Graph code that *fills* with
`Theme.background` (dot rings, fades) is untouched — it never went through
`.background()`.

## Later

- Per-file section headers (eyebrows) are private today; a shared component
  would let the label face reach them.
- The remaining `.font(.system(size:))` sites are numbers, icons, and export
  renderers, which stay on the system face by design.
- Title sparkles: navigation titles are UIKit-drawn, so the site's ✦ stickers
  on the title have no SwiftUI hook yet.
- A **starfield skin** (Astrelia-inspired night sky: steel-blue ground, a
  dense twinkling starfield, ✦ ✧ ⋆ ☾ stickers in gold/white/blue) on the same
  decoration machinery — after kagerou.glass. Tokens are in the project memory.
