"""Tests for pipeline/audit/claim_language.py and the file it gates.

Two things are pinned here. The vocabulary split: a medical claim is refused in
any row from any source, while the narrower register is asked only of the lines
Piru writes itself, so that reporting a compound's dose-dependent pharmacology
stays sayable. And the shape of data/curated/mechanism-lines.json: every authored
line is one short sentence that passes the strict check, every override passes the
medical-claim check, and every key names a record that exists.

Run from the repo root:
    python3 pipeline/audit/tests/test_claim_language.py
"""

import json
import sqlite3
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from audit.claim_language import (  # noqa: E402
    AUTHORED_OBJECTS,
    DB_PATH,
    LINES_PATH,
    MAX_LINE_WORDS,
    OVERRIDE_OBJECT,
    banned_hits,
    check_line,
)

DOC = json.loads(LINES_PATH.read_text())
MEDTAP_EXTRACT = Path("/tmp/piru-extract/medtap.substances.json")


class TestVocabularySplit(unittest.TestCase):
    """The medical-claim set answers for every row; the strict set only for ours."""

    def test_a_medical_claim_is_refused_in_any_row(self):
        for text in (
            "It is effective in schizophrenia.",
            "The therapeutic action is analgesia.",
            "Increased in patients with ulcerative colitis.",
            "Dosage is titrated to provide analgesia.",
        ):
            self.assertTrue(banned_hits(text), text)

    def test_dose_dependent_pharmacology_is_sayable_in_a_sourced_row(self):
        for text in (
            "At higher doses it depletes serotonin in the brain.",
            "A 10 mg/kg ingestion leaves 16% unmetabolized after 48 hours.",
            "It is considered to have low abuse potential.",
            "For a signal to pass, the receptor must remain open.",
        ):
            self.assertEqual(banned_hits(text), [], text)

    def test_the_same_wording_is_refused_in_a_line_piru_writes(self):
        for text in (
            "At higher doses it depletes serotonin in the brain.",
            "A 10 mg/kg ingestion leaves 16% unmetabolized after 48 hours.",
            "It is considered to have low abuse potential.",
        ):
            self.assertTrue(banned_hits(text, authored=True), text)

    def test_directed_guidance_is_refused_everywhere(self):
        self.assertIn(
            "advice",
            banned_hits("It should be taken into consideration when combining substances."),
        )
        self.assertIn("advice", banned_hits("Consult a physician."))

    def test_a_dosing_instruction_is_refused_everywhere(self):
        self.assertIn("dosing instruction", banned_hits("At the recommended doses."))
        self.assertIn("dosing instruction", banned_hits("The usual dose is one tablet."))


class TestLineShape(unittest.TestCase):
    def test_a_good_line_passes(self):
        self.assertEqual(check_line("Selective serotonin reuptake inhibitor at SERT."), [])

    def test_a_line_must_be_one_sentence_ending_in_a_period(self):
        self.assertIn(
            "not one sentence ending in a period", check_line("Blocks histamine H1 receptors")
        )
        self.assertIn("more than one sentence", check_line("Blocks H1 receptors. Also blocks M1."))

    def test_a_line_is_capped_in_length(self):
        long_line = " ".join(["word"] * (MAX_LINE_WORDS + 1)) + "."
        self.assertIn(f"more than {MAX_LINE_WORDS} words", check_line(long_line))


class TestCuratedFile(unittest.TestCase):
    """Both authored objects and the override object parse and pass their check."""

    def test_every_object_is_present_and_populated(self):
        for obj in (*AUTHORED_OBJECTS, OVERRIDE_OBJECT):
            self.assertIsInstance(DOC.get(obj), dict, obj)
            self.assertTrue(DOC[obj], obj)

    def test_every_authored_line_passes_the_strict_check(self):
        for obj in AUTHORED_OBJECTS:
            for key, line in DOC[obj].items():
                self.assertEqual(check_line(line), [], f"{obj}/{key}")

    def test_every_override_passes_the_medical_claim_check(self):
        for key, prose in DOC[OVERRIDE_OBJECT].items():
            self.assertEqual(banned_hits(prose), [], key)

    def test_no_key_is_claimed_by_two_objects(self):
        a, b = (set(DOC[o]) for o in AUTHORED_OBJECTS)
        self.assertEqual(a & b, set())


class TestKeysResolve(unittest.TestCase):
    """A key that names nothing ships no line, and does so silently."""

    @unittest.skipUnless(MEDTAP_EXTRACT.exists(), "MedTAP extract not present")
    def test_every_medtap_key_names_a_record_with_a_mechanism(self):
        records = json.loads(MEDTAP_EXTRACT.read_text())
        with_mechanism = {
            r["name"]
            for r in records
            if ((r.get("mechanismOfAction") or {}).get("summary") or "").strip()
        }
        missing = set(DOC["medtap_lines"]) - with_mechanism
        self.assertEqual(missing, set())

    @unittest.skipUnless(DB_PATH.exists(), "bundled database not present")
    def test_every_override_key_names_a_substance_that_has_a_row_to_override(self):
        con = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
        names = {
            n
            for (n,) in con.execute(
                "SELECT sub.canonical_name FROM mechanisms_summary m "
                "JOIN sources s ON s.id = m.source_id "
                "JOIN substances sub ON sub.id = m.substance_id "
                "WHERE m.language = 'en' AND s.slug = 'freeodwiki'"
            )
        }
        con.close()
        self.assertEqual(set(DOC[OVERRIDE_OBJECT]) - names, set())


if __name__ == "__main__":
    unittest.main(verbosity=2)
