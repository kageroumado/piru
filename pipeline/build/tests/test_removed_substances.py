"""Integrity gate for the adjudicated removal list (`data/curated/removed-substances.json`).

The list is how the catalog says "this is not a substance anyone doses" or "this
row's only content was a banner saying it had no content". It exists because both
failure modes recur: a scraper re-adds a diagnostic analyte or a cosmetic-cream
peptide, or somebody hand-writes a curated file whose whole payload is the
sentence "No published human pharmacology". Without a gate the removal silently
reverts on the next upstream refresh and nobody notices, because the symptom is
an extra row in a 1,700-row catalog.

The checks:

  1. Every entry is reviewable — name, a verdict from the fixed vocabulary, a
     reason, and evidence. A bare name list is what this file exists NOT to be.
  2. No removed name is back in the shipped DB.
  3. No removed name still has a curated file. The curated file is usually what
     kept an empty row alive (it protects rows from `drop_orphan_stubs`), so
     leaving one behind resurrects the entry's aliases and category.
  4. Every `supersededBy` survivor actually exists — a duplicate removal that
     points at nothing is data loss, not a merge.
  5. Names are unique, so a second entry can't silently override the first's
     recorded reason.

Run from the repo root (needs the built DB):
    python3 pipeline/build/tests/test_removed_substances.py
"""

import json
import sqlite3
import unittest
from pathlib import Path

_REPO = Path(__file__).resolve().parents[3]
_DB = _REPO / "Piru/Data/piru-substances.sqlite"
_LIST = _REPO / "data/curated/removed-substances.json"
_CURATED_DIR = _REPO / "data/curated/substances"

#: The removal rationales. Adding a verdict here is a deliberate act — each one
#: is a different argument for why a row should not ship, and each demands its own
#: kind of evidence — see the reason/evidence fields on the entries themselves.
_VERDICTS = {
    "not_a_substance",  # reagent, diagnostic analyte, cosmetic ingredient,
    # class name, protonated-cation record, vendor SKU
    "no_relevant_activity",  # real molecule, no activity a dose tracker can model
    "no_content",  # real compound, zero pharmacology in the catalog
    "catalog_noise",  # paper/patent/trial-only, never in human circulation
    "duplicate",  # same molecule as a populated survivor
}


def _normalise(name: str) -> str:
    """Case/space-insensitive key, matching how the build compares names."""
    return "".join(ch for ch in name.lower() if ch.isalnum())


class TestRemovedSubstances(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not _LIST.is_file():
            raise unittest.SkipTest(f"{_LIST} not present")
        cls.entries = json.loads(_LIST.read_text())["removed"]
        cls.db = sqlite3.connect(f"file:{_DB}?mode=ro", uri=True)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.db.close()

    def test_every_entry_is_reviewable(self) -> None:
        """A removal without a reason and evidence is indistinguishable from a
        mistake, and cannot be re-litigated later."""
        bad = []
        for entry in self.entries:
            name = entry.get("name") or "<unnamed>"
            for field in ("name", "verdict", "reason", "evidence"):
                if not (entry.get(field) or "").strip():
                    bad.append(f"{name}: missing {field}")
            verdict = entry.get("verdict")
            if verdict is not None and verdict not in _VERDICTS:
                bad.append(f"{name}: unknown verdict {verdict!r}")
        self.assertEqual(bad, [], "removal entries missing required fields")

    def test_names_are_unique(self) -> None:
        seen: dict[str, str] = {}
        dupes = []
        for entry in self.entries:
            key = _normalise(entry["name"])
            if key in seen:
                dupes.append(f"{entry['name']} (also {seen[key]})")
            seen[key] = entry["name"]
        self.assertEqual(dupes, [], "duplicate names in the removal list")

    def test_removed_names_are_absent_from_the_db(self) -> None:
        """The whole point of the file. A name back in the catalog means an
        upstream refresh reintroduced it and the drop step did not fire."""
        live = {_normalise(r[0]) for r in self.db.execute("SELECT canonical_name FROM substances")}
        back = sorted(e["name"] for e in self.entries if _normalise(e["name"]) in live)
        self.assertEqual(back, [], "removed substances are back in the shipped DB")

    def test_no_removed_name_still_has_a_curated_file(self) -> None:
        """A leftover curated file re-seeds the row's aliases and category, and
        protects it from the orphan-stub drop."""
        targets = {_normalise(e["name"]) for e in self.entries}
        stale = []
        for path in sorted(_CURATED_DIR.glob("*.json")):
            try:
                name = (json.loads(path.read_text()) or {}).get("name")
            except (ValueError, OSError):
                continue
            if name and _normalise(name) in targets:
                stale.append(f"{path.name} ({name})")
        self.assertEqual(stale, [], "curated files exist for removed substances")

    def test_duplicate_removals_name_a_surviving_substance(self) -> None:
        """`supersededBy` is the promise that the data went somewhere. If the
        survivor is missing, the removal deleted the only copy."""
        missing = []
        for entry in self.entries:
            survivor = entry.get("supersededBy")
            if not survivor:
                if entry["verdict"] == "duplicate":
                    missing.append(f"{entry['name']}: duplicate with no supersededBy")
                continue
            row = self.db.execute(
                "SELECT 1 FROM substances WHERE canonical_name = ? COLLATE NOCASE",
                (survivor,),
            ).fetchone()
            if row is None:
                missing.append(f"{entry['name']}: survivor {survivor!r} not in the DB")
        self.assertEqual(missing, [], "duplicate removals point at a missing survivor")


if __name__ == "__main__":
    unittest.main(verbosity=2)
