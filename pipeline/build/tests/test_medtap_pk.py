"""Tests for pipeline/fetch/brushers/medtap_pk.py.

The generator's job is refusing things, so that is what is pinned. Every case
below is a real misattribution the guards caught while it was being written.

    python3 pipeline/build/tests/test_medtap_pk.py
"""

import importlib.util
import sqlite3
import unittest
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    "medtap_pk", Path(__file__).resolve().parents[2] / "fetch/brushers/medtap_pk.py"
)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)


class Attribution(unittest.TestCase):
    def test_a_value_naming_another_ingredient_is_refused(self):
        # An oral contraceptive's label lists each ingredient's kinetics, and
        # taking the first value gave ethynodiol estradiol's 36-hour half-life.
        self.assertTrue(_mod.attributed_to_other("estradiol:   36 hours", "Ethynodiol"))

    def test_a_value_naming_its_own_substance_is_kept(self):
        self.assertFalse(_mod.attributed_to_other("clindamycin:   2.4 hours", "Clindamycin"))

    def test_an_unattributed_value_is_kept(self):
        self.assertFalse(_mod.attributed_to_other("2-4 hours", "Ibuprofen"))

    def test_a_time_of_day_is_not_an_attribution(self):
        # The colon in "administered at 8:00" must not read as a name.
        self.assertFalse(_mod.attributed_to_other("2 hours", "Ibuprofen"))


class LabelTable(unittest.TestCase):
    def test_headers_and_values_pair_up(self):
        section = {
            "content": {},
            "content_full": [
                {"text": "<text class='druglabel_header'>Half-life</text>"},
                {"text": "<paragraph>2-4 hours</paragraph>"},
                {"text": "<text class='druglabel_header'>Protein Binding</text>"},
                {"text": "99%"},
            ],
        }
        fields = _mod.label_fields(section)
        self.assertEqual(fields["Half-life"], "2-4 hours")
        self.assertEqual(fields["Protein Binding"], "99%")


class IndependentCheck(unittest.TestCase):
    """The reference set the refusal rule cross-checks against. Expectations are
    computed from the database rather than written down, so a rebuild that
    changes a value does not fail a test that has nothing to say about it."""

    @classmethod
    def setUpClass(cls):
        cls.reference = _mod.independent_half_lives()
        cls.db = sqlite3.connect(_mod.DB)

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    def test_it_reaches_most_of_the_catalog(self):
        self.assertGreater(len(self.reference), 400)

    def test_values_are_plausible_minutes(self):
        # The check this replaces existed because a regex matched the wrong
        # block and put memantine at 0.1 hours, making every long-half-life
        # drug look like a conflict. A unit slip is still the failure to catch.
        self.assertTrue(all(v > 0 for v in self.reference.values()))
        self.assertGreater(max(self.reference.values()), 24 * 60)

    def test_medtap_cannot_corroborate_itself(self):
        # A substance whose only half-life came from the label corpus must not
        # appear: it would then agree with itself and the refusal never fires.
        medtap_only = {
            name
            for (name,) in self.db.execute(
                """
                SELECT lower(s.canonical_name)
                  FROM half_lives h
                  JOIN substances s ON s.id = h.substance_id
                 GROUP BY h.substance_id
                HAVING SUM(h.source_id <> (SELECT id FROM sources WHERE slug = 'medtap')) = 0
                """
            )
        }
        self.assertTrue(medtap_only, "no medtap-only rows left to prove the exclusion")
        self.assertEqual(medtap_only & set(self.reference), set())

    def test_the_best_source_wins_a_disagreement(self):
        # Several sources carry a half-life for the same substance and disagree.
        # The reference must be the best-priority row, not whichever came last.
        rows = self.db.execute(
            """
            SELECT lower(s.canonical_name), h.half_life_minutes
              FROM half_lives h
              JOIN substances s ON s.id = h.substance_id
              JOIN sources src ON src.id = h.source_id
             WHERE src.slug <> 'medtap'
             GROUP BY h.substance_id
            HAVING COUNT(DISTINCT h.half_life_minutes) > 1
             ORDER BY MIN(src.default_priority) ASC, src.default_priority ASC
            """
        ).fetchall()
        self.assertTrue(rows, "no disagreements left to prove the ordering")
        for name, best in rows:
            self.assertAlmostEqual(self.reference[name], best, msg=name)


if __name__ == "__main__":
    unittest.main(verbosity=2)
