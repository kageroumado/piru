"""Seed the Tsuki, Starfield (astrelia) and Jellyfish skins from hex, gate
them, and write Oklch into palette-skins.json.

Text roles are pushed in L until they clear 4.5:1 on that skin's own card
(darker in light mode, lighter in dark), marks until 3:1; everything else is
taken as seeded. ely.pink's tokens are untouched — its sources are the site's
own values, hand-tuned in the 2026-09-02 session.

    python3 build_skin_palettes.py && python3 build_generator_input.py \
      && python3 generate_colorsets.py palette-generator-input.json --out ../../Shared/Assets.xcassets
"""
import json, sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from colorimetry import hex_to_rgb, oklch, oklch_to_rgb, wcag_ratio, fit_chroma, rgb_to_hex

TEXT, MARK = 4.5, 3.0
# name: {light: hex, dark: hex}
SKINS = {
 "tsuki": {
  "surface/background": ("#ece6f7", "#1f1733"),
  "surface/card":       ("#fbf9ff", "#291f42"),
  "surface/input":      ("#f1ecfa", "#382c59"),
  "stroke":             ("#8f7bb8", "#8c73bf"),
  "shadow":             ("#a08cd6", "#8c73bf"),   # the glow colour for a soft skin
  "eyebrow":            ("#6b52a3", "#b3a3e0"),
  "text/secondary":     ("#6d6484", "#a69ec0"),
  "accent/text":        ("#5e46a0", "#b3a3e0"),
  "accent/mark":        ("#7a5fc9", "#8c73bf"),
  "accent/on":          ("#ffffff", "#1a1230"),
  "semantic/success/text":   ("#1f7f5a", "#8fe0c0"),
  "semantic/success/accent": ("#2a9c72", "#7ad6bb"),
  "semantic/caution/text":   ("#8a6410", "#e8cf7a"),
  "semantic/caution/accent": ("#c9a13d", "#d9b856"),
  "semantic/info/text":      ("#2f5fae", "#9fbcf0"),
  "semantic/info/accent":    ("#4a7fd0", "#7fa6e6"),
  "semantic/danger/text":    ("#b8244f", "#ff8fa8"),
  "semantic/danger/accent":  ("#d63a68", "#ff6b8f"),
  "title/stroke":       ("#2a1f45", "#0d0818"),
  "title/shadow":       ("#b8a7dd", "#4a3878"),
  "star/core":          ("#ffffff", "#f2eeff"),
  "star/halo":          ("#b8a7dd", "#9c8cff"),
 },
 "astrelia": {
  "surface/background": ("#cfdcf2", "#0f172e"),
  "surface/card":       ("#f6f8fe", "#1a2140"),
  "surface/input":      ("#e9eef9", "#242e54"),
  "stroke":             ("#1b2444", "#47598e"),
  "shadow":             ("#1b2444", "#070b16"),
  "eyebrow":            ("#6a4a9c", "#b389d9"),
  "text/secondary":     ("#5b6684", "#aebbdc"),
  "accent/text":        ("#2f6f92", "#79a9c4"),
  "accent/mark":        ("#3f8bb4", "#79a9c4"),
  "accent/on":          ("#ffffff", "#070b16"),
  "semantic/success/text":   ("#1f7f5a", "#7ad6bb"),
  "semantic/success/accent": ("#2a9c72", "#7ad6bb"),
  "semantic/caution/text":   ("#8a6a1a", "#c9ab55"),
  "semantic/caution/accent": ("#b8922e", "#c9ab55"),
  "semantic/info/text":      ("#2f5fae", "#9fbcf0"),
  "semantic/info/accent":    ("#4a7fd0", "#79a9c4"),
  "semantic/danger/text":    ("#b8244f", "#ff8fa8"),
  "semantic/danger/accent":  ("#d63a68", "#ff5c7a"),
  "title/stroke":       ("#070b16", "#070b16"),
  "title/shadow":       ("#47598e", "#47598e"),
  "star/core":          ("#ffffff", "#ffffff"),
  "star/halo":          ("#79a9c4", "#79a9c4"),
  "title/fill":         ("#1b2444", "#c9ab55"),
 },
 "jellyfish": {
  "surface/background": ("#bfe9ee", "#041a2a"),
  "surface/card":       ("#f3fcfd", "#0b2b40"),
  "surface/input":      ("#e3f6f8", "#113a52"),
  "stroke":             ("#1f8f9c", "#4fd8e0"),
  "shadow":             ("#5fd5dd", "#2fc9d3"),   # glow
  "eyebrow":            ("#0f6f7a", "#9ee8ef"),
  "text/secondary":     ("#4f7480", "#8fb3c4"),
  "accent/text":        ("#0c7c8a", "#5fe3e0"),
  "accent/mark":        ("#11a3b3", "#2fd3d8"),
  "accent/on":          ("#ffffff", "#04202c"),
  "semantic/success/text":   ("#1f7f4f", "#8fe6b8"),
  "semantic/success/accent": ("#2a9c66", "#6fe0a8"),
  "semantic/caution/text":   ("#8a5a00", "#ffd98a"),
  "semantic/caution/accent": ("#d9962a", "#ffd166"),
  "semantic/info/text":      ("#2b62b8", "#a8c8ff"),
  "semantic/info/accent":    ("#3f7fd8", "#7fb4ff"),
  "semantic/danger/text":    ("#c92a55", "#ff9bb0"),
  "semantic/danger/accent":  ("#e0446c", "#ff6b8a"),
  "title/stroke":       ("#0a3a44", "#03141f"),
  "title/shadow":       ("#7fd8df", "#1f7f8a"),
  "water/deep":         ("#7fd0da", "#02101c"),
  "water/shallow":      ("#d6f4f7", "#0a3550"),
  "water/ray":          ("#ffffff", "#7fe6f0"),
  "water/bubble":       ("#ffffff", "#bff4f8"),
  "jelly/violet":       ("#8b88ff", "#8b88ff"),
  "jelly/cyan":         ("#58e0f5", "#58e0f5"),
  "jelly/pink":         ("#ff9bdd", "#ff9bdd"),
 },
}
TEXT_ROLES = {"eyebrow", "text/secondary", "accent/text", "semantic/success/text", "semantic/caution/text", "semantic/info/text", "semantic/danger/text"}
MARK_ROLES = {"accent/mark", "semantic/success/accent", "semantic/caution/accent", "semantic/info/accent", "semantic/danger/accent"}

def gate(lch, bg, floor, darken):
    """Move L until wcag(fg, bg) >= floor. darken=True lowers L (light mode)."""
    L, C, h = lch
    for _ in range(200):
        rgb = oklch_to_rgb(fit_chroma((L, C, h)))
        if wcag_ratio(rgb, bg) >= floor: return (L, C, h), rgb
        L += -0.005 if darken else 0.005
        if not 0 < L < 1: break
    return (L, C, h), oklch_to_rgb(fit_chroma((L, C, h)))

out = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'palette-skins.json')))
report = []
for skin, tokens in SKINS.items():
    entry = {}
    for mode_i, mode in enumerate(("light", "dark")):
        card = hex_to_rgb(tokens["surface/card"][mode_i])
        darken = mode == "light"
        for name, pair in tokens.items():
            rgb = hex_to_rgb(pair[mode_i]); lch = oklch(rgb)
            if name in TEXT_ROLES:
                lch, rgb = gate(lch, card, TEXT, darken)
            elif name in MARK_ROLES:
                lch, rgb = gate(lch, card, MARK, darken)
            elif name == "accent/on":
                acc = oklch_to_rgb(fit_chroma(oklch(hex_to_rgb(tokens["accent/text"][mode_i]))))
                r = wcag_ratio(rgb, acc)
                report.append(f"  {skin} {mode} accent/on on accent/text = {r:.2f}")
            entry.setdefault(name, {})[mode] = [round(x, 5) for x in lch]
            if name in TEXT_ROLES or name in MARK_ROLES:
                report.append(f"  {skin} {mode} {name:26s} {rgb_to_hex(rgb)} {wcag_ratio(rgb, card):.2f}")
    out["skins"][skin] = entry
json.dump(out, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'palette-skins.json'), 'w'), indent=1)
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'palette-skins.json'), 'a').write("\n")
print("\n".join(report))
