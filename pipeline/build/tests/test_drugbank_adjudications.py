"""Integrity gate for `data/curated/drugbank-adjudications.json`.

The file is how the catalog says "we already checked this DrugBank disagreement
and ours is right", "this substance honestly has no single half-life", or "this
missing enzyme/metabolite does not apply here". Every list suppresses rows from
`pipeline/audit/compare_to_drugbank.py`, so a stale or sloppy entry hides real
work instead of recording a decision.

The checks:

  1. Every entry is reviewable — a substance and a reason. A bare name list is
     what this file exists NOT to be, because the next reader cannot tell a
     settled question from an unexamined one.
  2. Names are unique within each list, so a second entry can't silently
     override the first's recorded reason.
  3. Every named substance is still in the shipped DB. An entry pointing at
     nothing suppresses nothing and is just rot.
  4. A substance called unresolvable has no half-life row. If one appeared, the
     claim that no honest value exists is now false and the entry must go.
  5. A divergence entry carries a verdict from the fixed vocabulary and, for a
     value we defend, the source that settles it.

Run from the repo root (needs the built DB):
    python3 pipeline/build/tests/test_drugbank_adjudications.py
"""

import json
import sqlite3
import sys
import unittest
from pathlib import Path

_REPO = Path(__file__).resolve().parents[3]
_DB = _REPO / "Piru/Data/piru-substances.sqlite"
_FILE = _REPO / "data/curated/drugbank-adjudications.json"

sys.path.insert(0, str(_REPO / "pipeline/build"))
from sqlite import normalise  # noqa: E402

#: Why a divergence is allowed to stand. Adding one is a deliberate act.
_VERDICTS = {
    "piru_correct",  # our value was verified against a primary source
}


class TestDrugBankAdjudications(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not _FILE.is_file():
            raise unittest.SkipTest(f"{_FILE} not present")
        cls.data = json.loads(_FILE.read_text(encoding="utf-8"))
        cls.divergences = cls.data.get("half_life_divergences", [])
        cls.unresolvable = cls.data.get("half_life_unresolvable", [])
        #: The coverage lists carry no verdict vocabulary of their own — a
        #: substance is either applicable or it is not — so they are checked
        #: only for reviewability, uniqueness, and still existing.
        cls.other = [
            *cls.data.get("enzyme_coverage", []),
            *cls.data.get("metabolite_coverage", []),
        ]
        if not _DB.is_file():
            raise unittest.SkipTest(f"{_DB} not present — run pipeline/fetch-db.sh")
        con = sqlite3.connect(f"file:{_DB}?mode=ro", uri=True)
        cls.names = {}
        for sid, canonical, display in con.execute(
            "SELECT id, canonical_name, display_name FROM substances"
        ):
            cls.names[normalise(canonical)] = sid
            if display:
                cls.names.setdefault(normalise(display), sid)
        for sid, alias in con.execute("SELECT substance_id, alias_normalized FROM aliases"):
            cls.names.setdefault(alias, sid)
        cls.with_half_life = {
            r[0] for r in con.execute("SELECT DISTINCT substance_id FROM half_lives")
        }
        con.close()

    def test_every_entry_is_reviewable(self):
        for entry in [*self.divergences, *self.unresolvable, *self.other]:
            self.assertTrue(
                entry.get("substance", "").strip(), f"entry without a substance: {entry}"
            )
            self.assertTrue(
                len(entry.get("reason", "").strip()) >= 20,
                f"{entry.get('substance')}: reason must say why, not just that",
            )

    def test_names_are_unique_within_each_list(self):
        for label, entries in (
            ("divergences", self.divergences),
            ("unresolvable", self.unresolvable),
            ("enzyme_coverage", self.data.get("enzyme_coverage", [])),
            ("metabolite_coverage", self.data.get("metabolite_coverage", [])),
        ):
            seen = [normalise(e["substance"]) for e in entries]
            self.assertEqual(len(seen), len(set(seen)), f"duplicate substance in {label}")

    def test_every_substance_still_exists(self):
        for entry in [*self.divergences, *self.unresolvable, *self.other]:
            self.assertIn(
                normalise(entry["substance"]),
                self.names,
                f"{entry['substance']}: adjudicated but no longer in the catalog — entry is rot",
            )

    def test_unresolvable_substances_have_no_half_life(self):
        for entry in self.unresolvable:
            sid = self.names.get(normalise(entry["substance"]))
            self.assertNotIn(
                sid,
                self.with_half_life,
                f"{entry['substance']}: has a half-life row now, so 'no honest value exists' is false",
            )

    def test_divergences_carry_a_verdict_and_a_source(self):
        for entry in self.divergences:
            self.assertIn(entry.get("verdict"), _VERDICTS, f"{entry['substance']}: unknown verdict")
            self.assertTrue(
                entry.get("source", "").strip() or "contradicts its own" in entry.get("reason", ""),
                f"{entry['substance']}: defends our value but names no source",
            )


if __name__ == "__main__":
    unittest.main(verbosity=1)
