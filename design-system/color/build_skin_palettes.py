"""Seed the Tsuki, Starfield (astrelia) and Jellyfish skins from hex, gate
them, and write Oklch into palette-skins.json.

Text roles are pushed in L until they clear 4.5:1 on that skin's own card
(darker in light mode, lighter in dark), marks until 3:1; everything else is
taken as seeded. ely.pink's tokens are untouched — its sources are the site's
own values, hand-tuned in the 2026-09-02 session.

    python3 build_skin_palettes.py && python3 build_generator_input.py \
      && python3 generate_colorsets.py palette-generator-input.json --out ../../Shared/Assets.xcassets
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from colorimetry import (  # noqa: E402
    fit_chroma,
    hex_to_rgb,
    oklch,
    oklch_to_rgb,
    rgb_to_hex,
    wcag_ratio,
)

PALETTE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "palette-skins.json")

TEXT, MARK = 4.5, 3.0
# name: {light: hex, dark: hex}
SKINS = {
    "tsuki": {
        "surface/background": ("#ece6f7", "#1f1733"),
        "surface/card": ("#fbf9ff", "#291f42"),
        "surface/input": ("#f1ecfa", "#382c59"),
        "stroke": ("#8f7bb8", "#8c73bf"),
        "shadow": ("#a08cd6", "#8c73bf"),  # the glow colour for a soft skin
        "eyebrow": ("#6b52a3", "#b3a3e0"),
        "text/secondary": ("#6d6484", "#a69ec0"),
        "accent/text": ("#5e46a0", "#b3a3e0"),
        "accent/mark": ("#7a5fc9", "#8c73bf"),
        "accent/on": ("#ffffff", "#1a1230"),
        "semantic/success/text": ("#1f7f5a", "#8fe0c0"),
        "semantic/success/accent": ("#2a9c72", "#7ad6bb"),
        "semantic/caution/text": ("#8a6410", "#e8cf7a"),
        "semantic/caution/accent": ("#c9a13d", "#d9b856"),
        "semantic/info/text": ("#2f5fae", "#9fbcf0"),
        "semantic/info/accent": ("#4a7fd0", "#7fa6e6"),
        "semantic/danger/text": ("#b8244f", "#ff8fa8"),
        "semantic/danger/accent": ("#d63a68", "#ff6b8f"),
        "title/stroke": ("#2a1f45", "#0d0818"),
        "title/shadow": ("#b8a7dd", "#4a3878"),
        "star/core": ("#ffffff", "#f2eeff"),
        "star/halo": ("#b8a7dd", "#9c8cff"),
    },
    "astrelia": {
        "surface/background": ("#cfdcf2", "#0f172e"),
        "surface/card": ("#f6f8fe", "#1a2140"),
        "surface/input": ("#e9eef9", "#242e54"),
        "stroke": ("#1b2444", "#47598e"),
        "shadow": ("#1b2444", "#070b16"),
        "eyebrow": ("#6a4a9c", "#b389d9"),
        "text/secondary": ("#5b6684", "#aebbdc"),
        "accent/text": ("#2f6f92", "#79a9c4"),
        "accent/mark": ("#3f8bb4", "#79a9c4"),
        "accent/on": ("#ffffff", "#070b16"),
        "semantic/success/text": ("#1f7f5a", "#7ad6bb"),
        "semantic/success/accent": ("#2a9c72", "#7ad6bb"),
        "semantic/caution/text": ("#8a6a1a", "#c9ab55"),
        "semantic/caution/accent": ("#b8922e", "#c9ab55"),
        "semantic/info/text": ("#2f5fae", "#9fbcf0"),
        "semantic/info/accent": ("#4a7fd0", "#79a9c4"),
        "semantic/danger/text": ("#b8244f", "#ff8fa8"),
        "semantic/danger/accent": ("#d63a68", "#ff5c7a"),
        "title/stroke": ("#070b16", "#070b16"),
        "title/shadow": ("#47598e", "#47598e"),
        "star/core": ("#ffffff", "#ffffff"),
        "star/halo": ("#79a9c4", "#79a9c4"),
        "title/fill": ("#1b2444", "#c9ab55"),
    },
    "graphite": {
        "surface/background": ("#F2F2F4", "#121214"),
        "surface/card": ("#FFFFFF", "#1C1C20"),
        "surface/input": ("#EBEBEE", "#26262C"),
        "stroke": ("#C8C8CE", "#3A3A42"),
        "shadow": ("#000000", "#000000"),
        "eyebrow": ("#5A5A66", "#A8A8B4"),
        "text/secondary": ("#6B6B76", "#9A9AA6"),
        "accent/text": ("#3A3A44", "#C8C8D2"),
        "accent/mark": ("#6E6E7A", "#9A9AA6"),
        "accent/on": ("#FFFFFF", "#121214"),
        "semantic/success/text": ("#2F7D5A", "#8FCBA8"),
        "semantic/success/accent": ("#4F9F78", "#6FB08A"),
        "semantic/caution/text": ("#8A6A1A", "#D9BC7A"),
        "semantic/caution/accent": ("#B8933A", "#C9A85A"),
        "semantic/info/text": ("#3A5F8A", "#9FB8D6"),
        "semantic/info/accent": ("#5A7FAA", "#7F9FC0"),
        "semantic/danger/text": ("#A83A44", "#E0929A"),
        "semantic/danger/accent": ("#C85A64", "#C87A82"),
        "title/fill": ("#1A1A1E", "#F0F0F4"),
        "title/stroke": ("#1A1A1E", "#000000"),
        "title/shadow": ("#C8C8CE", "#3A3A42"),
    },
    "linen": {
        "surface/background": ("#F4F0E8", "#1C1916"),
        "surface/card": ("#FBF8F2", "#26221E"),
        "surface/input": ("#EFEAE0", "#302B26"),
        "stroke": ("#D6CFC2", "#4A433C"),
        "shadow": ("#8C7A66", "#8C7A66"),
        "eyebrow": ("#6E5A48", "#C9B8A6"),
        "text/secondary": ("#6F675E", "#ADA294"),
        "accent/text": ("#6B4E3A", "#D8BFA6"),
        "accent/mark": ("#9C7A5E", "#B89478"),
        "accent/on": ("#FFFFFF", "#1C1916"),
        "semantic/success/text": ("#3D7A4E", "#9CC9A6"),
        "semantic/success/accent": ("#5F9A6E", "#7FB08C"),
        "semantic/caution/text": ("#8A6A1A", "#D9BC7A"),
        "semantic/caution/accent": ("#B8933A", "#C9A85A"),
        "semantic/info/text": ("#4A6A8A", "#A6BBD0"),
        "semantic/info/accent": ("#6A8AAA", "#8AA3BC"),
        "semantic/danger/text": ("#A0433F", "#DE9C96"),
        "semantic/danger/accent": ("#C0605A", "#C48078"),
        "title/fill": ("#2A2420", "#F1EBE2"),
        "title/stroke": ("#2A2420", "#0F0C0A"),
        "title/shadow": ("#D6CFC2", "#4A433C"),
    },
    "slate": {
        "surface/background": ("#EEF1F5", "#15191F"),
        "surface/card": ("#FFFFFF", "#1E242C"),
        "surface/input": ("#E6EBF2", "#28303A"),
        "stroke": ("#C5CEDA", "#3C4652"),
        "shadow": ("#5C7390", "#5C7390"),
        "eyebrow": ("#4E617A", "#AFBFD2"),
        "text/secondary": ("#66748A", "#9EACBE"),
        "accent/text": ("#3F5A7A", "#B9CBE0"),
        "accent/mark": ("#6A86A6", "#8CA4C0"),
        "accent/on": ("#FFFFFF", "#15191F"),
        "semantic/success/text": ("#2F7A5E", "#8FCBB0"),
        "semantic/success/accent": ("#4F9E7E", "#6FAF90"),
        "semantic/caution/text": ("#846A24", "#D6BE82"),
        "semantic/caution/accent": ("#B3934A", "#C4A664"),
        "semantic/info/text": ("#3A5F8A", "#9FB8D6"),
        "semantic/info/accent": ("#5A7FAA", "#7F9FC0"),
        "semantic/danger/text": ("#A63E50", "#E0929F"),
        "semantic/danger/accent": ("#C45C6C", "#C87A88"),
        "title/fill": ("#1E2630", "#EEF1F5"),
        "title/stroke": ("#1E2630", "#0A0D12"),
        "title/shadow": ("#C5CEDA", "#3C4652"),
    },
    "papergarden": {
        "surface/background": ("#F5F2ED", "#1F1B22"),
        "surface/card": ("#F7F5F0", "#2B262E"),
        "surface/input": ("#F5F0E0", "#36303A"),
        "stroke": ("#262630", "#F1EBE2"),
        "shadow": ("#8C6A4A", "#8C6A4A"),
        "eyebrow": ("#7A2E2A", "#E8B0A8"),
        "text/secondary": ("#6B665E", "#B8B0A4"),
        "accent/text": ("#B5231F", "#F08C84"),
        "accent/mark": ("#D9332E", "#F06A62"),
        "accent/on": ("#FFFFFF", "#1F1B22"),
        "semantic/success/text": ("#2E7A45", "#9FD9AE"),
        "semantic/success/accent": ("#40A659", "#7FCC92"),
        "semantic/caution/text": ("#8A6A1E", "#E8CB86"),
        "semantic/caution/accent": ("#D9B859", "#D9B859"),
        "semantic/info/text": ("#2F5FA0", "#9FBEEA"),
        "semantic/info/accent": ("#3373C7", "#7FA6E0"),
        "semantic/danger/text": ("#A8201C", "#F09C96"),
        "semantic/danger/accent": ("#C9302B", "#E8736C"),
        "title/fill": ("#262630", "#F1EBE2"),
        "title/stroke": ("#262630", "#0F0C12"),
        "title/shadow": ("#F5D1D9", "#5A3A44"),
        "garden/sand1": ("#DBCCB3", "#58513F"),
        "garden/sand2": ("#C2AD8F", "#4D4236"),
        "garden/groove": ("#8C6A4A", "#1A1614"),
        "garden/stone": ("#8C8780", "#5E5A55"),
        "garden/moss": ("#598C40", "#3F6B2E"),
        "garden/petal": ("#FFCCD9", "#E8A6B8"),
        "garden/firefly": ("#FFFF99", "#FFFF99"),
    },
    "hotaru": {
        "surface/background": ("#E6EEDF", "#050D08"),
        "surface/card": ("#F7FAF4", "#0E1811"),
        "surface/input": ("#EEF4E8", "#172219"),
        "stroke": ("#8FB07A", "#B3E64D"),
        "shadow": ("#B3E64D", "#B3E64D"),
        "eyebrow": ("#4A6B3A", "#C9E89A"),
        "text/secondary": ("#5C6B58", "#A9BFA4"),
        "accent/text": ("#2E6B3A", "#E6D98A"),
        "accent/mark": ("#3E8C4A", "#FFF2B3"),
        "accent/on": ("#FFFFFF", "#0A1208"),
        "semantic/success/text": ("#2F7A3A", "#B3E64D"),
        "semantic/success/accent": ("#4FA35A", "#B3E64D"),
        "semantic/caution/text": ("#8A6410", "#FFD166"),
        "semantic/caution/accent": ("#D9A93B", "#FFD166"),
        "semantic/info/text": ("#1E6E86", "#19B3CC"),
        "semantic/info/accent": ("#2E9BB8", "#19B3CC"),
        "semantic/danger/text": ("#B0304F", "#F07A9A"),
        "semantic/danger/accent": ("#D44A6C", "#CC4D80"),
        "title/fill": ("#1E2A1F", "#E8F2E6"),
        "title/stroke": ("#1E2A1F", "#020503"),
        "title/shadow": ("#B3E64D", "#FFF2B3"),
        "night/core": ("#FFFFFF", "#FFF2B3"),
        "night/glow": ("#C9DDB0", "#B3E64D"),
        "night/fog": ("#DDE8D4", "#0D140F"),
        "night/tree": ("#B8CCAA", "#010302"),
        "night/aurora1": ("#1ACC4D", "#1ACC4D"),
        "night/aurora2": ("#1AB3CC", "#1AB3CC"),
        "night/aurora3": ("#8033CC", "#8033CC"),
        "night/aurora4": ("#CC4D80", "#CC4D80"),
    },
    "yuki": {
        "surface/background": ("#EDF2FA", "#14172E"),
        "surface/card": ("#FAFAFA", "#23263A"),
        "surface/input": ("#E3F2FC", "#2C3048"),
        "stroke": ("#C7D6EE", "#3E4460"),
        "shadow": ("#7887CC", "#7887CC"),
        "eyebrow": ("#4E5A9E", "#B7C0F2"),
        "text/secondary": ("#6A6F85", "#A6ACC4"),
        "accent/text": ("#5C6BBF", "#A3ADF0"),
        "accent/mark": ("#7887CC", "#8E9BE0"),
        "accent/on": ("#FFFFFF", "#14172E"),
        "semantic/success/text": ("#2F7A3C", "#8FD79A"),
        "semantic/success/accent": ("#66BA6B", "#7FCC85"),
        "semantic/caution/text": ("#8A6410", "#F2CC7A"),
        "semantic/caution/accent": ("#E0A93B", "#E8BE66"),
        "semantic/info/text": ("#3A5FA8", "#9FB6F0"),
        "semantic/info/accent": ("#5C7FD4", "#8FA8EA"),
        "semantic/danger/text": ("#B8383F", "#FF8C8C"),
        "semantic/danger/accent": ("#FF6B6B", "#FF7A7A"),
        "title/fill": ("#212121", "#EDEDED"),
        "title/stroke": ("#212121", "#0A0C1A"),
        "title/shadow": ("#E3F2FC", "#7887CC"),
        "snow/flake": ("#7887CC", "#FFFFFF"),
        "snow/frost": ("#FFFFFF", "#E3F2FC"),
    },
    "hebi": {
        "surface/background": ("#EFE9FF", "#0D0221"),
        "surface/card": ("#FFFFFF", "#150A33"),
        "surface/input": ("#F4F0FF", "#1E0F45"),
        "stroke": ("#A800A8", "#FF00FF"),
        "shadow": ("#FF00FF", "#FF00FF"),
        "eyebrow": ("#6E2E9E", "#C77DFF"),
        "text/secondary": ("#5F5878", "#B3A6CC"),
        "accent/text": ("#A800A8", "#FF5CFF"),
        "accent/mark": ("#00798A", "#00FFFF"),
        "accent/on": ("#FFFFFF", "#0D0221"),
        "semantic/success/text": ("#1E7A48", "#00FF88"),
        "semantic/success/accent": ("#00B36A", "#00FF88"),
        "semantic/caution/text": ("#8A6A00", "#FFDD00"),
        "semantic/caution/accent": ("#D9B800", "#FFDD00"),
        "semantic/info/text": ("#00798A", "#00FFFF"),
        "semantic/info/accent": ("#00A3B8", "#00FFFF"),
        "semantic/danger/text": ("#C0223F", "#FF4466"),
        "semantic/danger/accent": ("#E63356", "#FF4466"),
        "title/fill": ("#00798A", "#00FFFF"),
        "title/stroke": ("#1A1030", "#0D0221"),
        "title/shadow": ("#FF00FF", "#FF00FF"),
        "arcade/grid": ("#D9CCFF", "#1A0440"),
        "arcade/wall": ("#B08CFF", "#8800FF"),
        "arcade/border": ("#E066E0", "#FF00FF"),
        "arcade/snake": ("#00A3B8", "#00FFFF"),
        "arcade/snakeBody": ("#008B9E", "#00BBCC"),
        "arcade/food": ("#E066E0", "#FF00FF"),
        "arcade/star": ("#C7B8F5", "#FFFFFF"),
    },
    "kumo": {
        "surface/background": ("#DCEBFB", "#0D0B2B"),
        "surface/card": ("#FFFFFF", "#1A1448"),
        "surface/input": ("#EAF3FE", "#281F63"),
        "stroke": ("#FFFFFF", "#FFFFFF"),
        "shadow": ("#4A90D9", "#7B68EE"),
        "eyebrow": ("#3E5E8C", "#B8C4FF"),
        "text/secondary": ("#5A6A80", "#B3B3CC"),
        "accent/text": ("#2A6FB8", "#7FB8F0"),
        "accent/mark": ("#4A90D9", "#66D9F2"),
        "accent/on": ("#FFFFFF", "#0D0B2B"),
        "semantic/success/text": ("#2A7A55", "#66D9A0"),
        "semantic/success/accent": ("#3FAD78", "#66D9A0"),
        "semantic/caution/text": ("#8A6410", "#FFD159"),
        "semantic/caution/accent": ("#E6B040", "#FFD159"),
        "semantic/info/text": ("#5A4DB8", "#B0A3FF"),
        "semantic/info/accent": ("#7B68EE", "#9F8FFF"),
        "semantic/danger/text": ("#B83A5C", "#F2739F"),
        "semantic/danger/accent": ("#F27399", "#F2739F"),
        "title/fill": ("#14203A", "#FFFFFF"),
        "title/stroke": ("#14203A", "#05041A"),
        "title/shadow": ("#66D9F2", "#66D9F2"),
        "sky/night1": ("#0D0A2B", "#0D0A2B"),
        "sky/night2": ("#140F40", "#140F40"),
        "sky/day1": ("#3359B3", "#3359B3"),
        "sky/day2": ("#80B3F2", "#80B3F2"),
        "sky/sunset1": ("#8C3366", "#8C3366"),
        "sky/sunset2": ("#E67340", "#E67340"),
        "sky/cloud": ("#FFFFFF", "#FFFFFF"),
        "sky/star": ("#FFFFFF", "#FFFFFF"),
        "sky/rain": ("#FFFFFF", "#FFFFFF"),
        "sky/sun": ("#FFD159", "#FFD159"),
        "sky/moon": ("#F2F2FF", "#F2F2FF"),
    },
    "jellyfish": {
        "surface/background": ("#bfe9ee", "#041a2a"),
        "surface/card": ("#f3fcfd", "#0b2b40"),
        "surface/input": ("#e3f6f8", "#113a52"),
        "stroke": ("#1f8f9c", "#4fd8e0"),
        "shadow": ("#5fd5dd", "#2fc9d3"),  # glow
        "eyebrow": ("#0f6f7a", "#9ee8ef"),
        "text/secondary": ("#4f7480", "#8fb3c4"),
        "accent/text": ("#0c7c8a", "#5fe3e0"),
        "accent/mark": ("#11a3b3", "#2fd3d8"),
        "accent/on": ("#ffffff", "#04202c"),
        "semantic/success/text": ("#1f7f4f", "#8fe6b8"),
        "semantic/success/accent": ("#2a9c66", "#6fe0a8"),
        "semantic/caution/text": ("#8a5a00", "#ffd98a"),
        "semantic/caution/accent": ("#d9962a", "#ffd166"),
        "semantic/info/text": ("#2b62b8", "#a8c8ff"),
        "semantic/info/accent": ("#3f7fd8", "#7fb4ff"),
        "semantic/danger/text": ("#c92a55", "#ff9bb0"),
        "semantic/danger/accent": ("#e0446c", "#ff6b8a"),
        "title/stroke": ("#0a3a44", "#03141f"),
        "title/shadow": ("#7fd8df", "#1f7f8a"),
        "water/deep": ("#7fd0da", "#02101c"),
        "water/shallow": ("#d6f4f7", "#0a3550"),
        "water/ray": ("#ffffff", "#7fe6f0"),
        "water/bubble": ("#ffffff", "#bff4f8"),
        "jelly/violet": ("#8b88ff", "#8b88ff"),
        "jelly/cyan": ("#58e0f5", "#58e0f5"),
        "jelly/pink": ("#ff9bdd", "#ff9bdd"),
    },
    "dosewiki": {
        # dose.wiki's own tokens (their CSS, brand hue 326, plum hue 318), oklch
        # converted with colorimetry.py. Dark is their default appearance.
        "surface/background": (
            "#fefdfe",
            "#110617",
        ),  # light: oklch(99.4% .002 326); dark: their body bg
        "surface/card": ("#faedfa", "#1f0527"),  # frosted-panel-primary / panel-base
        "surface/input": ("#f6e5f6", "#220c2a"),  # oklch(94% .03 326) / control-base
        "stroke": (
            "#e8d8e9",
            "#6c4973",
        ),  # card border: oklch(48% .13 326)/.2 and rgb(240 171 252)/.16, composited over the card
        "shadow": (
            "#ffffff",
            "#f0abfc",
        ),  # the frosted highlight along the card's top: white / fuchsia-300
        "eyebrow": ("#584560", "#bcb9be"),  # text-muted
        "text/secondary": ("#46314f", "#dcdcdc"),  # text-secondary
        "accent/text": ("#932998", "#f0abfc"),  # --theme-accent: oklch(49% .19 326) / fuchsia-300
        "accent/mark": ("#a854ab", "#f0abfc"),  # accent-soft / accent
        "accent/on": ("#ffffff", "#110617"),  # their filled button: light fuchsia with dark text
        # the semantic pairs are their dose-tier ramp: threshold, light, moderate, heavy
        "semantic/success/text": (
            "#007252",
            "#71cda7",
        ),  # oklch(58% .12 165) pushed darker so it clears 4.5 in P3 / oklch(78% .105 165)
        "semantic/success/accent": ("#0a9068", "#71cda7"),
        "semantic/caution/text": ("#9d7200", "#f0c36f"),  # oklch(58% .12 82) / oklch(84% .115 82)
        "semantic/caution/accent": ("#9d7200", "#f0c36f"),
        "semantic/info/text": ("#0e84b7", "#76c9f8"),  # oklch(58% .12 235) / oklch(80% .105 235)
        "semantic/info/accent": ("#0e84b7", "#76c9f8"),
        "semantic/danger/text": ("#b65962", "#fa979d"),  # oklch(58% .12 16) / oklch(78% .12 16)
        "semantic/danger/accent": ("#b65962", "#fa979d"),
        "title/fill": ("#351741", "#ffffff"),
        "title/stroke": ("#351741", "#110617"),
        "title/shadow": ("#e9b8ee", "#a21caf"),  # the title's fuchsia glow / fuchsia-700
        "molecule/ink": ("#932998", "#f0abfc"),  # the ring, drawn as a template at low alpha
        "halo/top": ("#9f2180", "#733f83"),  # home-glow-top / page-halo-top oklch(46% .12 318)
        "halo/left": ("#9f2180", "#744276"),  # page-halo-left oklch(46% .1 326)
        "halo/right": ("#7c3aed", "#584d8b"),  # page-halo-right oklch(46% .1 290)
        "halo/bottom": ("#7c3aed", "#d946ef"),  # home-glow-bottom
    },
}

TEXT_ROLES = {
    "eyebrow",
    "text/secondary",
    "accent/text",
    "semantic/success/text",
    "semantic/caution/text",
    "semantic/info/text",
    "semantic/danger/text",
}
MARK_ROLES = {
    "accent/mark",
    "semantic/success/accent",
    "semantic/caution/accent",
    "semantic/info/accent",
    "semantic/danger/accent",
}


def gate(lch, bg, floor, darken):
    """Move L until wcag(fg, bg) >= floor. darken=True lowers L (light mode)."""
    L, C, h = lch
    for _ in range(200):
        rgb = oklch_to_rgb(fit_chroma((L, C, h)))
        if wcag_ratio(rgb, bg) >= floor:
            return (L, C, h), rgb
        L += -0.005 if darken else 0.005
        if not 0 < L < 1:
            break
    return (L, C, h), oklch_to_rgb(fit_chroma((L, C, h)))


with open(PALETTE_PATH) as f:
    out = json.load(f)
report = []
for skin, tokens in SKINS.items():
    entry = {}
    for mode_i, mode in enumerate(("light", "dark")):
        card = hex_to_rgb(tokens["surface/card"][mode_i])
        bg = hex_to_rgb(tokens["surface/background"][mode_i])
        darken = mode == "light"
        for name, pair in tokens.items():
            rgb = hex_to_rgb(pair[mode_i])
            lch = oklch(rgb)
            if name in TEXT_ROLES:
                lch, rgb = gate(lch, card, TEXT, darken)
                lch, rgb = gate(lch, bg, TEXT, darken)
            elif name in MARK_ROLES:
                lch, rgb = gate(lch, card, MARK, darken)
            elif name == "accent/on":
                acc = oklch_to_rgb(fit_chroma(oklch(hex_to_rgb(tokens["accent/text"][mode_i]))))
                r = wcag_ratio(rgb, acc)
                report.append(f"  {skin} {mode} accent/on on accent/text = {r:.2f}")
            entry.setdefault(name, {})[mode] = [round(x, 5) for x in lch]
            if name in TEXT_ROLES or name in MARK_ROLES:
                report.append(
                    f"  {skin} {mode} {name:26s} {rgb_to_hex(rgb)} card {wcag_ratio(rgb, card):.2f} bg {wcag_ratio(rgb, bg):.2f}"
                )
    out["skins"][skin] = entry

# ely.pink's tokens are the site's own, hand-tuned against the card; push only its text
# roles' L until they also clear the page background, the way the three above are gated.
ely = out["skins"]["elypink"]
for mode in ("light", "dark"):
    card = oklch_to_rgb(fit_chroma(tuple(ely["surface/card"][mode])))
    bg = oklch_to_rgb(fit_chroma(tuple(ely["surface/background"][mode])))
    for name in TEXT_ROLES:
        lch = tuple(ely[name][mode])
        lch, rgb = gate(lch, card, TEXT, mode == "light")
        lch, rgb = gate(lch, bg, TEXT, mode == "light")
        ely[name][mode] = [round(x, 5) for x in lch]
        report.append(
            f"  elypink {mode} {name:26s} {rgb_to_hex(rgb)} card {wcag_ratio(rgb, card):.2f} bg {wcag_ratio(rgb, bg):.2f}"
        )
with open(PALETTE_PATH, "w") as f:
    json.dump(out, f, indent=1)
    f.write("\n")
print("\n".join(report))
