"""The per-substance curated mechanism records in data/curated/mechanisms.json.

Every record must parse, name its receptor actions in the vocabulary the app
decodes (an action outside `BindingAction` renders as an unlabelled affinity),
and cite by identifier — a reference that parses to neither a DOI nor a PMID
is a label the citation gates cannot verify.

The estradiol record gets its own checks: it is the first record authored from
read abstracts under the "never a number nobody read" rule, so its shape — two
named receptor subtypes, the ester → estradiol hydrolysis, the depot kinetics —
is pinned here so a later edit cannot quietly drop a citation.

    python3 pipeline/build/tests/test_curated_mechanisms.py
"""

import importlib.util
import json
import sqlite3
import unittest
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    "sqlite_build", Path(__file__).resolve().parent.parent / "sqlite.py"
)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
parse_reference = _mod.parse_reference
normalise = _mod.normalise
normalise_binding_action = _mod.normalise_binding_action
BINDING_ACTIONS = _mod.BINDING_ACTIONS

_REPO = Path(__file__).resolve().parents[3]
MECHANISMS = _REPO / "data/curated/mechanisms.json"
BUNDLED_DB = _REPO / "Piru/Data/piru-substances.sqlite"


def _records() -> list[dict]:
    return json.loads(MECHANISMS.read_text())


def _identifier(ref: str) -> tuple:
    doi, pmid, _url, _title = parse_reference(ref)
    return (doi, pmid)


class EveryRecord(unittest.TestCase):
    def test_names_and_summaries_are_present(self):
        for rec in _records():
            self.assertTrue(rec.get("name"), f"record without a name: {rec}")
            self.assertTrue(
                rec.get("summary") or rec.get("description"),
                f"{rec['name']}: no summary or description",
            )

    def test_binding_actions_decode_and_tiers_are_ordinal(self):
        for rec in _records():
            for b in rec.get("bindings") or []:
                action, _note = normalise_binding_action(b.get("action"))
                self.assertIn(action, BINDING_ACTIONS, f"{rec['name']}: {b}")
                self.assertIn(b.get("affinity_tier"), (1, 2, 3), f"{rec['name']}: {b}")

    def test_references_are_identifiers(self):
        for rec in _records():
            for ref in rec.get("references") or []:
                self.assertNotEqual(
                    _identifier(ref), (None, None), f"{rec['name']}: {ref!r} is not a DOI or PMID"
                )


class Estradiol(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        matches = [r for r in _records() if r.get("name") == "Estradiol"]
        assert len(matches) == 1, f"expected one Estradiol record, found {len(matches)}"
        cls.rec = matches[0]

    def test_both_receptor_subtypes_are_agonised(self):
        bindings = {b["target"]: b for b in self.rec["bindings"]}
        self.assertEqual(set(bindings), {"Estrogen receptor α", "Estrogen receptor β"})
        for b in bindings.values():
            self.assertEqual(b["action"], "agonist")
            self.assertEqual(b["affinity_tier"], 3)

    def test_summary_names_the_receptor(self):
        self.assertIn("Estrogen Receptor", self.rec["summary"])

    def test_description_covers_hydrolysis_and_depot_kinetics(self):
        text = self.rec["description"]
        self.assertIn("hydrolysis", text)
        self.assertIn("depot", text)
        for author_year in ("Kuiper 1997", "Düsterberg 1985", "Oriowo 1980", "Sierra-Ramírez 2011"):
            self.assertIn(author_year, text, f"{author_year} is cited in-text")

    def test_every_in_text_citation_has_an_identifier(self):
        expected = {
            "10.1210/endo.138.3.4979",  # Kuiper 1997 — ERα/ERβ ligand binding
            "10.1159/000180039",  # Düsterberg 1985 — valerate hydrolysis → 17β-estradiol
            "10.1016/s0010-7824(80)80018-7",  # Oriowo 1980 — three esters, 5 mg IM in oil
            "10.1016/j.contraception.2011.03.014",  # Sierra-Ramírez 2011 — SC vs IM cypionate
        }
        parsed = {_identifier(ref)[0] for ref in self.rec["references"]}
        self.assertEqual(parsed, expected)

    def test_first_reference_is_the_receptor_paper(self):
        # `ingest_curated_mechanisms` attaches references[0] to the summary row,
        # so the receptor-binding paper must lead; the PK papers cite the prose.
        self.assertEqual(_identifier(self.rec["references"][0])[0], "10.1210/endo.138.3.4979")

    def test_name_resolves_in_the_bundled_db(self):
        if not BUNDLED_DB.exists():
            self.skipTest("bundled DB not fetched")
        con = sqlite3.connect(f"file:{BUNDLED_DB}?mode=ro", uri=True)
        try:
            row = con.execute(
                "SELECT id FROM substances WHERE normalized_name = ?",
                (normalise(self.rec["name"]),),
            ).fetchone()
        finally:
            con.close()
        self.assertIsNotNone(row, "the record would be skipped at ingest (no substance match)")


if __name__ == "__main__":
    unittest.main()
