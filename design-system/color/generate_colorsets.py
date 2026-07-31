#!/usr/bin/env python3
"""generate_colorsets.py — turn a palette definition into Xcode `.colorset`
directories (display-p3, all four appearance slots).

    python3 generate_colorsets.py palette.json --out Shared/Assets.xcassets

**Swift accessors are Xcode's job, not this script's.** With
`ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES`
(`project.pbxproj:395,463`) Xcode emits `Color.Semantic.Caution.text` plus
UIColor/NSColor/ColorResource variants, with real nested namespaces, per-target
bundle resolution, and compile-time checking. A hand-emitted accessor file uses
string lookup, so a typo compiles and silently resolves to a fallback colour at
runtime — strictly worse, so this script no longer offers it.

Design goals (see `design-system/color/asset-catalog-migration.md`
section 4-5 for the full rationale):

  * display-p3 in every emitted colorset, always — this tool exists because
    the app has zero P3 usage today (grep-verified) and 100% sRGB literals.

  * The single biggest P3-migration bug is silently unrepresentable: every
    appearance value MUST declare its representation (`oklch` or `p3_hex`,
    both already in P3 terms). sRGB input support was removed once the last
    sRGB notation left the palette sources — there is deliberately no code
    path that could copy raw sRGB numbers into a `display-p3` slot
    unconverted, the reinterpretation (same numbers, a different, more
    saturated color) that `colorimetry.py`'s module docstring calls "the
    single biggest trap in a P3 migration."

  * Four appearance slots per token: Any, Dark, Any+High-Contrast,
    Dark+High-Contrast. High-contrast slots are optional per token — Xcode
    falls back to the non-HC sibling appearance when one is omitted, so a
    token can ship with just Any/Dark today and grow HC variants later
    without a structural change.

  * Slash-namespaced token names (`semantic/caution/text`) become *real*
    Xcode namespace folders (`semantic/` and `caution/` each get a
    `Contents.json` with `"provides-namespace": true`), not flattened
    filenames — so `Color("semantic/caution/text")` actually resolves. This
    is the part most hand-written colorset scripts get wrong: without
    `provides-namespace`, Xcode treats intermediate folders as pure
    organization and the asset's *name* collapses to just `text`.

  * Idempotent: re-running against an unchanged palette produces
    byte-identical output (sorted keys, fixed-precision float formatting) —
    safe as a CI "is the catalog stale" check.

  * Refuses to touch anything named `AccentColor` — the one hand-authored,
    designer-owned colorset in the app.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from colorimetry import hex_to_rgb, oklch_to_rgb  # noqa: E402

APPEARANCE_SLOTS = ["any", "dark", "any_hc", "dark_hc"]

# Xcode's `appearances` array per slot. `any`/no-key omits the array entirely
# (Xcode's convention for the universal/base entry).
SLOT_APPEARANCES: dict[str, list[dict[str, str]]] = {
    "any": [],
    "dark": [{"appearance": "luminosity", "value": "dark"}],
    "any_hc": [{"appearance": "contrast", "value": "high"}],
    "dark_hc": [
        {"appearance": "luminosity", "value": "dark"},
        {"appearance": "contrast", "value": "high"},
    ],
}


class PaletteError(ValueError):
    pass


def resolve_p3_components(spec: dict) -> tuple[float, float, float, float]:
    """One appearance value -> (r, g, b, a) in display-p3, 0..1.

    `spec` must carry exactly one of:
      - {"oklch": [L, C, h]}   -- interpreted directly in P3 (the palette
        author is expected to have gamut-fit this to P3 already; values
        outside [0,1] after conversion are clipped with a loud warning,
        not silently wrapped).
      - {"p3_hex": "RRGGBB"}   -- already display-p3 components, hex-packed.

    There is intentionally no sRGB input: the palette sources are Oklch/P3
    throughout, and an sRGB path would be one accident away from copying
    unconverted numbers into a display-p3 slot.
    """
    keys = {"oklch", "p3_hex"} & spec.keys()
    if len(keys) != 1:
        raise PaletteError(
            f"appearance spec must have exactly one of oklch/p3_hex, got {spec!r}",
        )
    alpha = float(spec.get("alpha", 1.0))

    if "oklch" in spec:
        lightness, chroma, hue = spec["oklch"]
        rgb = oklch_to_rgb((lightness, chroma, hue), space="p3")
    else:
        rgb = hex_to_rgb(spec["p3_hex"])

    clipped = []
    for c in rgb:
        if c < -1e-4 or c > 1 + 1e-4:
            print(
                f"warning: component {c:.4f} outside [0,1] for {spec!r}, clipping", file=sys.stderr
            )
        clipped.append(min(1.0, max(0.0, c)))
    r, g, b = clipped
    return (r, g, b, alpha)


def _fmt(x: float) -> str:
    return f"{x:.3f}"


def contents_json_entry(
    rgba: tuple[float, float, float, float], appearances: list[dict[str, str]]
) -> dict:
    r, g, b, a = rgba
    entry: dict = {
        "color": {
            "color-space": "display-p3",
            "components": {
                "red": _fmt(r),
                "green": _fmt(g),
                "blue": _fmt(b),
                "alpha": _fmt(a),
            },
        },
        "idiom": "universal",
    }
    if appearances:
        entry["appearances"] = appearances
    return entry


def build_contents_json(token_spec: dict) -> dict:
    if "any" not in token_spec:
        raise PaletteError("every token needs at least an 'any' appearance")
    colors = []
    for slot in APPEARANCE_SLOTS:
        if slot not in token_spec:
            continue  # HC slots (and even 'dark') are optional
        rgba = resolve_p3_components(token_spec[slot])
        colors.append(contents_json_entry(rgba, SLOT_APPEARANCES[slot]))
    return {"colors": colors, "info": {"author": "generate_colorsets.py", "version": 1}}


NAMESPACE_CONTENTS = (
    json.dumps(
        {
            "info": {"author": "generate_colorsets.py", "version": 1},
            "properties": {"provides-namespace": True},
        },
        indent=2,
    )
    + "\n"
)


def write_namespace_folder(path: Path) -> None:
    """A plain organizational folder in the catalog gets `provides-namespace`
    so `token/parent/name` lookups actually include `parent` in the resolved
    asset name, instead of Xcode silently flattening it to just `name`."""
    path.mkdir(parents=True, exist_ok=True)
    contents = path / "Contents.json"
    text = NAMESPACE_CONTENTS
    if not contents.exists() or contents.read_text() != text:
        contents.write_text(text)


def write_colorset(out_dir: Path, token_name: str, token_spec: dict) -> Path:
    parts = token_name.split("/")
    leaf, parents = parts[-1], parts[:-1]
    if leaf == "AccentColor" and not parents:
        raise SystemExit("refusing to write AccentColor -- hand-owned, not generated")

    folder = out_dir
    for parent in parents:
        folder = folder / parent
        write_namespace_folder(folder)

    colorset_dir = folder / f"{leaf}.colorset"
    colorset_dir.mkdir(parents=True, exist_ok=True)
    contents = build_contents_json(token_spec)
    text = json.dumps(contents, indent=2, sort_keys=False) + "\n"
    target = colorset_dir / "Contents.json"
    if not target.exists() or target.read_text() != text:
        target.write_text(text)
    return colorset_dir


# --------------------------------------------------------------------------
# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------


def main() -> None:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument(
        "palette", type=Path, help='palette JSON: {"tokens": {name: {slot: {space: value}}}}'
    )
    ap.add_argument(
        "--out",
        type=Path,
        required=True,
        help="an .xcassets directory (or a scratch dir) to write .colorset folders into",
    )
    args = ap.parse_args()

    if args.out.name == "AccentColor.colorset":
        raise SystemExit("refusing to write directly into AccentColor.colorset")

    palette = json.loads(args.palette.read_text())
    tokens = palette["tokens"]

    args.out.mkdir(parents=True, exist_ok=True)
    written = [write_colorset(args.out, name, spec) for name, spec in tokens.items()]

    print(f"wrote {len(written)} colorsets under {args.out}")
    print("Swift accessors: generated by Xcode from the catalog, not by this script.")


if __name__ == "__main__":
    main()
