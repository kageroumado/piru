"""Tests for the waiver plumbing in pipeline/audit/pk_sanity.py.

The gate and the Swift EliminationConsistencyTests read one allowlist file, so
what needs pinning is the seam between them: which entries this gate honors,
and that a waived substance stops gating. Never give this gate a waiver list of
its own — two lists drift silently, and the symptom is CI red on main for a
contradiction somebody already explained in the other one.

No database and no network — every input is a literal.

Run from the repo root:
    python3 pipeline/audit/tests/test_pk_sanity.py
"""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    "pk_sanity", Path(__file__).resolve().parent.parent / "pk_sanity.py"
)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)


def _allowlist(entries) -> Path:
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
        json.dump({"entries": entries}, handle)
    return Path(handle.name)


class LoadWaivers(unittest.TestCase):
    def test_only_the_halflife_pk_pair_applies(self):
        """`override` entries compare the felt-effect ke patch, not these columns."""
        path = _allowlist(
            [
                {"name": "adrafinil", "pair": "halflife-pk", "note": "prodrug"},
                {"name": "heroin", "pair": "override", "note": "ke patch"},
            ]
        )
        self.assertEqual(_mod.load_waivers(path), {"adrafinil": "prodrug"})

    def test_names_are_lowercased(self):
        """The allowlist writes `adrafinil`; the DB's canonical name is `Adrafinil`."""
        path = _allowlist([{"name": "Buprenorphine", "pair": "halflife-pk", "note": "n"}])
        self.assertEqual(_mod.load_waivers(path), {"buprenorphine": "n"})

    def test_a_missing_file_waives_nothing(self):
        self.assertEqual(_mod.load_waivers(Path("/nonexistent/allowlist.json")), {})


class Findings(unittest.TestCase):
    HALF_LIVES = {"Adrafinil": [900.0]}
    PK_ROUTES = {"Adrafinil": [("oral", 60.0)]}

    def _row(self, waivers):
        rows = _mod.findings(self.HALF_LIVES, self.PK_ROUTES, 2.0, waivers)
        self.assertEqual(len(rows), 1)
        return rows[0]

    def test_a_lone_route_leaves_the_disagreement_unexplained(self):
        row = self._row({})
        self.assertEqual(row["ratio"], 15.0)
        self.assertFalse(row["route_explained"])
        self.assertFalse(row["waived"])

    def test_a_waiver_matches_across_case(self):
        self.assertTrue(self._row({"adrafinil": "prodrug"})["waived"])

    def test_agreement_within_the_threshold_is_not_a_finding(self):
        rows = _mod.findings({"X": [100.0]}, {"X": [("oral", 60.0)]}, 2.0, {})
        self.assertEqual(rows, [])

    def test_the_most_charitable_pairing_wins(self):
        """Two half_lives rows: a finding means NO pairing of the columns agrees."""
        rows = _mod.findings({"X": [900.0, 70.0]}, {"X": [("oral", 60.0)]}, 2.0, {})
        self.assertEqual(rows, [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
