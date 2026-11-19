#!/usr/bin/env python3
"""Generate the L2 encoding scales -> palette-L2.json

L2 scales are multi-valued but still meaning-bearing (experience phases, routes,
dose tiers). They get the *same* treatment as the L1 semantic tokens — a `text`
variant gated at WCAG AA against both the card and its own fill, and an `accent`
variant gated at the 3:1 non-text floor, because they fail the same way. The
phase ramp, for instance, renders its color as `.caption` text on a capsule
filled with that same color (`DosePhaseProgressBar`), the self-tint pattern
that most often falls below AA.

Hue is held from the source values: these scales encode meaning through hue
and users have learned them, so only lightness and chroma move. Each token
keeps its source hue to within a degree.

Chroma is maximized at each gate, as `palette-L1.json` is built, so `accent`
lands at the vivid end. Taking the first lightness that passes instead gives a
dark-mode accent darker than its own text.

    python3 build_l2_scales.py
"""

from __future__ import annotations

import json
from pathlib import Path

from colorimetry import (
    composite,
    fit_chroma,
    oklch,
    oklch_to_rgb,
    wcag_ratio,
)

HERE = Path(__file__).parent
CATEGORY_SEEDS_SWIFT = HERE.parents[1] / "Piru" / "Domain" / "SubstanceCategory+OklchSeed.swift"

# Every color in this file is Oklch (L, C, H), per the CLAUDE.md color
# convention: the numbers mean what a viewer sees, and Oklab dE between two
# entries is a perceived distance. Gamut fitting and gate arithmetic happen in
# Display P3, the panel gamut of every consuming device.
SPACE = "p3"

# The app card surfaces. They are near-neutral, so the gamut is irrelevant, but
# the gates must compare candidate and surface in the same space.
CARD = {"light": (0.97015, 0.00012, 260.0), "dark": (0.17764, 0.00002, 260.0)}


def quantize(rgb: tuple) -> tuple:
    """Round to the precision the catalog ships, Xcode's three-decimal P3
    components, so the gates verify the shipped value rather than a float that
    rounds the wrong way."""
    return tuple(round(c, 3) for c in rgb)


def encode(rgb: tuple) -> dict:
    """Serialize a gated color for palette-L2.json: P3 components, the same
    {"p3": [...]} shape the family scale uses, which build_generator_input
    passes through without ever leaving the P3 gamut."""
    return {"p3": [round(c, 4) for c in rgb]}


FILL_ALPHA = 0.10
TEXT_GATE = 4.55  # headroom over 4.5 so 8-bit quantization cannot drop under
ACCENT_GATE = 3.05

# High-contrast variants, emitted into the catalog's Any+HC / Dark+HC slots.
# WCAG AAA for text (7:1) and AA-for-text for marks (4.5:1) -- one full step up
# from the default gates, which is what "Increase Contrast" should mean.
TEXT_GATE_HC = 7.05
ACCENT_GATE_HC = 4.55

# Source hues, taken from the ramp already shared by TimelineGraphView,
# SessionReportPDF and DosePhaseProgressBar. Keep one phase ramp: with two,
# "peak" changed color between editing a dose and reading it.
PHASE_SOURCE: dict[str, tuple[float, float, float]] = {
    "onset": (0.691, 0.009, 285.9),
    "comeup": (0.642, 0.167, 254.8),
    "peak": (0.730, 0.194, 147.5),
    "offset": (0.782, 0.171, 67.2),
    # `afterglow` deliberately reuses onset's neutral: the arc opens and closes
    # quiet.
    "afterglow": (0.691, 0.009, 285.9),
}


# Route tints. Hue comes from the dark value of each source pair, the
# designer-chosen hue; the light value was hand-darkened for contrast and its
# hue drifted.
#
# Keep the pill fill at the standard 0.10 alpha. At 0.16, a color on a tint of
# itself tops out around 4.5:1 whatever its lightness, so dark mode cannot pass.
ROUTE_SOURCE: dict[str, tuple[float, float, float]] = {
    "oral": (0.624, 0.206, 255.5),
    "sublingual": (0.700, 0.111, 212.8),
    "buccal": (0.748, 0.130, 189.1),
    "insufflation": (0.615, 0.213, 312.4),
    "inhalation": (0.765, 0.175, 62.6),
    "intravenous": (0.654, 0.232, 28.7),
    "intramuscular": (0.650, 0.238, 17.9),
    "subcutaneous": (0.556, 0.203, 278.1),
    "transdermal": (0.730, 0.194, 147.5),
    "rectal": (0.632, 0.064, 72.8),
    "other": (0.648, 0.007, 285.9),
}


# Dose intensity, one scale for every dose-tier surface.
#
# Cold to hot: ice → slate → periwinkle → purple → magenta → red. Hue is
# strictly monotonic and chroma rises with the tier, so "colder = milder" holds
# at both ends and `sub` is a faint icy blue. Never add yellow or green: yellow
# at mid-ramp lightness is gamut-capped into mud, and green implies that a
# light dose is a safe one. Comparison sheet: dose-ramp.html.
#
# Seeds are Oklch (L, C, H), gamut-fit in Display P3. Only C (the chroma
# ceiling) and H survive gating; L is where the seed sat when chosen.
DOSE_SOURCE: dict[str, tuple[float, float, float]] = {
    "sub": (0.650, 0.050, 248.0),
    "threshold": (0.653, 0.106, 263.4),
    "light": (0.620, 0.161, 291.9),
    "common": (0.612, 0.190, 320.0),
    "strong": (0.624, 0.217, 351.4),
    "heavy": (0.636, 0.192, 31.1),
}


# Evidence quality. `ConfidenceBadge` and `ProvenanceBadge` render the same
# green -> yellow -> orange -> gray ramp. It is an ordered trust grade, so it
# stays out of `semantic/*`: "medium confidence" is not a caution.
CONFIDENCE_SOURCE: dict[str, tuple[float, float, float]] = {
    "high": (0.730, 0.194, 147.5),
    "medium": (0.865, 0.177, 90.4),
    "low": (0.765, 0.175, 62.6),
    "unverified": (0.648, 0.007, 285.9),
}


# Interaction severity. An ordered three-step trust-in-danger ladder, which is
# why it is a scale and not three `semantic/*` lookups: `.unsafe` sits between
# caution and danger, and the four-level semantic ladder has no middle tier.
SEVERITY_SOURCE: dict[str, tuple[float, float, float]] = {
    "caution": (0.865, 0.177, 90.4),
    "unsafe": (0.765, 0.175, 62.6),
    "dangerous": (0.654, 0.232, 28.7),
}


# Substance categories: a nominal scale, one step per category. Its steps
# cannot all be mutually distinguishable on one hue wheel, and they need not
# be: a category badge always carries its name. So this scale is exempt from
# the distinctness floor the smaller scales hold to.
CATEGORY_SOURCE: dict[str, tuple[float, float, float]] = {
    "stimulant": (0.765, 0.175, 62.6),
    "psychedelic": (0.615, 0.213, 312.4),
    "dissociative": (0.707, 0.133, 233.9),
    "dysdelic": (0.493, 0.132, 333.7),
    "deliriant": (0.579, 0.058, 94.6),
    "opioid": (0.654, 0.232, 28.7),
    "benzodiazepine": (0.603, 0.218, 257.4),
    "gabapentinoid": (0.529, 0.191, 278.3),
    "empathogen": (0.650, 0.238, 17.9),
    "cannabinoid": (0.730, 0.194, 147.5),
    "nootropic": (0.700, 0.111, 212.8),
    "ampakine": (0.812, 0.156, 138.5),
    "eugeroic": (0.807, 0.137, 76.4),
    "depressant": (0.638, 0.073, 261.5),
    "orexinAntagonist": (0.537, 0.117, 287.8),
    "antidepressant": (0.865, 0.177, 90.4),
    "antipsychotic": (0.748, 0.130, 189.1),
    "analgesic": (0.632, 0.064, 72.8),
    "antihistamine": (0.636, 0.092, 356.7),
    "cardiovascular": (0.697, 0.193, 26.6),
    "antimicrobial": (0.766, 0.094, 207.8),
    "gastrointestinal": (0.811, 0.152, 70.2),
    "respiratory": (0.767, 0.108, 230.4),
    "endocrine": (0.701, 0.162, 313.4),
    "immunological": (0.670, 0.177, 255.7),
    "supplement": (0.778, 0.161, 150.2),
    "peptide": (0.702, 0.100, 244.0),
    "anticonvulsant": (0.693, 0.114, 298.9),
    "other": (0.648, 0.007, 285.9),
}


# Library families. These fill `FamilyGradientCard` backgrounds with white text
# over them. Every pair clears Oklab dE 0.08 (comparison sheet:
# family-tuning.html); peptides and research use orchid and coral, whose chroma
# lies outside sRGB.
#
# Values are Display P3 components: the catalog is P3 throughout and every
# consuming device has a P3 panel.
FAMILY_SOURCE: dict[str, tuple[float, float, float]] = {
    "common": (0.3433, 0.3526, 0.7355),
    "stimulant": (0.9433, 0.6044, 0.2176),
    "empathogen": (0.9198, 0.2684, 0.3520),
    "hallucinogen": (0.4812, 0.1903, 0.7333),
    "cannabinoid": (0.3076, 0.6798, 0.3097),
    "opioid": (0.9213, 0.3045, 0.2405),
    "sedative": (0.2046, 0.4710, 0.9661),
    "peptide": (0.8062, 0.3476, 0.7568),
    "mind": (0.2291, 0.4637, 0.5141),
    "pharmaceutical": (0.5206, 0.3873, 0.5170),
    "supplement": (0.2981, 0.6605, 0.5442),
    "research": (0.8774, 0.4905, 0.3351),
    "other": (0.3904, 0.3996, 0.4213),
}


def max_chroma(hue: float, gate, background, ceiling: float = 1.0) -> tuple[float, float, tuple]:
    """Highest-chroma color at `hue` satisfying `gate(color)`, up to `ceiling`.

    Scans every lightness and keeps the best, rather than returning the first
    that passes (see the module note).

    `ceiling` exists because saturation carries meaning *within* a scale. Routes
    include both a vivid orange (inhalation, from `#FF9500`) and a deliberately
    muted brown (rectal, from `#A2845E`) only three degrees of hue apart. Letting
    both run to the gamut edge collapses them from Oklab dE 0.069 to 0.026,
    indistinguishable on a small pill. Capping each token at its own source
    chroma keeps a muted step muted.
    """
    # Chroma outermost, descending: the first hit is the most saturated value
    # that passes. Lightness scans toward the surface, so among equal-chroma
    # candidates the one nearest the background wins, the smallest excursion
    # that clears the gate. Never scan away from the surface: that returns the
    # most extreme passing value (`rectal` becomes a near-black brown at 12:1
    # against a 4.55 gate).
    dark_surface = wcag_ratio(background, (1.0, 1.0, 1.0), SPACE) > 2.0
    lightness_steps = range(1, 200) if dark_surface else range(199, 0, -1)

    for j in range(80, 0, -1):
        chroma = j / 200
        if chroma > ceiling:
            continue
        for i in lightness_steps:
            lightness = i / 200
            lch = fit_chroma((lightness, chroma, hue), SPACE)
            if abs(lch[1] - chroma) > 1e-3:
                continue  # gamut-clamped at this lightness
            candidate = quantize(oklch_to_rgb(lch, SPACE))  # quantize, then test
            if gate(candidate):
                return (chroma, lightness, candidate)
    raise ValueError(f"no colour at hue {hue} satisfies the gate on {background}")


# Below this chroma a color is a neutral and its hue is noise: a near-gray
# reports a hue of ~286 degrees, and maximizing chroma there turns it vivid
# purple. Neutrals keep their hue but never gain chroma.
NEUTRAL_CHROMA = 0.02


def build_neutral(hue: float, chroma: float) -> dict[str, dict]:
    """A neutral step: hold the (tiny) source chroma, move lightness only."""
    entry: dict[str, dict] = {}
    for mode, card_oklch in CARD.items():
        card = oklch_to_rgb(card_oklch, SPACE)

        def at(lightness: float) -> tuple:
            return quantize(oklch_to_rgb(fit_chroma((lightness, chroma, hue), SPACE), SPACE))

        steps = [i / 200 for i in range(1, 200)]
        if mode == "light":
            steps.reverse()  # prefer the lightest value that still passes
        accent = next(c for c in map(at, steps) if wcag_ratio(c, card, SPACE) >= ACCENT_GATE)
        fill = composite(accent, FILL_ALPHA, card, SPACE)
        text = next(
            c
            for c in map(at, steps)
            if wcag_ratio(c, fill, SPACE) >= TEXT_GATE and wcag_ratio(c, card, SPACE) >= TEXT_GATE
        )
        entry[mode] = {
            "text": encode(text),
            "accent": encode(accent),
            "hue": round(hue, 2),
            "neutral": True,
            "verified": {
                "text_on_fill": round(wcag_ratio(text, fill, SPACE), 2),
                "text_on_card": round(wcag_ratio(text, card, SPACE), 2),
                "accent_on_card": round(wcag_ratio(accent, card, SPACE), 2),
            },
        }
    return entry


def build_family(source: dict[str, tuple[float, float, float]]) -> dict[str, dict]:
    """Library family colors, passed through unchanged.

    These fill large decorative gradient cards
    (`color -> color.mix(with: .white, by: 0.35)`) with white text over them, so
    the surface is not the app card and the usual gates do not apply.

    Do not gate them. Gating at 3:1 against the app card settles on the palest
    passing value, and gating for white-on-the-gradient forces orange and green
    almost to black, because those hues cannot be both vivid and dark (orange
    sits at Oklab L ~0.78; lowered far enough for white text it is brown).
    `FamilyGradientCard` lifts its white text off the gradient with a shadow
    instead, which keeps it legible without touching hue. This is the one
    scale in the system whose values are hand-chosen and ungated.

    Source entries are Display P3 component tuples; they serialize as
    {"p3": [r, g, b]}.
    """
    scale: dict[str, dict] = {}
    for name, src in source.items():
        _, _, hue = oklch(src, "p3")
        value = {"p3": [round(component, 4) for component in src]}
        scale[name] = {
            mode: {
                "text": value,
                "accent": value,
                "text_hc": value,
                "accent_hc": value,
                "hue": round(hue, 2),
                "ungated": "decorative gradient card; legibility comes from the text shadow",
            }
            for mode in CARD
        }
    return scale


def build_scale(source: dict[str, tuple[float, float, float]]) -> dict[str, dict]:
    scale: dict[str, dict] = {}
    for name, seed in source.items():
        _, source_chroma, hue = seed  # Oklch: L is documentary, C caps chroma, H is held
        if source_chroma < NEUTRAL_CHROMA:
            scale[name] = build_neutral(hue, source_chroma)
            continue
        entry: dict[str, dict] = {}
        for mode, card_oklch in CARD.items():
            card = oklch_to_rgb(card_oklch, SPACE)
            # Bind `card` / `fill` as defaults rather than closing over the loop
            # variable: a late-bound closure would silently gate every mode
            # against whichever surface the loop happened to end on.
            _, _, accent = max_chroma(
                hue, lambda c, bg=card: wcag_ratio(c, bg, SPACE) >= ACCENT_GATE, card, source_chroma
            )
            fill = composite(accent, FILL_ALPHA, card, SPACE)
            _, _, text = max_chroma(
                hue,
                lambda c, f=fill, bg=card: (
                    wcag_ratio(c, f, SPACE) >= TEXT_GATE and wcag_ratio(c, bg, SPACE) >= TEXT_GATE
                ),
                card,
                source_chroma,
            )
            _, _, accent_hc = max_chroma(
                hue,
                lambda c, bg=card: wcag_ratio(c, bg, SPACE) >= ACCENT_GATE_HC,
                card,
                source_chroma,
            )
            fill_hc = composite(accent_hc, FILL_ALPHA, card, SPACE)
            _, _, text_hc = max_chroma(
                hue,
                lambda c, f=fill_hc, bg=card: (
                    wcag_ratio(c, f, SPACE) >= TEXT_GATE_HC
                    and wcag_ratio(c, bg, SPACE) >= TEXT_GATE_HC
                ),
                card,
                source_chroma,
            )
            entry[mode] = {
                "text": encode(text),
                "accent": encode(accent),
                "text_hc": encode(text_hc),
                "accent_hc": encode(accent_hc),
                "hue": round(hue, 2),
                "verified": {
                    "text_on_fill": round(wcag_ratio(text, fill, SPACE), 2),
                    "text_on_card": round(wcag_ratio(text, card, SPACE), 2),
                    "accent_on_card": round(wcag_ratio(accent, card, SPACE), 2),
                },
            }
        scale[name] = entry
    return scale


def write_category_seeds_swift() -> None:
    """CATEGORY_SOURCE as a Swift table, so the app's substance-color generator
    draws its hues from the same seeds the category colorsets are built from."""
    rows = "\n".join(
        f"        case .{name}: Oklch(l: {lightness}, c: {chroma}, h: {hue})"
        for name, (lightness, chroma, hue) in CATEGORY_SOURCE.items()
    )
    CATEGORY_SEEDS_SWIFT.write_text(
        "// Generated by design-system/color/build_l2_scales.py from CATEGORY_SOURCE.\n"
        "// Edit the seeds there and re-run it.\n"
        "\n"
        "nonisolated extension SubstanceCategory {\n"
        "    /// The Oklch seed the category's colorset is derived from.\n"
        "    var oklchSeed: Oklch {\n"
        "        switch self {\n"
        f"{rows}\n"
        "        }\n"
        "    }\n"
        "}\n"
    )


def main() -> None:
    scales = {
        "phase": build_scale(PHASE_SOURCE),
        "route": build_scale(ROUTE_SOURCE),
        "dose": build_scale(DOSE_SOURCE),
        "confidence": build_scale(CONFIDENCE_SOURCE),
        "severity": build_scale(SEVERITY_SOURCE),
        "category": build_scale(CATEGORY_SOURCE),
        "family": build_family(FAMILY_SOURCE),
    }
    out = {
        "_meta": {
            "fill_alpha": FILL_ALPHA,
            "text_gate": TEXT_GATE,
            "accent_gate": ACCENT_GATE,
            "card_light": list(CARD["light"]),
            "card_dark": list(CARD["dark"]),
            "note": "Oklch seeds, gamut-fit and gated in Display P3; hue held, lightness and chroma re-derived at the gates",
        },
        "scales": scales,
    }
    (HERE / "palette-L2.json").write_text(json.dumps(out, indent=1) + "\n")
    write_category_seeds_swift()

    def show(value: dict) -> str:
        """A {"p3": [...]} value as compact Oklch, the notation of this file."""
        lightness, chroma, hue = oklch(tuple(value["p3"]), "p3")
        return f"L{lightness:.2f} C{chroma:.3f} H{hue:5.1f}"

    for scale_name, entries in scales.items():
        print(f"{scale_name}:")
        for name, modes in entries.items():
            light, dark = modes["light"], modes["dark"]
            v = light.get("verified")
            if v is None:
                print(f"  {name:16} {show(light['accent'])}   ungated — {light['ungated']}")
                continue
            print(
                f"  {name:16} text {show(light['text'])} | {show(dark['text'])}"
                f"   t/fill {v['text_on_fill']:.2f}/{dark['verified']['text_on_fill']:.2f}"
                f"  a/card {v['accent_on_card']:.2f}/{dark['verified']['accent_on_card']:.2f}",
            )


if __name__ == "__main__":
    main()
