#!/usr/bin/env python3
"""Generate the L2 encoding scales -> palette-L2.json

L2 scales are multi-valued but still meaning-bearing (experience phases, routes,
dose tiers). They get the *same* treatment as the L1 semantic tokens — a `text`
variant gated at WCAG AA against both the card and its own fill, and an `accent`
variant gated at the 3:1 non-text floor — because they fail the same way. The
phase ramp, for instance, renders its colour as `.caption` text on a capsule
filled with that same colour at 18% (`DosePhaseProgressBar.swift:57,72`), which
is the self-tint pattern that put 21 of 33 measured text pairs below AA.

**Hue is held from the existing values.** These scales encode meaning through
hue, and users have learned them; the job here is to fix lightness and chroma,
not to redesign what "peak" looks like. Each token keeps its source hue to
within a degree.

**Chroma is maximised at each gate**, exactly as `palette-L1.json` is built, so
`accent` lands at the vivid end rather than merely the first value that clears.
Deriving these by "first lightness that passes" instead produces a dark-mode
accent *darker* than its own text, which is backwards.

    python3 build_l2_scales.py
"""

from __future__ import annotations

import json
from pathlib import Path

from colorimetry import (
    composite,
    fit_chroma,
    hex_to_rgb,
    oklch,
    oklch_to_rgb,
    rgb_to_hex,
    wcag_ratio,
)

HERE = Path(__file__).parent

CARD = {"light": "#f5f5f5", "dark": "#111111"}
FILL_ALPHA = 0.10
TEXT_GATE = 4.55  # headroom over 4.5 so 8-bit quantisation cannot drop under
ACCENT_GATE = 3.05

# Source hues, taken from the ramp already shared by TimelineGraphView,
# SessionReportPDF and DosePhaseProgressBar. The competing ramp in
# DoseLevelIndicator (.blue/.teal/.orange/.purple) is dropped: it is used in one
# place against this one's three, and having two meant editing a dose and then
# reading it flipped "peak" from orange to green.
PHASE_SOURCE = {
    "onset": "9B9BA1",
    "comeup": "3A8DEF",
    "peak": "34C759",
    "offset": "FF9F0A",
    # `afterglow` deliberately reuses onset's neutral: the arc opens and closes
    # quiet. Both source ramps already did this.
    "afterglow": "9B9BA1",
}


def max_chroma(hue: float, gate, background) -> tuple[float, float, tuple]:
    """Highest-chroma colour at `hue` satisfying `gate(colour)`.

    Scans every lightness and keeps the best, rather than returning the first
    that passes -- see the module note on why that distinction matters.
    """
    best = None
    for i in range(1, 200):
        lightness = i / 200
        for j in range(80, 0, -1):
            chroma = j / 200
            lch = fit_chroma((lightness, chroma, hue), "srgb")
            if abs(lch[1] - chroma) > 1e-3:
                continue  # gamut-clamped at this chroma, try lower
            candidate = hex_to_rgb(rgb_to_hex(oklch_to_rgb(lch, "srgb")))  # quantise, then test
            if gate(candidate):
                if best is None or chroma > best[0]:
                    best = (chroma, lightness, candidate)
                break
    if best is None:
        raise ValueError(f"no colour at hue {hue} satisfies the gate on {background}")
    return best


# Below this chroma a colour is a neutral and its hue is meaningless noise --
# `#9B9BA1` reports 285.9 degrees, and maximising chroma there turns a gray into
# a vivid purple. Neutrals keep their hue but never gain chroma.
NEUTRAL_CHROMA = 0.02


def build_neutral(hue: float, chroma: float) -> dict[str, dict]:
    """A neutral step: hold the (tiny) source chroma, move lightness only."""
    entry: dict[str, dict] = {}
    for mode, card_hex in CARD.items():
        card = hex_to_rgb(card_hex)

        def at(lightness: float) -> tuple:
            return hex_to_rgb(
                rgb_to_hex(oklch_to_rgb(fit_chroma((lightness, chroma, hue), "srgb"), "srgb"))
            )

        steps = [i / 200 for i in range(1, 200)]
        if mode == "light":
            steps.reverse()  # prefer the lightest value that still passes
        accent = next(c for c in map(at, steps) if wcag_ratio(c, card) >= ACCENT_GATE)
        fill = composite(accent, FILL_ALPHA, card)
        text = next(
            c
            for c in map(at, steps)
            if wcag_ratio(c, fill) >= TEXT_GATE and wcag_ratio(c, card) >= TEXT_GATE
        )
        entry[mode] = {
            "text": rgb_to_hex(text),
            "accent": rgb_to_hex(accent),
            "hue": round(hue, 2),
            "neutral": True,
            "verified": {
                "text_on_fill": round(wcag_ratio(text, fill), 2),
                "text_on_card": round(wcag_ratio(text, card), 2),
                "accent_on_card": round(wcag_ratio(accent, card), 2),
            },
        }
    return entry


def build_scale(source: dict[str, str]) -> dict[str, dict]:
    scale: dict[str, dict] = {}
    for name, source_hex in source.items():
        _, source_chroma, hue = oklch(hex_to_rgb(source_hex))
        if source_chroma < NEUTRAL_CHROMA:
            scale[name] = build_neutral(hue, source_chroma)
            continue
        entry: dict[str, dict] = {}
        for mode, card_hex in CARD.items():
            card = hex_to_rgb(card_hex)
            # Bind `card` / `fill` as defaults rather than closing over the loop
            # variable: a late-bound closure would silently gate every mode
            # against whichever surface the loop happened to end on.
            _, _, accent = max_chroma(
                hue, lambda c, bg=card: wcag_ratio(c, bg) >= ACCENT_GATE, card
            )
            fill = composite(accent, FILL_ALPHA, card)
            _, _, text = max_chroma(
                hue,
                lambda c, f=fill, bg=card: (
                    wcag_ratio(c, f) >= TEXT_GATE and wcag_ratio(c, bg) >= TEXT_GATE
                ),
                card,
            )
            entry[mode] = {
                "text": rgb_to_hex(text),
                "accent": rgb_to_hex(accent),
                "hue": round(hue, 2),
                "verified": {
                    "text_on_fill": round(wcag_ratio(text, fill), 2),
                    "text_on_card": round(wcag_ratio(text, card), 2),
                    "accent_on_card": round(wcag_ratio(accent, card), 2),
                },
            }
        scale[name] = entry
    return scale


def main() -> None:
    scales = {"phase": build_scale(PHASE_SOURCE)}
    out = {
        "_meta": {
            "fill_alpha": FILL_ALPHA,
            "text_gate": TEXT_GATE,
            "accent_gate": ACCENT_GATE,
            "card_light": CARD["light"],
            "card_dark": CARD["dark"],
            "note": "hue held from the shipped ramp; lightness and chroma re-derived at the gates",
        },
        "scales": scales,
    }
    (HERE / "palette-L2.json").write_text(json.dumps(out, indent=1) + "\n")

    for scale_name, entries in scales.items():
        print(f"{scale_name}:")
        for name, modes in entries.items():
            light, dark = modes["light"], modes["dark"]
            print(
                f"  {name:10} text {light['text']}/{dark['text']}  accent {light['accent']}/{dark['accent']}"
                f"   t/fill {light['verified']['text_on_fill']:.2f}/{dark['verified']['text_on_fill']:.2f}"
                f"  a/card {light['verified']['accent_on_card']:.2f}/{dark['verified']['accent_on_card']:.2f}",
            )


if __name__ == "__main__":
    main()
