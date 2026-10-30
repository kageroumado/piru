"""Tests for the gates in pipeline/audit/source_with_haiku.py. No network, no
model and no database: every gate is a pure function of the claim, the passages
and the answer, which is what makes a model's answer checkable at all.

Run from the repo root:
    python3 pipeline/audit/tests/test_source_with_haiku.py
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "build"))

from audit.source_with_haiku import (  # noqa: E402
    HALF_LIFE,
    Claim,
    Doc,
    Passage,
    Term,
    Text,
    compact,
    make_term,
    number_in,
    quote_in,
    verify,
)

PASSAGE = (
    "Ketamine is mainly an NMDA receptor antagonist. It is metabolized in the liver "
    "chiefly by CYP3A4 and CYP2B6 into norketamine."
)


def doc(kind: str = "wikipedia", classes: frozenset[str] = frozenset()) -> Doc:
    return Doc(kind, "wp:Ketamine", "Wikipedia 'Ketamine'", "InChIKey", "https://x", None, classes)


def claim(terms: list[Term], need: int = 1, minutes: float | None = None) -> Claim:
    return Claim("c", "metabolism", None, "Ketamine", "claim", terms, need, number_minutes=minutes)


def answer(*quotes: tuple[int, str], verdict: str = "supported") -> dict:
    return {
        "verdict": verdict,
        "quotes": [{"passage": p, "quote": q} for p, q in quotes],
        "reason": "",
    }


class TestQuoteGate(unittest.TestCase):
    def setUp(self) -> None:
        self.d = doc()
        self.passages = [Passage(self.d, "Pharmacology", PASSAGE)]
        self.cyp = make_term("CYP3A4")

    def test_verbatim_quote_passes_through_punctuation_and_case(self) -> None:
        self.assertTrue(quote_in("metabolized in the liver — chiefly by cyp3a4", PASSAGE))

    def test_a_reworded_quote_fails(self) -> None:
        self.assertFalse(quote_in("metabolized mainly by CYP3A4 in the liver", PASSAGE))
        out = verify(claim([self.cyp]), self.passages, answer((1, "metabolized mainly by CYP3A4")))
        self.assertEqual(out.status, "rejected")
        self.assertIn("gate 1", out.reason)

    def test_a_quote_naming_no_shown_passage_fails(self) -> None:
        out = verify(claim([self.cyp]), self.passages, answer((2, "chiefly by CYP3A4 and CYP2B6")))
        self.assertIn("cites no shown passage", out.reason)

    def test_short_quotes_fail(self) -> None:
        out = verify(claim([self.cyp]), self.passages, answer((1, "by CYP3A4")))
        self.assertIn("fewer than five words", out.reason)

    def test_not_found_is_never_accepted(self) -> None:
        out = verify(claim([self.cyp]), self.passages, answer(verdict="not_found"))
        self.assertEqual(out.status, "not_found")
        out = verify(claim([self.cyp]), self.passages, answer((1, PASSAGE[:60]), verdict="partial"))
        self.assertEqual(out.status, "partial")


class TestKeyTermGate(unittest.TestCase):
    def setUp(self) -> None:
        self.passages = [Passage(doc(), "Pharmacology", PASSAGE)]

    def test_quote_must_name_the_rows_term(self) -> None:
        out = verify(
            claim([make_term("CYP2D6")]),
            self.passages,
            answer((1, "metabolized in the liver chiefly by CYP3A4")),
        )
        self.assertIn("gate 3", out.reason)
        out = verify(
            claim([make_term("CYP3A4")]),
            self.passages,
            answer((1, "metabolized in the liver chiefly by CYP3A4")),
        )
        self.assertEqual(out.status, "accepted")

    def test_half_the_prose_terms_are_needed(self) -> None:
        terms = [make_term("NMDA"), make_term("CYP3A4"), make_term("CYP2B6"), make_term("SERT")]
        out = verify(
            claim(terms, need=2), self.passages, answer((1, "Ketamine is mainly an NMDA receptor"))
        )
        self.assertIn("names 1 of the 2", out.reason)

    def test_a_short_key_only_counts_in_capitals(self) -> None:
        mor = Term("MOR", frozenset({"mor"}))
        self.assertFalse(mor.named_in(Text.of("there is more to it")))
        self.assertTrue(mor.named_in(Text.of("an agonist at MOR and KOR")))


class TestNumberGate(unittest.TestCase):
    def setUp(self) -> None:
        self.half_life = Term("half-life", frozenset(compact(h) for h in HALF_LIFE))

    def check(self, text: str, minutes: float) -> str:
        passages = [Passage(doc(), "Infobox", text)]
        return verify(claim([self.half_life], minutes=minutes), passages, answer((1, text))).status

    def test_the_rows_number_must_be_in_the_quote(self) -> None:
        self.assertEqual(
            self.check("Its elimination half-life is 3.6 hours in adults", 216), "accepted"
        )
        self.assertEqual(
            self.check("Its elimination half-life is 4 hours in adults", 216), "rejected"
        )

    def test_a_value_inside_a_stated_range_counts_and_says_so(self) -> None:
        text = "Elimination half-life: 20–33 hours in healthy adults"
        self.assertEqual(self.check(text, 1200), "accepted")  # the low end
        self.assertEqual(self.check(text, 1590), "accepted")  # 26.5 h, inside
        self.assertEqual(self.check(text, 2100), "rejected")  # 35 h, outside
        self.assertEqual(number_in(1590, text), "within range 20–33 hours")

    def test_ranges_in_words(self) -> None:
        self.assertEqual(number_in(180, "half-life of 2 to 4 h"), "within range 2 to 4 h")
        self.assertIsNone(number_in(300, "half-life of 2 to 4 h"))


class TestClassGate(unittest.TestCase):
    def test_both_classes_named_counting_the_pages_subject(self) -> None:
        opioid = Term("opioid", frozenset({"opioid", "opioids", "morphine"}))
        benzo = Term("benzodiazepine", frozenset({"benzodiazepine", "benzodiazepines"}))
        c = Claim(
            "a", "interaction_rules", None, "opioid + benzodiazepine", "claim", [], 2,
            classes=("opioid", "benzodiazepine"),
            class_terms={"opioid": opioid, "benzodiazepine": benzo},
        )  # fmt: skip
        text = "Taking it with benzodiazepines can cause profound respiratory depression and death."
        on_member = [Passage(doc(classes=frozenset({"opioid"})), "Interactions", text)]
        self.assertEqual(verify(c, on_member, answer((1, text))).status, "accepted")
        unrelated = [Passage(doc(classes=frozenset({"stimulant"})), "Interactions", text)]
        self.assertEqual(verify(c, unrelated, answer((1, text))).status, "rejected")


if __name__ == "__main__":
    unittest.main()
