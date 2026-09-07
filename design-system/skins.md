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

## The skins

| Skin | Source | Surface | Type | Scene |
|---|---|---|---|---|
| Piru | the app's own | glass | system | none |
| ely.pink | `~/Developer/website main` | edged, dashed inset, hard drop | Fredoka + DotGothic16 | stickers |
| Tsuki | `~/Developer/Tsuki` | soft (hairline + lavender glow) | `.rounded` | night sky, sparse, sleeping moon |
| Starfield | `~/Developer/website main/astrelia` | edged | Fredoka | night sky, dense, gold |
| Jellyfish | rocuronium's jellyfish | soft (hairline + cyan glow) | `.rounded` | underwater |
| Graphite | — | glass | system | none — a muted skin |
| Linen | — | paper | system | none — a muted skin |
| Slate | — | soft (slate glow) | system | none — a muted skin |
| Paper Garden | `~/Developer/Origami` + `~/Developer/Kaze` | paper (grain, ink hairline, no shadow) | Fraunces | raked sand around stones, sakura, fireflies at night |
| Hotaru | `~/Developer/Hotaru` | soft (lime glow) | system | fireflies, fog, a tree line, an aurora |
| Yuki | `~/Developer/Yuki` | soft (periwinkle glow) | `.rounded` | snow, frost at the corners |
| Hebi Arcade | `~/Developer/Hebi` (Neon City) | neon (phosphor stroke + glow) | Press Start 2P (scaled .72) | a perspective grid, pixel stars, a snake, scanlines |
| Kumo | `~/Developer/Kumo` | frosted (translucent, hairline, highlight) | system | a sky by the real clock and season |

Light modes for Tsuki, Starfield and Jellyfish are invented — a moonlit
lavender day, a dawn sky, a shallow lagoon — since their sources are dark
only; every one is gated by `ColorContrastTests` like the rest.

## Adding a skin

1. Palette: seed `skin/<id>/…` as hex in `color/build_skin_palettes.py` — it
   gates text 4.5:1 and marks 3:1 against the skin's own card and writes
   Oklch into `palette-skins.json`; then `build_generator_input.py` and
   `generate_colorsets.py`.
2. `Skin`: add the case, its name/tagline, a `SkinPalette` from the generated
   symbols, `surface`, `fontDesign` / `typeface`, `decorations`.
3. `translate_catalog.py`: the name and tagline.
4. Nothing else. `ColorContrastTests` iterates `Skin.allCases`; the picker
   lists them.

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

Six surfaces: `.glass` (the default's material — Piru, Graphite), `.edged`
(solid, stroke, hard offset shadow — ely.pink, Starfield), `.soft` (solid,
1pt hairline at low opacity, a coloured glow, never a black shadow — Tsuki,
Jellyfish, Hotaru, Yuki, Slate), `.paper` (matte, ink hairline, no shadow, a
grain tile — Paper Garden, Linen), `.neon` (translucent dark fill, 1.5pt phosphor stroke, outer
glow, inner highlight — Hebi Arcade) and `.frosted` (translucent white,
white hairline, a top highlight, no material — Kumo, so the sky shows
through). Buttons: `SoftButtonStyle` (glow brightens on press),
`PaperButtonStyle` (fill darkens), `NeonButtonStyle` (the tube fills).
Textures come from `SkinTextures`: a 96pt grain tile and a 1×3 scanline tile
rendered once per appearance and painted by tiling, one fill per frame.

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

Every screen root says `.skinBackdrop()` instead of
`.background(Theme.background)`; for a skin whose `Skin.decorations` is
non-nil (and the Appearance toggle is on) that is the background colour plus
**one `Canvas` on one `TimelineView` clock** (30 fps, paused under Reduce
Motion) that draws the skin's `SkinScene` and then its glyph stickers. One
draw pass per frame per screen, however much is in it — the phone froze once
when this was many animated views instead.

Everything is a pure function of `(size, time)` from a seeded RNG: a screen
looks the same every time, and nothing keeps a history buffer. Rules from
rocuronium's jellyfish: glows are radial gradients that reach zero alpha at
their edge, never `.blur`/`.shadow` filters, and over dark water they
composite `plusLighter` (additive) so a colour reads as emitting, not paler.

- `.stickers` (ely.pink): warm glow, dotted ground, the full glyph field on a
  jittered grid (~one per 110pt cell) that bobs, sways, twinkles and turns.
  Blinkies were tried and dropped: text in the background competes with text
  in the content.
- `.nightSky` (Tsuki, Starfield): nebula glows, a haloed starfield with
  per-star twinkle and drift in three size tiers (the brightest get four
  points), Tsuki's sleeping crescent moon with a breathing glow, a thinner
  glyph field.
- `.underwater` (Jellyfish): a night dive in the dark (faint soft-edged
  moon rays, caustic ripples near the surface, depth fog, blooms) and a
  sunlit deep in the light; twinkling plankton, rising bubbles, a vignette so
  the edges read as glass; and the cast of `SkinJellies.swift` swimming up —
  rocuronium's five mascots (Remi, Bitjelly, Koko, Aurora, Sparkler, ported
  with permission; their colours are their own hex palette, art rather than
  UI roles) and Piru's own jelly. Each is a pure function of `(time,
  motion)`: the bell pulses on rocuronium's contraction curve, tentacles
  *lag* the bell by evaluating the swimmer's closed-form motion in the past,
  and roots are sampled off the hem the bell is drawing that frame, so
  nothing floats free. Species are cast by seeded draw; the small ones are
  far, dimmer, faceless, and sink into the fog.
- Tsuki's moon is the app icon's own crescent (`skin/tsuki/moon` imageset,
  lifted from the icon with its glow and face by
  `build_skin_palettes.py`'s sibling scratch script; the mask is the fitted
  outer and bite circles), drawn by the canvas with a breathing halo.

- `.paper` (Paper Garden): Origami's washi gradient and grain, Kaze's fine
  rake bending around two stones with concentric rings, the stones with
  their gradient and moss, sakura petals on Kaze's fall, its fireflies (with
  their blink keyframes) after dark, its vignette floored at .5.
- `.fireflies` (Hotaru): the shaders' ground, fog and tree line; 120
  fireflies with the shader's blink (`pulse²·flicker`), size and two-term
  glow, additive; three aurora ribbons on its wave cycling green → cyan →
  purple → pink. By day: pollen motes and morning mist.
- `.snow` (Yuki): its `SnowfallView` numbers in closed form (60 flakes,
  speeds, drift, depth fade), frost blooms and crystals at the top corners,
  a drift along the top edge.
- `.arcade` (Hebi): a perspective floor scrolling toward the viewer in the
  wall and border colours, 2×2 pixel stars, a snake walking a seeded random
  walk on a 12pt grid one step every .16 s with the game's glow ladder, its
  food blinking ahead of it, scanlines and a vignette.
- `.sky` (Kumo): `SceneClock` reads the wall clock each frame; the sky is
  Kumo's night / day / sunset stops lerped through dawn (5–7) and dusk
  (17–20), light mode kept to the day family and dark to the night family;
  a sun or moon on an arc; its 80 stars; its three cloud layers on their own
  speeds; snow in Dec–Feb and rain in Mar–Apr and Oct–Nov with its particle
  numbers; the night aurora band.

**Muted skins** (Graphite, Linen, Slate) have `decorations == nil`: palette,
surface and type only, nothing moving, for people who want none of it. Two
night skies never share a star map: `SkinNightSky.seed` differs per skin
and Starfield adds a Milky Way band.

**Parallax.** `SkinMotion` low-pass filters device gravity into a resting
reference and reports the deviation as a tilt; every layer slides opposite
the tilt scaled by its depth (rays far, small jellies farther than big ones,
bubbles by size, stars by tier, the moon nearest) — the window into the
aquarium. Zero on the simulator, on the Mac, and under Reduce Motion; the
motion manager runs only while a backdrop is on screen.

Graph code that *fills* with `Theme.background` (dot rings, fades) is
untouched — it never went through `.background()`.

Two more flourishes live in the same file, both keyed off `Skin.decorations`
and the Appearance toggle: `.skinFrameCorners()` puts the site's ✧ / ♡ pair on
a glance card's top-right and bottom-left edges (glance cards only — on a
dense row they would collide with text), and `.tapTrail()` at the root spawns
a ♡ that floats up and fades from every tap (a simultaneous gesture, so
buttons and scrolling never see it). `.skinHeroTitle()` is the site's `h1`
for a SwiftUI-drawn title: fill in the mark colour, a near-black outline
(eight zero-radius shadows — SwiftUI cannot stroke text) and a hard dark-wine
drop. The UIKit large title gets the same treatment through the appearance
proxy (`Skin.titleOutline`, tokens `skin/<id>/title/{stroke,shadow}`).

## The edged card, in full

Under `.edged`, `themeCard` draws: the hard offset shadow, the solid card
fill, the stroke, and the site's `.frame::before` — a dashed inset border in
`Skin.cardInsetDash` (`themeCapsule` skips the dash; a dash inside a pill
reads as a broken ring). The Library / Search gradient tiles
(`FamilyGradientCard`) get the stroke and hard shadow too, and every small
tinted chip drawn outside the chip primitives takes `skinChipShape()` — a
capsule, or the skin's 3pt square — so nothing on an edged screen is still a
pill. `themeCapsule` (search fields) squares to the input radius.

**A skin never changes a container's shape.** Cards keep the radius their
caller asked for (22 for cards, 16 for the timeline envelope, 18 for tiles),
so what nests inside keeps nesting; skins change fill, edge and shadow only.
Chips are not containers and may square.

**Contrast is gated on the page background too.** Hour labels, gutter marks
and eyebrows sit on the background, not a card, so `build_skin_palettes.py`
pushes every text role until it clears 4.5:1 on both surfaces and
`ColorContrastTests` checks both.

What stays flat: `List` / `Form` sections. Rows share the system's clipped
section container, so a per-row stroke would be cut at every corner and a
section-level edge has no hook. They keep the solid card fill only.

## Screenshots without tapping

DEBUG builds accept `-piruRoute <piru://url>` as a launch argument and land on
that screen (after `SubstanceStore.ensureAllLoaded()`), because `simctl
openurl` is stopped by the untappable "Open in Piru?" sheet. Combine with
`AppNavigator.selectedTab` in the standard defaults and the app-group `skin`
key to screenshot any screen in any skin.

## Later

- Per-file section headers (eyebrows) are private today; a shared component
  would let the label face reach them.
- The remaining `.font(.system(size:))` sites are numbers, icons, and export
  renderers, which stay on the system face by design.
- Title sparkles: navigation titles are UIKit-drawn, so the site's ✦ stickers
  on the title have no SwiftUI hook yet.
- The next batch from the user's apps: Shrine, Mochi, Shizuka, Hoshi, Hanabi.
- kagerou.glass, the other developer's site, as a skin.
