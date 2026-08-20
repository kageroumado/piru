"""Tests for the pure logic in pipeline/audit/compare_to_drugbank.py — the
half-life statement parser, citation-token stripping, and InChIKey identity
relation. No network, no DrugBank data: the parser is what decides whether a
DrugBank statement is comparable at all, so its accept/reject line is pinned
here.

Run from the repo root:
    python3 pipeline/audit/tests/test_compare_to_drugbank.py
"""

import importlib.util
import unittest
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    "cdb", Path(__file__).resolve().parent.parent / "compare_to_drugbank.py"
)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
parse_half_life = _mod.parse_half_life
strip_citation_tokens = _mod.strip_citation_tokens
inchikey_relation = _mod.inchikey_relation
classify_ik_conflict = _mod.classify_ik_conflict


class TestParseAccepts(unittest.TestCase):
    """Clean single values and ranges with explicit units parse to minutes."""

    def test_single_value(self):
        self.assertEqual(parse_half_life("10 hours"), (600.0, 600.0))
        self.assertEqual(parse_half_life("11.2 minutes"), (11.2, 11.2))
        self.assertEqual(parse_half_life("4 h"), (240.0, 240.0))
        self.assertEqual(parse_half_life("5 days"), (7200.0, 7200.0))

    def test_range(self):
        self.assertEqual(parse_half_life("9-11 hours"), (540.0, 660.0))
        self.assertEqual(parse_half_life("1 to 3 hours"), (60.0, 180.0))
        self.assertEqual(parse_half_life("12–14 hours"), (720.0, 840.0))
        # An inverted range is normalized, not rejected.
        self.assertEqual(parse_half_life("11-9 hours"), (540.0, 660.0))

    def test_plus_minus_becomes_a_range(self):
        self.assertEqual(parse_half_life("3.5 ± 0.5 hours"), (180.0, 240.0))

    def test_sentence_wrapper(self):
        self.assertEqual(
            parse_half_life("The average half-life of torasemide is 3.5 hours."),
            (210.0, 210.0),
        )

    def test_citation_tokens_are_transparent(self):
        self.assertEqual(parse_half_life("12 hours[A174292]"), (720.0, 720.0))
        self.assertEqual(
            parse_half_life("The half-life is approximately 6 hours.[A12, L41539]"),
            (360.0, 360.0),
        )

    def test_approximation_words(self):
        self.assertEqual(parse_half_life("approximately 12 hours"), (720.0, 720.0))
        self.assertEqual(parse_half_life("~2.5 hours"), (150.0, 150.0))


class TestParseRejects(unittest.TestCase):
    """Anything the parser cannot pin to one point estimate returns None —
    a skipped comparison is free, a wrong one isn't."""

    def test_unitless(self):
        # MDMA's actual DrugBank value: a number with no unit proves nothing.
        self.assertIsNone(parse_half_life("6-10"))

    def test_extra_numbers_mean_phases_or_populations(self):
        self.assertIsNone(
            parse_half_life(
                "For d-amphetamine the half-life is 9-11 hours while for "
                "l-amphetamine it is 11-14 hours."
            )
        )
        self.assertIsNone(parse_half_life("Alpha phase 2 hours, beta phase 12 hours"))

    def test_bounds_are_not_point_estimates(self):
        self.assertIsNone(parse_half_life("less than 10 hours"))
        self.assertIsNone(parse_half_life("up to 34 hours"))

    def test_population_qualifiers(self):
        self.assertIsNone(parse_half_life("6 hours in patients with renal impairment"))
        self.assertIsNone(parse_half_life("18 hours in elderly subjects"))

    def test_metabolite_values_are_not_the_parent_drug(self):
        self.assertIsNone(parse_half_life("The active metabolite has a half-life of 30 hours"))

    def test_empty_and_prose(self):
        self.assertIsNone(parse_half_life(""))
        self.assertIsNone(parse_half_life("Not available."))
        self.assertIsNone(parse_half_life("Variable; see absorption."))

    def test_long_prose_is_rejected_on_length(self):
        self.assertIsNone(parse_half_life("word " * 40 + "10 hours"))


class TestStripCitationTokens(unittest.TestCase):
    def test_single_and_grouped(self):
        self.assertEqual(strip_citation_tokens("12 h[A174292]"), "12 h")
        self.assertEqual(strip_citation_tokens("x[L41539, A3]y"), "xy")

    def test_bracketed_prose_is_kept(self):
        # Only [A/L/T/F + digits] groups are citations; other brackets are content.
        self.assertEqual(strip_citation_tokens("10 hours [terminal]"), "10 hours [terminal]")


class TestInchikeyRelation(unittest.TestCase):
    K1 = "KWTSXDURSIMDCE-QMMMGPOBSA-N"  # (S)-amphetamine
    K2 = "KWTSXDURSIMDCE-UHFFFAOYSA-N"  # racemic amphetamine — same skeleton
    K3 = "SHXWCVYOXRDMCX-UHFFFAOYSA-N"  # MDMA — different skeleton

    def test_relations(self):
        self.assertEqual(inchikey_relation(self.K1, self.K1), "match")
        self.assertEqual(inchikey_relation(self.K1, self.K2), "skeleton")
        self.assertEqual(inchikey_relation(self.K1, self.K3), "mismatch")


class TestClassifyIkConflict(unittest.TestCase):
    def test_same_name_means_one_side_is_wrong(self):
        self.assertEqual(classify_ik_conflict("Sildenafil", "Sildenafil"), "identifier-error")
        # normalise() strips salt suffixes, so salt spellings still compare equal
        self.assertEqual(classify_ik_conflict("Sildenafil HCl", "sildenafil"), "identifier-error")

    def test_different_names_mean_the_match_was_false(self):
        # "Mitragynine" reached DrugBank's "Magnesium" through a shared short
        # alias — the pair is two different drugs, not a data error on either.
        self.assertEqual(classify_ik_conflict("Mitragynine", "Magnesium"), "alias-collision")


if __name__ == "__main__":
    unittest.main(verbosity=1)
