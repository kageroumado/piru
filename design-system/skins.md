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
| Paper Garden (shelved, `Skin.shelved`) | `~/Developer/Origami` + `~/Developer/Kaze` | paper (grain, ink hairline, no shadow) | Fraunces | raked sand around stones, sakura, fireflies at night |
| Aurora | `~/Developer/Hotaru` | soft (lime glow) | system | fireflies, fog, a tree line, an aurora |
| Yuki | `~/Developer/Yuki` | soft (periwinkle glow) | `.rounded` | snow, frost at the corners |
| Hebi Arcade | `~/Developer/Hebi` (Neon City) | neon (phosphor stroke + glow) | Press Start 2P (scaled .72) | a perspective grid, pixel stars, a real snake game replayed from a seed, scanlines |
| Kumo | `~/Developer/Kumo` | frosted (translucent, hairline, highlight) | system | a sky by the real clock and season |
| dose.wiki | https://dose.wiki (partner; their CSS tokens, hue 326/318) | frosted (fuchsia hairline + highlight) | Saira (scaled .94) | their page halos and molecule ring, one node pulse |
| Selenia | `~/Developer/Ecliptica` (the folder keeps the pre-rename name) | frosted (gold hairline + glow) | system **serif** | an engraved chart wheel turning under a still dome |
| Hanabi | `~/Developer/Hanabi` (the co-op card game) | soft (periwinkle glow) | `.rounded` | a festival night: a star field, rockets, bursts in the five suits |
| substance.wiki | https://substance.wiki (partner; their black ground, paper ink, cyan and signal lime) | edged (1pt hairline, no shadow, `--radius: 0`) | system | none — nothing moving, by their design |

Hanabi's five card suits **are** its semantic pairs — red → danger, yellow →
caution, green → success, blue → info — the move dose.wiki makes with its
dose-tier ramp, so a Piru warning reads in the family a player already knows.
Its accent stays the game's own blue rather than the 花火 wordmark's gold: the
gold measures 0.053 Oklab dE from the yellow suit, while the blue holds 0.131
from the blue suit. Light mode gates the accent and the blue suit onto the same
colour (0.03 dE) unless the suit is seeded a step deeper, which is why its
`semantic/info` seeds differ by mode.

**A second Astrelia was built and deleted (2026-09-22).** The iOS app has its
own design language — near-black and periwinkle with 1px rings, against the
site page's lit steel-blue and 2.5px sticker borders — so it looked like a
distinct skin on paper. It was not: Starfield already holds the starry ground,
and their accents measure only 0.093 apart. Palette alone does not make a
second skin out of one product. Note for whenever a skin is dropped:
`SkinProducts.all` filters the catalog, so removing one also means removing
its product from `StoreKit/Skins.storekit` — `SkinShopTests` asserts the two
agree and catches it immediately.

**If you want a Metal shader in a scene, two things are already known.** A
SwiftUI `colorEffect` can live *inside* the backdrop's existing
`TimelineView`, which means no second clock and `SkinPower` still governs
every frame — that part works, and it is the only way a shader belongs here.
What sank the attempt was the noise domain: on a tall phone `aspect` is about
0.46, so an `x` scaled by it spans under one unit, and any noise frequency in
the single digits gives two or three cells across the width. The field goes
effectively one-dimensional and paints parallel diagonal lines — it reads as
scratched glass. The fix is frequency, not opacity.

Hanabi's five card suits **are** its semantic pairs — red → danger, yellow →
caution, green → success, blue → info — the move dose.wiki makes with its
dose-tier ramp, so a Piru warning reads in the family a player already knows.
Its accent stays the game's own blue rather than the 花火 wordmark's gold: the
gold measures 0.053 Oklab dE from the yellow suit, while the blue holds 0.131
from the blue suit. Light mode gates the accent and the blue suit onto the same
colour (0.03 dE) unless the suit is seeded a step deeper, which is why its
`semantic/info` seeds differ by mode.

**Selenia's accent is not the colour its own `Theme` uses.** Selenia and the
Astrelia app were both ported from Astrolabe and share periwinkle `#8FB8FF`,
so a faithful seed would have landed on a colour two of the author's apps
already wear. Selenia takes the icon's engraved gold `#E3C37C` instead — its
own astrology tint, and 0.214 from that periwinkle. Its semantics are its four
elements, with one substitution: air (`#F2D980`) sits 0.062 from the gold, so
caution takes fire and danger takes the chart's hard-aspect red.

Light modes for Tsuki, Starfield, Jellyfish, Hanabi and Selenia are invented —
a moonlit lavender day, a dawn sky, a shallow lagoon, a daytime festival and
the chart engraved on vellum — since their sources are dark only; every one is gated by `ColorContrastTests` like the rest.

## Surfaces are closed

Six surfaces exist (glass, edged, soft, paper, neon, frosted) and that is
the set: every surface touches `ThemedBackground`, `CardBackground`,
`themeCapsule`, the chips, the buttons, the Library card edge and the session
envelope, and verifying a new one across all of that is more than a skin is
worth. A new skin picks one of the six. (Decided 2026-09-08.)

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
- `.fireflies` (Aurora, from Hotaru — the case and raw value keep the app's
  name, only the picker says Aurora): the shaders' ground, fog and tree line; 120
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
- `.molecule` (dose.wiki): the site's four page halos breathing on slow
  phases (`drawGlows`), their logo as a template image tinted with the skin
  ink at 5–7% behind the right half of the screen, and one bloom walking the
  ring's six outer vertices. The semantic pairs are their dose-tier ramp
  (threshold green, light blue, moderate amber, heavy red), so a Piru warning
  reads in the family a dose.wiki reader knows. The logo is their mark: it
  ships only with their okay.
- `.sky` (Kumo): `SceneClock` reads the wall clock each frame; the sky is
  Kumo's night / day / sunset stops lerped through dawn (5–7) and dusk
  (17–20), light mode kept to the day family and dark to the night family;
  a sun or moon on an arc; its 80 stars; its three cloud layers on their own
  speeds; snow in Dec–Feb and rain in Mar–Apr and Oct–Nov with its particle
  numbers; the night aurora band.

- `.fireworks` (Hanabi): the game's menu — its static 50-star field (white
  at 0.06–0.30) under a thinned drift of its rising sparks, then four rocket
  slots. Each slot runs its own period; where a flight launches, which suit it
  is and which of `FireworkScene`'s three shapes it takes (circle, star on long
  arms, double ring) are drawn from an RNG seeded on `(slot, cycle)`, so a
  flight is a pure function of the clock and nothing is kept between frames.
  The rocket rises on an eight-node fading trail; the burst is the closed form
  of a particle emitter — radius eases open, gravity pulls the tail down, alpha
  falls off a cube, and a white core blooms for the first third.
  **Sparks are drawn as short radial streaks, never as dots** — a ring of dots
  reads as a dotted circle, which is exactly what the first device look showed.
  The sparks the menu tints at a random hue are suit-coloured here instead: a
  skin never invents a colour that is not in its palette.

- `.ephemeris` (Selenia): `ChartWheel.swift` as a backdrop, drawn as a whole
  plate — six concentric rules, **a full 360° of degree marks** with every
  fifth one long, twelve sign sectors carrying their own zodiac glyph and an
  element tick, the seven classical planets each at its own longitude on its
  own period, and the aspect chords breathing on long phases, all over the
  still dome `CelestialSphereView` turns and a bloom that lights the plate
  from its middle. One revolution every twelve minutes: slow enough to read as
  still, which is what an instrument should do.
  - The 360 marks are **one `Path` with 360 subpaths**, so the whole ring is a
    single stroke call. A wheel that stops short of the full circle stops
    being an instrument, and drawing them one at a time would not be worth it.
  - Type on the wheel comes from ``WheelAtlas``, the same trick ``GlyphAtlas``
    uses: `Text` cannot cross into the nonisolated renderer, so the twelve
    signs and seven planets are baked to images on the main actor once per
    appearance and blitted. **Every symbol carries U+FE0E**, the text
    presentation selector — without it the zodiac codepoints default to emoji
    on iOS and the wheel comes back with twelve filled purple tiles on it.

**Muted skins** (Graphite, Linen, Slate) have `decorations == nil`: palette,
surface and type only, nothing moving, for people who want none of it.
substance.wiki is `nil` for a different reason — their site has no motion, so
a scene would be Piru's invention rather than theirs. Two
night skies never share a star map: `SkinNightSky.seed` differs per skin.

**Parallax.** `SkinMotion` low-pass filters the accelerometer into a gravity
estimate, then into a resting reference, and reports the deviation as a tilt;
every layer slides opposite the tilt scaled by its depth (rays far, small
jellies farther than big ones, bubbles by size, stars by tier, the moon
nearest) — the window into the aquarium. Zero on the simulator, on the Mac,
and under Reduce Motion; the accelerometer runs at 20 Hz only while a
backdrop is on screen. Never the fused `deviceMotion` feed: it keeps the
gyroscope powered for as long as the skin is showing, and the parallax only
needs which way is down.

**What a frame costs.** Measured on the native macOS build idling on the
Journal under Jellyfish (Instruments, SwiftUI template): the scene's own
drawing is about a third of each frame; the SwiftUI transaction around it,
the display-list build and the Core Animation commit are the rest, and the
transaction also evaluates every `ForEach` evictor in the screen (~22 on the
Journal) whether or not the rows changed. So the frame *count* is the lever,
not the draw code: on the simulator the animated skins idle at 5–9 % of a
core (Jellyfish, Hotaru, Starfield and Hebi at the top) against 0 % for a
static skin, and every fps removed is proportional. The policy in
`SkinBackdrop`: 30 fps (stickers 20), halved under Low Power Mode, stopped at
a serious thermal state (`SkinPower`), stopped when the screen is not on top
of its stack, and stopped the moment the app is backgrounded (scene phase).
Hebi's snake is a cached tape, one array read per frame, rather than a
replay of every step before it. Two things were measured and rejected:
hosting the canvas in its own hosting controller (the display link still
reached the screen's evictors, plus a layout pass per tick), and caching the
water's static gradients (3 % of the draw; the eight jellies are two thirds).
Known and open: on macOS, state restoration can rebuild a scene with no
window behind it, and that scene reports `.active` and ticks at full rate.

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

**Set the skin with `-piruSkin <id>`, not the app-group plist.** DEBUG builds
also take `-piruSkin hanabi` / `-piruScheme light|dark`, which wear a skin at
launch with ownership ignored. Writing `group.dev.yumeji.piru.plist` from
outside does **not** work on a booted simulator however carefully it is
sequenced: `cfprefsd` serves its own cached copy and flushes it back over the
edit, so the app still reads the old value — verified through an app restart, a
`cfprefsd` kickstart and a full device reboot, all of which still came up
`.piru`.

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

## A skin does not change the app icon

Tried and parked (2026-09-22, `git stash` "skin-themed alternate app icons").
The mechanism works and is cheap — but the *result* does not, so the bar for
bringing it back is a design answer, not a build-setting one.

What was verified, end to end: a per-skin Icon Composer bundle dropped in
`Piru/AltIcons/<Name>.icon` is picked up by the synchronized group with no
pbxproj file reference; `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` in the
two app configs turns them into real `CFBundleAlternateIcons` entries; and
`setAlternateIconName` then binds to them. Six skins were rendered this way.

Why it was dropped: a skin's ground is dark and low-chroma on purpose, so
swapping only the icon's background gradient gave four skins (Tsuki, ely.pink,
Yuki, Kumo) that are the same dark square at Home Screen size. Only Jellyfish
(teal) and Hebi (violet-black) read apart. Making the set work means re-tinting
the pill, heart and face per skin — the mascot is the recognisable thing, and
it stayed pink in all six. That is icon design, not a palette derivation, and
`build_skin_palettes.py` cannot generate it.

Two things worth keeping whoever picks this up:

- **Preview icons with `actool`, not the simulator.** `xcrun actool <X>.icon
  --compile <dir> --app-icon <X> --target-device iphone --platform
  iphonesimulator …` emits a rendered `<X>60x60@2x.png` beside `Assets.car` —
  Apple's real Liquid Glass render, in about a second, with no build. The
  simulator is the wrong instrument here: `setAlternateIconName` returns
  success and `alternateIconName` reads back correctly while SpringBoard keeps
  drawing the old icon from its cache.
- **The icon follows a deliberate choice, never the skin.** iOS shows its "You
  have changed the icon" alert on every `setAlternateIconName`, so wiring the
  icon to `SkinStore.setSkin` fires an alert on each try-on settle. If it comes
  back, it is its own picker.
