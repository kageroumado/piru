"""Tests for pipeline/fetch/brushers/medtap_pk.py.

The generator's job is refusing things, so that is what is pinned. Every case
below is a real misattribution the guards caught while it was being written.

    python3 pipeline/build/tests/test_medtap_pk.py
"""

import importlib.util
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
    def test_the_swift_table_parses_to_real_values(self):
        # A regex that matched the wrong block put memantine at 0.1 hours and
        # made every long-half-life drug look like a conflict.
        reference = _mod.independent_half_lives()
        self.assertGreater(len(reference), 400)
        self.assertAlmostEqual(reference["memantine"], 3600.0)
        self.assertAlmostEqual(reference["caffeine"], 300.0, delta=120)


if __name__ == "__main__":
    unittest.main(verbosity=2)
