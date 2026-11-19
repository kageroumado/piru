#!/usr/bin/env python3
"""palette-L1.json (+ chrome tokens) -> palette-generator-input.json

`palette-L1.json` stores tokens as P3 *components*, which is what the contrast
verification works in. `generate_colorsets.py` wants `oklch` or `p3_hex` per
appearance. This converts between them; nothing here touches sRGB or hex.

Oklch, never hex: hex round-trips through 8 bits, and two route tints that
passed contrast in floating point failed after quantization (4.4988 and 4.5046
against a 4.5 gate). Oklch keeps the precision until Xcode's 3-decimal
component format truncates it, which the contrast test re-verifies at shipped
precision.

Run after editing `palette-L1.json`:

    python3 build_generator_input.py
    python3 generate_colorsets.py palette-generator-input.json --out ../../Shared/Assets.xcassets
"""

from __future__ import annotations

import json
from pathlib import Path

from colorimetry import oklch

HERE = Path(__file__).parent

# Chrome tokens: neutral, no semantic meaning, so they live outside the L1
# ladder. Values are Oklch (L, C, H) per the CLAUDE.md color convention.
CHROME: dict[str, dict[str, tuple[float, float, float]]] = {
    "text/secondary": {
        # Clears 4.5:1 on the real card with headroom past rounding. Measure
        # against the card, never pure white, which flatters the ratio.
        "light": (0.53990, 0.00776, 285.9),
        # What iOS ships: systemGray at 60% over the card (9.97:1).
        "dark": (0.79764, 0.01126, 285.9),
        # Increase Contrast: >= 7:1 on every light surface (7.26 on the grouped
        # gray) and on every dark one (11.45 on the #1C1C1E sheet). Placeholder
        # and tertiary text swap to this token under the setting too, so it is
        # also what they read at.
        "light_hc": (0.43, 0.008, 285.9),
        "dark_hc": (0.87, 0.012, 285.9),
    },
    # Surfaces. As colorsets they get the Any+HC / Dark+HC slots, which a
    # `UIColor { traits }` closure cannot express: it branches on
    # userInterfaceStyle only.
    #
    # The light values are the system colors (`systemBackground` white,
    # `systemGray6`, `systemGroupedBackground`), fixed published values, so
    # pinning them loses nothing. The dark values are the app's OLED choice:
    # the system's own dark surfaces are never true black.
    "surface/background": {"light": (1.0, 0.0, 260.0), "dark": (0.0, 0.0, 0.0)},
    "surface/card": {"light": (0.96257, 0.00676, 285.8), "dark": (0.17764, 0.00002, 260.0)},
    "surface/grouped": {"light": (0.96257, 0.00676, 285.8), "dark": (0.14479, 0.00002, 260.0)},
    "surface/input": {"light": (0.96257, 0.00676, 285.8), "dark": (0.22771, 0.00577, 285.8)},
}


def main() -> None:
    palette = json.loads((HERE / "palette-L1.json").read_text())
    tokens: dict[str, dict] = {}

    for key, value in palette["tokens"].items():
        name = key.split("/")[1]
        for role in ("text", "accent"):
            tokens[f"semantic/{name}/{role}"] = {
                appearance_slot: {
                    "oklch": [round(x, 5) for x in oklch(tuple(value[mode][f"{role}_p3"]), "p3")]
                }
                for mode, appearance_slot in (("light", "any"), ("dark", "dark"))
            }

    for name, modes in CHROME.items():
        tokens[name] = {
            "any": {"oklch": list(modes["light"])},
            "dark": {"oklch": list(modes["dark"])},
        }
        if "light_hc" in modes:
            tokens[name]["any_hc"] = {"oklch": list(modes["light_hc"])}
            tokens[name]["dark_hc"] = {"oklch": list(modes["dark_hc"])}

    # L2 encoding scales, built by build_l2_scales.py with the same gates as
    # L1. Every value is {"p3": [r, g, b]} components; they pass through as
    # oklch so the generator's own P3 conversion is a no-op in gamut terms.
    def l2_spec(value: dict) -> dict:
        return {"oklch": [round(x, 5) for x in oklch(tuple(value["p3"]), "p3")]}

    l2_path = HERE / "palette-L2.json"
    if l2_path.exists():
        for scale, entries in json.loads(l2_path.read_text())["scales"].items():
            for step, modes in entries.items():
                for role in ("text", "accent"):
                    token = {
                        "any": l2_spec(modes["light"][role]),
                        "dark": l2_spec(modes["dark"][role]),
                    }
                    # Increase Contrast. Never move these back into a
                    # `UIColor { traits }` closure: it branches on
                    # userInterfaceStyle alone and cannot express a contrast axis.
                    if f"{role}_hc" in modes["light"]:
                        token["any_hc"] = l2_spec(modes["light"][f"{role}_hc"])
                        token["dark_hc"] = l2_spec(modes["dark"][f"{role}_hc"])
                    tokens[f"{scale}/{step}/{role}"] = token

    # Skins. Each skin is a namespace under `skin/<id>/` carrying its own
    # surfaces, text, accent and semantic overrides, so a skin gets the same
    # Any/Dark slots (and the same contrast gate) as the default tokens.
    # `Skin.swift` switches on the skin and reads the generated symbols.
    skins_path = HERE / "palette-skins.json"
    if skins_path.exists():
        for skin_id, skin_tokens in json.loads(skins_path.read_text())["skins"].items():
            for name, modes in skin_tokens.items():
                tokens[f"skin/{skin_id}/{name}"] = {
                    "any": {"oklch": list(modes["light"])},
                    "dark": {"oklch": list(modes["dark"])},
                }

    out = HERE / "palette-generator-input.json"
    out.write_text(json.dumps({"tokens": tokens}, indent=1) + "\n")
    print(f"wrote {len(tokens)} tokens to {out.name}")
    for name in tokens:
        print(f"  {name}")


if __name__ == "__main__":
    main()
