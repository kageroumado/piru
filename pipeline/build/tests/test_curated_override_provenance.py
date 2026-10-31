"""Every curated dose ladder and duration timeline says where its numbers come from.

`piru-curated` outranks every source, so a curated ladder or timeline replaces
dose.wiki's, substance.wiki's and the rest for its route. That is only worth it
when the curated numbers are a real correction. A curated block that sits within
±25% of a source's numbers is deleted instead, and the source ships. What stays
carries one of, per route:

- `doseSource` / `durationSource` — a DOI, PMID or URL that states the numbers;
- `doseReason` / `durationReason` — one line saying why the curated numbers
  override the sources.

Blocks that had neither when this check was introduced are listed in
`curated-override-baseline.json`. The list may only shrink: a block missing from
it fails (cite or explain it), and so does a line naming a block that is now
explained or gone (delete the line).

    python3 pipeline/build/tests/test_curated_override_provenance.py
"""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from sqlite import parse_reference  # noqa: E402

REPO = HERE.parents[2]
CURATED_DIR = REPO / "data/curated/substances"
BASELINE = HERE / "curated-override-baseline.json"

#: (route block, citation field, reason field)
BLOCKS = (
    ("doses", "doseSource", "doseReason"),
    ("duration", "durationSource", "durationReason"),
)


def curated_blocks() -> list[tuple[str, bool, dict]]:
    """`(key, explained, route)` for every non-empty dose or duration block.

    The key is `"<file> | <route> | <unit> | <block>"`, which names one block."""
    out = []
    for fp in sorted(CURATED_DIR.glob("*.json")):
        entry = json.loads(fp.read_text())
        for route in entry.get("routes") or []:
            for block, cite, why in BLOCKS:
                if not route.get(block):
                    continue
                key = f"{fp.name} | {route.get('route')} | {route.get('unit')} | {block}"
                out.append((key, bool(route.get(cite) or route.get(why)), route))
    return out


class TestCuratedOverrideProvenance(unittest.TestCase):
    def setUp(self) -> None:
        self.blocks = curated_blocks()
        self.baseline = set(json.loads(BASELINE.read_text()))

    def test_each_key_names_one_block(self) -> None:
        keys = [k for k, _, _ in self.blocks]
        dupes = sorted({k for k in keys if keys.count(k) > 1})
        self.assertEqual(dupes, [], "two blocks share a key")

    def test_no_new_unexplained_block(self) -> None:
        unexplained = {k for k, explained, _ in self.blocks if not explained}
        self.assertEqual(
            sorted(unexplained - self.baseline),
            [],
            "curated dose/duration blocks with no doseSource/durationSource or "
            "doseReason/durationReason. Cite or explain them — or delete them when a "
            "source is within ±25% — never add them to the baseline",
        )

    def test_baseline_only_shrinks(self) -> None:
        unexplained = {k for k, explained, _ in self.blocks if not explained}
        self.assertEqual(
            sorted(self.baseline - unexplained),
            [],
            f"explained or gone — delete these lines from {BASELINE.name}",
        )

    def test_citations_are_references(self) -> None:
        bad = []
        for key, _, route in self.blocks:
            for _, cite, _ in BLOCKS:
                ref = route.get(cite)
                if ref and parse_reference(ref)[:3] == (None, None, None):
                    bad.append(f"{key}: {cite} {ref!r} is no DOI, PMID or URL")
        self.assertEqual(bad, [], "\n".join(bad))


if __name__ == "__main__":
    unittest.main()
