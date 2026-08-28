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
parse_half_life_mean = _mod.parse_half_life_mean
normalize_quantity_text = _mod.normalize_quantity_text
strip_citation_tokens = _mod.strip_citation_tokens
inchikey_relation = _mod.inchikey_relation
classify_ik_conflict = _mod.classify_ik_conflict
cyp_token = _mod.cyp_token
UI_ENZYMES = _mod.UI_ENZYMES
metabolite_key = _mod.metabolite_key


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


class TestCypToken(unittest.TestCase):
    """DrugBank writes enzymes long-form; the metabolism table and the app both
    key on the short gene token, and the join is what decides whether a
    modulator readout appears at all."""

    def test_cyp_names_become_gene_tokens(self):
        self.assertEqual(cyp_token("Cytochrome P450 3A4"), "CYP3A4")
        self.assertEqual(cyp_token("Cytochrome P450 2C19"), "CYP2C19")
        self.assertEqual(cyp_token("Cytochrome P450 1A2"), "CYP1A2")

    def test_case_and_spacing_do_not_matter(self):
        self.assertEqual(cyp_token("cytochrome  p450  2d6"), "CYP2D6")

    def test_non_cyp_enzymes_are_not_tokens(self):
        # A UGT clears plenty of drugs but has no modulator catalog behind it,
        # so calling it a CYP would invent a readout that does not exist.
        self.assertIsNone(cyp_token("UDP-glucuronosyltransferase 1-1"))
        self.assertIsNone(cyp_token("Monoamine oxidase A"))
        self.assertIsNone(cyp_token(""))

    def test_2c19_is_never_read_as_2c9(self):
        # The tokens must not overlap: CYP2C19 contains "CYP2C1", and a
        # substring-based match would silently give 2C9's modulators to a 2C19
        # substrate.
        self.assertEqual(cyp_token("Cytochrome P450 2C9"), "CYP2C9")
        self.assertNotEqual(cyp_token("Cytochrome P450 2C19"), "CYP2C9")

    def test_every_ui_enzyme_round_trips(self):
        # Each key must be producible from DrugBank's own spelling, or the gap
        # check silently never fires for it.
        for token in UI_ENZYMES:
            long_form = f"Cytochrome P450 {token.removeprefix('CYP')}"
            self.assertEqual(cyp_token(long_form), token)


class TestMetaboliteKey(unittest.TestCase):
    """Spelling differences must fold; chemistry must not."""

    def test_stereo_spelling_folds(self):
        # DrugBank writes "Dextroamphetamine"; the catalog writes "d-amphetamine".
        self.assertTrue(metabolite_key("Dextroamphetamine") & metabolite_key("d-amphetamine"))
        self.assertTrue(metabolite_key("Levomethadone") & metabolite_key("l-methadone"))

    def test_positional_prefix_spelling_folds(self):
        self.assertTrue(
            metabolite_key("m-chlorophenylpiperazine (m-CPP)")
            & metabolite_key("meta-chlorophenylpiperazine (mCPP)")
        )

    def test_a_parenthetical_short_form_is_its_own_key(self):
        self.assertIn("mcpp", metabolite_key("meta-chlorophenylpiperazine (mCPP)"))

    def test_n_and_o_desmethyl_never_collapse(self):
        # The whole point of tramadol's CYP2D6 story: O-desmethyltramadol is the
        # active opioid, N-desmethyltramadol is not. Folding these would report
        # one as covered when the catalog names the other.
        self.assertFalse(
            metabolite_key("N-Desmethyltramadol") & metabolite_key("O-Desmethyltramadol")
        )

    def test_distinct_compounds_stay_distinct(self):
        self.assertFalse(metabolite_key("Norketamine") & metabolite_key("Ketamine"))
        self.assertFalse(metabolite_key("Theophylline") & metabolite_key("Theobromine"))

    def test_punctuation_and_case_are_irrelevant(self):
        self.assertTrue(metabolite_key("4-Hydroxy-Ketamine") & metabolite_key("4 hydroxyketamine"))

    def test_empty_and_tiny_names_yield_nothing(self):
        self.assertEqual(metabolite_key(""), set())
        self.assertEqual(metabolite_key("  "), set())


class MeanWithRange(unittest.TestCase):
    """A mean and its own explicit range. The number-counting rule refuses
    these for having three numbers, but three numbers arranged this way say one
    thing — and it is the clearest statement a label makes."""

    def test_mean_then_range(self):
        self.assertEqual(parse_half_life("12 hours (range 8-17 hours)"), (480.0, 1020.0))
        self.assertEqual(parse_half_life("22 hours (range of 7 to 42 hours)"), (420.0, 2520.0))
        self.assertEqual(parse_half_life("7.5 days (range: 4-11 days)"), (5760.0, 15840.0))

    def test_range_then_mean(self):
        self.assertEqual(parse_half_life("9.1 to 14.4 hours (average 10.8 hours)"), (546.0, 864.0))
        self.assertEqual(parse_half_life("2.5 to 3.6 hours (mean 2.9 hours)"), (150.0, 216.0))

    def test_the_range_is_kept_not_the_mean(self):
        # The mean summarises the range; the range is the claim.
        low, high = parse_half_life("24 hours (range of 13.4 - 39.2 hours)")
        self.assertAlmostEqual(low / 60, 13.4)
        self.assertAlmostEqual(high / 60, 39.2)

    def test_a_third_number_that_is_not_a_range_is_still_refused(self):
        self.assertIsNone(parse_half_life("Healthy subjects = 3 hours; others 5 hours"))
        self.assertIsNone(parse_half_life("d-methylphenidate = 3-4 hours; l- 2 hours"))


class StatedMean(unittest.TestCase):
    """The other half of the same statement, for a caller that stores one number.
    Composed with the midpoint a caller would otherwise take, the range-keeping
    rule threw away a number the label states outright."""

    def test_mean_then_range(self):
        self.assertEqual(parse_half_life_mean("12 hours (range 8-17 hours)"), 720.0)
        self.assertEqual(parse_half_life_mean("22 hours (range of 7 to 42 hours)"), 1320.0)
        self.assertEqual(parse_half_life_mean("7.5 days (range: 4-11 days)"), 10800.0)

    def test_range_then_mean(self):
        self.assertEqual(parse_half_life_mean("9.1 to 14.4 hours (average 10.8 hours)"), 648.0)
        self.assertEqual(parse_half_life_mean("2.5 to 3.6 hours (mean 2.9 hours)"), 174.0)

    def test_the_two_rows_this_was_written_for(self):
        # Phenytoin's label says 22 hours; the midpoint of its range is 24.5.
        self.assertEqual(parse_half_life_mean("22 hours (range of 7 to 42 hours)"), 1320.0)
        # Phenelzine's upper bound IS its point estimate, so the midpoint (384
        # min) contradicts the sentence it was computed from.
        self.assertEqual(parse_half_life_mean("1.2 to 11.6 hours (mean 11.6 hours)"), 696.0)

    def test_a_plain_range_states_no_mean(self):
        # The rule is "never discard a stated mean", not "midpoints are bad":
        # summarising a bare 1-4 hours as 2.5 h invents nothing.
        self.assertIsNone(parse_half_life_mean("1 to 4 hours"))
        self.assertIsNone(parse_half_life_mean("9-11 hours"))

    def test_a_single_value_needs_no_mean_of_its_own(self):
        self.assertIsNone(parse_half_life_mean("10 hours"))

    def test_refuses_what_the_range_parser_refuses(self):
        self.assertIsNone(parse_half_life_mean("Healthy subjects = 3 hours; others 5 hours"))
        self.assertIsNone(parse_half_life_mean("6 hours (range 2-9 hours) in elderly subjects"))
        self.assertIsNone(parse_half_life_mean(""))


class QuantityNormalisation(unittest.TestCase):
    """Spellings of the same character. Every one was found in a real statement
    the parser refused."""

    def test_ascii_plus_minus(self):
        self.assertEqual(parse_half_life("3 +/- 1 hours"), (120.0, 240.0))

    def test_en_and_em_dash_ranges(self):
        self.assertEqual(parse_half_life("9\u201311 hours"), (540.0, 660.0))
        self.assertEqual(parse_half_life("9\u201411 hours"), (540.0, 660.0))

    def test_non_breaking_space(self):
        self.assertEqual(parse_half_life("10\u00a0hours"), (600.0, 600.0))


if __name__ == "__main__":
    unittest.main(verbosity=1)
