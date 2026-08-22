"""Tests for the quantity parsers and the character normalizer they share.

The failure these guard against is not a refusal. A separator the pattern does
not know makes the match stop at the leading number, so `10—20 mg` parses as
`10` with **no unit** — a wrong value that looks like a parsed one. Each
character below is one a source has actually used.

    python3 pipeline/build/tests/test_quantity_parsers.py
"""

import sys
import unittest
from pathlib import Path

BRUSHERS = Path(__file__).resolve().parents[3] / "pipeline/fetch/brushers"
sys.path.insert(0, str(BRUSHERS))

from _common import normalize_quantity_text, parse_range  # noqa: E402
from extract import parse_dose_cell  # noqa: E402

#: Every spelling of "ten to twenty milligrams" a source has produced.
SEPARATORS = [
    "10-20 mg",  # hyphen-minus
    "10–20 mg",  # en dash
    "10—20 mg",  # em dash
    "10−20 mg",  # minus sign
    "10‐20 mg",  # hyphen
    "10‑20 mg",  # non-breaking hyphen
    "10‒20 mg",  # figure dash
    "10－20 mg",  # fullwidth hyphen-minus
    "10 - 20 mg",
    "10 to 20 mg",
]


class DoseCell(unittest.TestCase):
    def test_every_separator_yields_the_same_range_and_unit(self):
        for text in SEPARATORS:
            with self.subTest(text=text):
                self.assertEqual(parse_dose_cell(text), (10.0, 20.0, "mg"))

    def test_both_micro_signs_fold_onto_one_unit(self):
        # U+00B5 MICRO SIGN and U+03BC GREEK SMALL LETTER MU are visually
        # identical; storing both means one substance's µg rows never group
        # with another's.
        for text in ("100 µg", "100 μg", "100 mcg", "100 ug"):
            with self.subTest(text=text):
                self.assertEqual(parse_dose_cell(text), (100.0, None, "µg"))


class Range(unittest.TestCase):
    def test_every_separator_yields_the_same_range_and_unit(self):
        for text in SEPARATORS:
            with self.subTest(text=text):
                self.assertEqual(parse_range(text), ("10", "20", "mg"))

    def test_durations_parse_through_the_same_separators(self):
        for text in ("4-8 hours", "4–8 hours", "4—8 hours", "4 to 8 hours"):
            with self.subTest(text=text):
                self.assertEqual(parse_range(text), ("4", "8", "hours"))


class Normalizer(unittest.TestCase):
    def test_plus_or_minus_is_written_three_ways(self):
        for text in ("5 +/- 2", "5 +- 2", "5 ± 2"):
            with self.subTest(text=text):
                self.assertEqual(normalize_quantity_text(text), "5 ± 2")

    def test_exotic_spaces_become_ordinary_ones(self):
        self.assertEqual(normalize_quantity_text("10 mg to 20 mg"), "10 mg to 20 mg")

    def test_none_and_empty_are_the_empty_string(self):
        self.assertEqual(normalize_quantity_text(None), "")
        self.assertEqual(normalize_quantity_text(""), "")


if __name__ == "__main__":
    unittest.main(verbosity=2)
