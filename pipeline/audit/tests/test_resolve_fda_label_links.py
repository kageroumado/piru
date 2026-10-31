"""Tests for the label-identity rule in pipeline/audit/resolve_fda_label_links.py.
No network is touched.

A name matched as a substring passed Pimozide's brand "Orap" for ORAPRED ODT,
a prednisolone label, so pimozide shipped a corticosteroid label as its source.

Run from the repo root:
    python3 pipeline/audit/tests/test_resolve_fda_label_links.py
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from audit.resolve_fda_label_links import choose, starts_with_name, title_names  # noqa: E402

ORAPRED = "ORAPRED ODT (PREDNISOLONE SODIUM PHOSPHATE) TABLET, ORALLY DISINTEGRATING [ADVANZ PHARMA (US) CORP.]"


class TestTitleNames(unittest.TestCase):
    def test_a_prefix_name_does_not_match_a_longer_token(self):
        self.assertEqual(title_names(["Orap", "Pimozide"], ORAPRED), [])
        self.assertFalse(starts_with_name(ORAPRED, "Orap"))

    def test_the_parenthesized_ingredient_comes_first(self):
        title = "ZOLOFT (SERTRALINE HYDROCHLORIDE) TABLET [PFIZER LABORATORIES]"
        self.assertEqual(title_names(["Zoloft", "Sertraline"], title), ["Sertraline", "Zoloft"])

    def test_a_name_inside_another_drug_name_is_not_the_drug(self):
        title = "SPRAVATO (ESKETAMINE HYDROCHLORIDE) SOLUTION [JANSSEN PHARMACEUTICALS, INC.]"
        self.assertEqual(title_names(["Ketamine"], title), [])

    def test_a_generic_title_matches_anywhere_before_the_labeler(self):
        title = "MEMANTINE HYDROCHLORIDE TABLET [CARDINAL HEALTH 107, LLC]"
        self.assertEqual(title_names(["Memantine"], title), ["Memantine"])
        self.assertEqual(title_names(["Cardinal"], title), [])

    def test_a_multi_word_brand_opens_the_title(self):
        title = "SEROQUEL XR (QUETIAPINE FUMARATE) TABLET, EXTENDED RELEASE [ASTRAZENECA]"
        self.assertTrue(starts_with_name(title, "Seroquel XR"))
        self.assertTrue(starts_with_name(title, "Seroquel"))


class TestChoose(unittest.TestCase):
    def test_a_brand_is_matched_as_whole_words(self):
        labels = [
            {"setid": "a", "title": ORAPRED},
            {"setid": "b", "title": "ORAP (PIMOZIDE) TABLET [TEVA]"},
        ]
        label, how = choose(labels, {"ORAP"}, "")
        self.assertEqual(label["setid"], "b")
        self.assertEqual(how, "brand label")


if __name__ == "__main__":
    unittest.main()
