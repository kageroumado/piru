"""Tests for the pure logic in pipeline/audit/citation_sourcing.py and the
target expansion in citation_topicality.py. No network is touched.

These pin the two halves that decide whether a citation check is deterministic
or merely plausible: how a number in a paper is turned into a comparable
quantity, and how much a match on that number is allowed to prove.

Run from the repo root:
    python3 pipeline/audit/tests/test_citation_sourcing.py
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from audit.citation_sourcing import (  # noqa: E402
    extract_quantities,
    match_strength,
    parse_prose_citation,
    value_matches,
)
from audit.citation_topicality import PHARMACOLOGICAL_QUALIFIERS, target_keys  # noqa: E402
from audit.europepmc import _record_from  # noqa: E402


def canonical(text, unit_class):
    return [q.value for q in extract_quantities(text) if q.unit_class == unit_class]


class TestUnitCanonicalisation(unittest.TestCase):
    """A row stores nM; a paper may write any scale. Both sides must land on one
    number or the check silently reports absence for every converted value."""

    def test_concentration_scales_fold_to_nanomolar(self):
        self.assertEqual(canonical("Ki 66.4 nM", "concentration"), [66.4])
        self.assertEqual(canonical("IC50 0.0664 µM", "concentration"), [66.4])
        self.assertEqual(canonical("IC50 0.0664 uM", "concentration"), [66.4])
        self.assertEqual(canonical("Kd 66400 pM", "concentration"), [66.4])

    def test_time_scales_fold_to_minutes(self):
        self.assertEqual(canonical("t1/2 3.5 h", "time"), [210.0])
        self.assertEqual(canonical("t1/2 210 min", "time"), [210.0])

    def test_error_term_does_not_capture_the_unit(self):
        # "66.4 ± 3.7 nM" states one measurement, not two; reading 3.7 as the
        # nanomolar value would make the tool match the wrong number.
        self.assertEqual(canonical("Ki was 66.4 ± 3.7 nM", "concentration"), [66.4])

    def test_log_affinity_is_converted(self):
        values = canonical("pKi 7.18 at the receptor", "concentration")
        self.assertEqual(len(values), 1)
        self.assertAlmostEqual(values[0], 66.07, places=1)

    def test_a_bare_number_is_never_a_quantity(self):
        # Every full text contains "14". Admitting unitless numbers would let any
        # row match any paper, which is the failure this whole check exists to
        # avoid.
        self.assertEqual(extract_quantities("we studied 14 subjects over 3"), [])


class TestValueMatching(unittest.TestCase):
    def test_tolerance_follows_stated_precision(self):
        quantities = extract_quantities("values of 66 nM and 66.4 nM and 398 nM")
        # Three significant figures claims precision, so 66 must not satisfy 66.4.
        self.assertEqual(value_matches(66.4, "concentration", quantities).raw, "66.4 nM")
        # Two significant figures does not, so a rounded restatement still counts.
        self.assertIsNotNone(value_matches(400, "concentration", quantities))

    def test_absent_value_returns_none(self):
        quantities = extract_quantities("Ki 66.4 nM")
        self.assertIsNone(value_matches(999, "concentration", quantities))

    def test_unit_class_must_agree(self):
        quantities = extract_quantities("half-life 45 min")
        self.assertIsNone(value_matches(45, "concentration", quantities))


class TestMatchStrength(unittest.TestCase):
    """Presence and absence are not symmetric evidence. An early run of this tool
    "confirmed" nine citations on matches like "50%" and "75%", every one a
    coincidence in an unrelated abstract."""

    def test_round_percentages_prove_nothing(self):
        self.assertEqual(match_strength(50, "percent"), "low")
        self.assertEqual(match_strength(75, "percent"), "low")

    def test_an_odd_precise_percentage_discriminates(self):
        self.assertEqual(match_strength(54.5, "percent"), "high")

    def test_a_precise_affinity_discriminates(self):
        self.assertEqual(match_strength(66.4, "concentration"), "high")

    def test_a_round_order_of_magnitude_does_not(self):
        self.assertEqual(match_strength(100, "concentration"), "low")
        self.assertEqual(match_strength(1, "concentration"), "low")


class TestProseCitation(unittest.TestCase):
    def test_author_year_is_recovered(self):
        prose = parse_prose_citation("Kang et al. 2017 (Neuropharmacology 112:144-149).")
        self.assertEqual((prose.author, prose.year), ("Kang", "2017"))

    def test_ampersand_pair(self):
        prose = parse_prose_citation("Setola & Roth 2003. 5-HT2B agonism is…")
        self.assertEqual((prose.author, prose.year), ("Setola", "2003"))

    def test_table_reference_is_not_an_author(self):
        self.assertIsNone(parse_prose_citation("Table 1 of the 2019 panel"))

    def test_notes_without_a_reference(self):
        self.assertIsNone(parse_prose_citation("Negligible serotonin activity."))


class TestTargetKeys(unittest.TestCase):
    """Subunit stoichiometry appears in the data and in no paper title, so it has
    to be stripped before a target can be looked for at all."""

    def test_subunit_stoichiometry_reduces_to_the_family(self):
        grams, phrases = target_keys("GABA-A α1β2γ2")
        self.assertIn("gabaa", grams)
        self.assertIn("benzodiazepine site", phrases)

    def test_greek_and_latin_spellings_agree(self):
        self.assertEqual(target_keys("σ1"), target_keys("sigma-1"))

    def test_opioid_receptor_type_maps_to_its_abbreviation(self):
        grams, _ = target_keys("μ-opioid")
        self.assertIn("mor", grams)

    def test_enzymes_need_no_table_entry(self):
        grams, _ = target_keys("CYP2D6")
        self.assertIn("cyp2d6", grams)

    def test_filler_words_never_become_a_key(self):
        grams, phrases = target_keys("receptor site")
        self.assertEqual(grams | phrases, set())


class TestMeshDomain(unittest.TestCase):
    """The domain check reads MEDLINE's own indexing, so it works with no
    abstract and no full text. Both halves of the parse are load-bearing: a
    missing qualifier list must not crash, and an unindexed paper must stay
    silent rather than be accused."""

    def test_qualifiers_are_flattened_across_headings(self):
        record = _record_from(
            {
                "meshHeadingList": {
                    "meshHeading": [
                        {
                            "descriptorName": "Ketamine",
                            "meshQualifierList": {
                                "meshQualifier": [
                                    {"qualifierName": "pharmacokinetics"},
                                    {"qualifierName": "pharmacology"},
                                ]
                            },
                        },
                        {"descriptorName": "Animals"},
                    ]
                }
            }
        )
        self.assertEqual(record.mesh_qualifiers, {"pharmacokinetics", "pharmacology"})
        self.assertEqual(record.mesh_descriptors, {"ketamine", "animals"})
        self.assertTrue(record.mesh_qualifiers & PHARMACOLOGICAL_QUALIFIERS)

    def test_a_paper_about_no_substance_has_no_pharmacological_qualifier(self):
        # "ASA Award. Kai Rehder", cited as the source of ketamine's half-life.
        record = _record_from(
            {
                "meshHeadingList": {
                    "meshHeading": [
                        {"descriptorName": "Anesthesiology"},
                        {"descriptorName": "Awards and Prizes"},
                        {"descriptorName": "History, 20th Century"},
                    ]
                }
            }
        )
        self.assertFalse(record.mesh_qualifiers & PHARMACOLOGICAL_QUALIFIERS)

    def test_an_unindexed_paper_yields_no_mesh_at_all(self):
        # Distinct from "indexed under nothing relevant" — the domain check must
        # stay silent here, because the absence is about the journal, not the
        # paper.
        self.assertEqual(_record_from({"title": "A preprint"}).mesh, ())


if __name__ == "__main__":
    unittest.main(verbosity=2)
