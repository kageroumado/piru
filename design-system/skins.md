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

## Later

- Chrome components (`GlassPillButton`, chips, badges, the timeline day capsule,
  the dock) read `Skin.surface` and pick their form.
- A typography layer (`Font.piru(_:)`) so a skin can bundle custom families;
  until then `fontDesign` reshapes the system faces app-wide.
- Widgets read `SkinDefaults.storedSkin()` and resolve the same catalog symbols.
