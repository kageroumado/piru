#!/usr/bin/env python3
"""palette-L1.json (+ chrome tokens) -> palette-generator-input.json

`palette-L1.json` stores tokens as P3 *components*, which is what the contrast
verification works in. `generate_colorsets.py` wants `oklch` or `p3_hex` per
appearance. This converts between them; nothing here touches sRGB or hex.

**Oklch, not hex, is deliberate.** Hex round-trips through 8 bits, and that has
already cost us: two route tints passed contrast in floating point and failed
after quantisation (4.4988 and 4.5046 against a 4.5 gate). Oklch keeps the
precision until Xcode's own 3-decimal component format truncates it, which the
contrast test then re-verifies at shipped precision.

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
# ladder. Values are Oklch (L, C, H) per the CLAUDE.md colour convention; see
# the note on each for why it is what it is.
CHROME: dict[str, dict[str, tuple[float, float, float]]] = {
    "text/secondary": {
        # Was #7A7A80 / #A6A6AD. The light value measured 3.89:1 on the real
        # card -- a WCAG AA failure across ~566 call sites, and the original
        # audit missed it by computing against pure white. Darkened to clear
        # 4.5:1 with headroom past rounding.
        "light": (0.53990, 0.00776, 285.9),
        # The old dark override was *worse* than the system colour (7.79 vs
        # 9.97), so this adopts what iOS ships: systemGray at 60% over the card.
        "dark": (0.79764, 0.01126, 285.9),
    },
    # Surfaces. These existed as `UIColor { traits }` closures, which branch on
    # userInterfaceStyle only and therefore cannot express high contrast at all.
    # As colorsets they gain the Any+HC / Dark+HC slots.
    #
    # The light values are the system colours the closures already resolved to
    # (`systemBackground` white, `systemGray6`, `systemGroupedBackground`) --
    # fixed published values, so pinning them loses nothing. The dark values
    # are the app's deliberate OLED choice, which is *why* the closures
    # existed: the system's own dark surfaces are never true black.
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
                    # Increase Contrast. The app had no response to this setting
                    # at all before the catalog migration, and could not have —
                    # a `UIColor { traits }` closure branches on
                    # userInterfaceStyle alone and cannot express a contrast
                    # axis. These slots are the point of the whole migration.
                    if f"{role}_hc" in modes["light"]:
                        token["any_hc"] = l2_spec(modes["light"][f"{role}_hc"])
                        token["dark_hc"] = l2_spec(modes["dark"][f"{role}_hc"])
                    tokens[f"{scale}/{step}/{role}"] = token

    out = HERE / "palette-generator-input.json"
    out.write_text(json.dumps({"tokens": tokens}, indent=1) + "\n")
    print(f"wrote {len(tokens)} tokens to {out.name}")
    for name in tokens:
        print(f"  {name}")


if __name__ == "__main__":
    main()
