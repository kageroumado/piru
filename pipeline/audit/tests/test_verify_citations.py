"""Tests for the topicality scoring in pipeline/audit/verify_citations.py.
No network is touched.

These pin the property that makes alias-aware scoring safe: a substance's other
names may only ever RAISE a citation's score. Counting each alias as its own
claim term would divide every score by the length of the alias list, quietly
demoting correct citations on well-branded drugs to WEAK.

Run from the repo root:
    python3 pipeline/audit/tests/test_verify_citations.py
"""

import importlib.util
import sys
import unittest
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    "vc", Path(__file__).resolve().parent.parent / "verify_citations.py"
)
_mod = importlib.util.module_from_spec(_spec)
# @dataclass resolves annotations through sys.modules, so the module has to be
# registered before it executes or Claim's definition raises.
sys.modules["vc"] = _mod
_spec.loader.exec_module(_mod)
overlap_score = _mod.overlap_score
tokenize = _mod.tokenize


class TestOverlapScore(unittest.TestCase):
    def test_no_claim_terms_scores_one(self):
        self.assertEqual(overlap_score(set(), {"anything"}), 1.0)

    def test_plain_overlap_is_the_hit_fraction(self):
        self.assertEqual(overlap_score({"ketamine", "banana"}, {"ketamine"}), 0.5)

    def test_zero_overlap_is_zero(self):
        # Score 0 is what the caller turns into OFF_TOPIC.
        self.assertEqual(overlap_score({"ketamine"}, {"cardiology", "stent"}), 0.0)


class TestAliasScoring(unittest.TestCase):
    """A substance's aliases name ONE thing, so they score as one unit."""

    def test_alias_match_rescues_an_otherwise_off_topic_citation(self):
        # The real case: the row is "CoQ10"; its source is titled "coenzyme Q10".
        claim = tokenize("CoQ10")
        paper = tokenize("Pharmacokinetic study of deuterium-labelled coenzyme Q10 in man")
        self.assertEqual(overlap_score(claim, paper), 0.0)
        rescued = overlap_score(claim, paper, alias_terms={"coenzyme", "ubiquinone"})
        self.assertGreater(rescued, 0.0)

    def test_aliases_never_lower_a_score(self):
        claim = {"ketamine", "norketamine"}
        paper = tokenize("Ketamine and norketamine plasma concentrations after oral dosing")
        bare = overlap_score(claim, paper)
        # A dozen unmatched brand names must not dilute a perfect score.
        brands = {f"brand{i}" for i in range(12)}
        self.assertEqual(overlap_score(claim, paper, alias_terms=brands), bare)

    def test_unmatched_aliases_leave_a_partial_score_untouched(self):
        claim = {"ketamine", "banana"}
        paper = {"ketamine"}
        self.assertEqual(overlap_score(claim, paper, alias_terms={"unrelated"}), 0.5)

    def test_matched_alias_counts_once_however_many_match(self):
        claim = {"coq10"}
        paper = {"coenzyme", "ubiquinone", "ubiquinol"}
        one = overlap_score(claim, paper, alias_terms={"coenzyme"})
        many = overlap_score(claim, paper, alias_terms={"coenzyme", "ubiquinone", "ubiquinol"})
        self.assertEqual(one, many)


if __name__ == "__main__":
    unittest.main(verbosity=1)
