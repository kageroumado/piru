"""Tests for pipeline/build/prose.py.

Every input below is a real string from the shipped database, so a passing test
means that string is fixed and a failing one means it came back.

    python3 pipeline/build/tests/test_prose.py
"""

import importlib.util
import unittest
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    "prose", Path(__file__).resolve().parent.parent / "prose.py"
)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
clean = _mod.clean_wiki_prose


class Advice(unittest.TestCase):
    def test_a_sentence_that_is_only_advice_goes(self):
        text = (
            "Very little data exists about the pharmacological properties of 2-FA. "
            "It is highly advised to use harm reduction practices if using this substance."
        )
        self.assertEqual(
            clean(text),
            "Very little data exists about the pharmacological properties of 2-FA.",
        )

    def test_a_sentence_that_opens_with_content_keeps_it(self):
        text = (
            "While it is often characterized by users as being generally more "
            "recreational than LSD, it is highly advised to use harm reduction "
            "practices if using this substance."
        )
        self.assertEqual(
            clean(text),
            "While it is often characterized by users as being generally more "
            "recreational than LSD.",
        )

    def test_the_recommended_phrasings_go_too(self):
        for variant in [
            "It is strongly advised to use harm reduction practices if using this substance.",
            "It is strongly recommended that one use harm reduction practices if choosing to use this substance.",
            "Harm reduction practices are strongly recommended when using this substance.",
        ]:
            self.assertEqual(clean(f"Alpha is a stimulant. {variant}"), "Alpha is a stimulant.")

    def test_the_banned_phrase_is_gone_from_every_case(self):
        for variant in [
            "X is a thing. It is highly advised to use harm reduction practices when using this substance.",
            "Y is a thing. As a result, it is highly advised to use harm reduction practices if using this substance.",
        ]:
            self.assertNotIn("harm reduction", clean(variant).lower())

    def test_the_clause_is_found_after_a_newline_too(self):
        # PW's articles put it on its own line after the paragraph, so a
        # boundary rule that only looked backwards one space missed 17 of them.
        text = (
            "Psychological reactions such as severe anxiety are always possible. \n"
            "It is highly advised to use harm reduction practices if using this substance."
        )
        self.assertEqual(
            clean(text), "Psychological reactions such as severe anxiety are always possible."
        )

    def test_other_advisory_phrasings_go(self):
        for variant in [
            "Thorough independent research and harm reduction practices are strongly advised if choosing to use this substance.",
            "Harm reduction measures are strongly recommended if this substance is used.",
            "Users are advised to approach this substance with precaution and harm reduction practices.",
        ]:
            self.assertEqual(clean(f"Alpha is a stimulant. {variant}"), "Alpha is a stimulant.")

    def test_a_sentence_that_mentions_the_practice_without_instructing_survives(self):
        # Describing where evidence came from is not telling anyone what to do.
        text = "Evidence is mainly from labeling summaries and harm-reduction organizations."
        self.assertEqual(clean(text), text)


class Markup(unittest.TestCase):
    def test_markdown_reference_links_go(self):
        text = "25I-NBOMe acts as a full agonist at 5-HT2A.[[5]](#cite_note-Ettrup2011-5) The role is unclear."
        self.assertEqual(
            clean(text), "25I-NBOMe acts as a full agonist at 5-HT2A. The role is unclear."
        )

    def test_bare_wiki_markers_go(self):
        self.assertEqual(clean("Diazepam is a benzodiazepine.[2]"), "Diazepam is a benzodiazepine.")

    def test_citation_needed_goes_in_either_language(self):
        self.assertEqual(clean("It may inhibit MAO-A.[需要引用]"), "It may inhibit MAO-A.")
        self.assertEqual(clean("It may inhibit MAO-A. [citation needed]"), "It may inhibit MAO-A.")

    def test_a_locant_set_in_a_systematic_name_survives(self):
        # `[1,2,4]triazolo[4,3-a][1,4]benzodiazepine` is a chemical name, not a
        # citation, and stripping it corrupts the compound.
        name = "Clonazolam is a [1,2,4]triazolo[4,3-a][1,4]benzodiazepine."
        self.assertEqual(clean(name), name)

    def test_a_cross_reference_header_line_goes(self):
        text = "更多信息：血清素能致幻剂\n\n25I-NBOMe 在 5-HT2A 受体上具有功效。"
        self.assertEqual(clean(text), "25I-NBOMe 在 5-HT2A 受体上具有功效。")

    def test_main_article_header_goes(self):
        self.assertEqual(clean("Main article: Serotonergic psychedelic\n\nIt binds."), "It binds.")


class Voice(unittest.TestCase):
    """The phrase the repo's voice rule names outright. Every case below is a
    string that was shipping when the rule was written."""

    def test_a_qualifier_goes_and_its_statement_stays(self):
        self.assertEqual(
            _mod.enforce_voice(
                "Very irritating to nasal mucosa. Oral/sublingual generally preferred for harm reduction."
            ),
            "Very irritating to nasal mucosa. Oral/sublingual preferred.",
        )
        self.assertEqual(
            _mod.enforce_voice("Values are tentative. Prefer oral for harm reduction."),
            "Values are tentative. Prefer oral.",
        )

    def test_a_lead_in_goes_and_the_instruction_keeps_its_capital(self):
        self.assertEqual(
            _mod.enforce_voice(
                "Doses are approximate. For harm reduction, take 1-2 small puffs and wait."
            ),
            "Doses are approximate. Take 1-2 small puffs and wait.",
        )

    def test_a_kind_of_organisation_is_named_plainly(self):
        self.assertEqual(
            _mod.enforce_voice("Evidence mainly from labeling summaries and harm-reduction orgs."),
            "Evidence mainly from labeling summaries and community organizations.",
        )

    def test_a_sentence_that_is_only_the_exhortation_goes(self):
        self.assertEqual(
            _mod.enforce_voice(
                "Judgment can be impaired. Immediate harm reduction steps and external support may be necessary."
            ),
            "Judgment can be impaired.",
        )

    def test_nothing_the_table_covers_leaves_the_phrase_behind(self):
        for case in [
            "Oral/sublingual generally preferred for harm reduction.",
            "Prefer oral for harm reduction.",
            "insufflation not advised for harm reduction.",
            "For harm reduction: titrate cautiously and remain seated.",
            "Evidence mainly from harm-reduction orgs.",
            "Immediate harm reduction measures and calm supervision are advisable.",
            "Harm reduction practices are strongly recommended when choosing to use this substance.",
        ]:
            self.assertIsNone(
                _mod.BANNED_PHRASE.search(_mod.enforce_voice(case)),
                f"phrase survived: {case!r}",
            )


class LabelProse(unittest.TestCase):
    """FDA label paragraphs. Piru ships one section of a label, never the whole
    document, so the label's pointers into itself point at nothing."""

    def test_a_bare_section_heading_is_rejected(self):
        # Modafinil shipped the word "indications" as an indication.
        self.assertEqual(_mod.clean_label_prose("indications"), "")
        self.assertEqual(_mod.clean_label_prose("Contraindications:"), "")
        self.assertEqual(_mod.clean_label_prose("Indications & Usage"), "")

    def test_a_real_indication_survives(self):
        text = "Maintenance treatment of chronic obstructive pulmonary disease (COPD)."
        self.assertEqual(_mod.clean_label_prose(text), text)

    def test_a_pointer_into_the_document_goes(self):
        self.assertEqual(
            _mod.clean_label_prose(
                "Levels are known to increase in the presence of carbamazepine, see below. "
                "Thus, if a patient has been titrated to a stable dosage, adjust."
            ),
            "Levels are known to increase in the presence of carbamazepine. "
            "Thus, if a patient has been titrated to a stable dosage, adjust.",
        )

    def test_a_whole_sentence_that_is_only_a_pointer_goes(self):
        self.assertEqual(
            _mod.clean_label_prose(
                "Methadone is subject to the Federal Opioid Treatment Standards. "
                "See below for important regulatory exceptions to certification."
            ),
            "Methadone is subject to the Federal Opioid Treatment Standards.",
        )

    def test_a_parenthetical_cross_reference_goes(self):
        self.assertEqual(
            _mod.clean_label_prose(
                "Reduce the dose in renal impairment (see Dosage and Administration)."
            ),
            "Reduce the dose in renal impairment.",
        )


class Safety(unittest.TestCase):
    def test_ordinary_prose_is_untouched(self):
        text = (
            "2C-B was discovered in 1974 by Alexander Shulgin, who was investigating "
            "psychedelic phenethylamines derived from mescaline."
        )
        self.assertEqual(clean(text), text)

    def test_empty_input(self):
        self.assertEqual(clean(None), "")
        self.assertEqual(clean(""), "")


class CuratorNotes(unittest.TestCase):
    strip_notes = staticmethod(_mod.strip_curator_notes)

    def test_a_note_among_pharmacology_goes_and_the_pharmacology_stays(self):
        text = (
            "Diphenylmethylpiperidine NDRI \u2014 STIMULANT, miscategorized here. "
            "See stimulants-DAT-inhibitors enrichment file. "
            "Pharmacology similar to methylphenidate skeleton (but without ester)."
        )
        self.assertEqual(
            self.strip_notes(text),
            "Pharmacology similar to methylphenidate skeleton (but without ester).",
        )

    def test_british_spelling_is_matched_too(self):
        # The enrichment files are British and `americanize` runs LATER in the
        # build, so a matcher that only knows -ize never sees these strings.
        # "miscategorised" survived a pass written to remove exactly it.
        self.assertEqual(self.strip_notes("Not a GABAergic depressant \u2014 miscategorised."), "")
        self.assertEqual(self.strip_notes("Recategorise as Psychedelic."), "")

    def test_a_row_that_is_only_notes_becomes_empty(self):
        self.assertEqual(
            self.strip_notes(
                "MISCATEGORIZED FOR THIS GROUP. Recommend reassigning for proper enrichment."
            ),
            "",
        )

    def test_real_pharmacology_is_untouched(self):
        text = (
            "Ketamine blocks NMDA receptors, causing a glutamate surge that drives AMPA throughput."
        )
        self.assertEqual(self.strip_notes(text), text)


class LeadingSectionHeading(unittest.TestCase):
    clean = staticmethod(_mod.clean_label_prose)

    def test_the_scraped_heading_is_stripped_from_its_own_body(self):
        # 323 indication rows arrive as "Indications & Usage <the indication>".
        # The heading names the field the row is already stored in.
        self.assertEqual(
            self.clean("Indications & Usage treats frequent heartburn"),
            "treats frequent heartburn",
        )
        self.assertEqual(
            self.clean("Warnings and Precautions Serious infections have occurred"),
            "Serious infections have occurred",
        )

    def test_the_word_as_a_sentence_subject_survives(self):
        # `[A-Z]` cannot tell these apart — IGNORECASE makes it match lowercase
        # too, which stripped "Description" off "Description of the induction
        # phase". A heading is never followed by a preposition binding back to it.
        for text in (
            "Description of the induction phase follows",
            "Overview of the dosing schedule",
        ):
            with self.subTest(text=text):
                self.assertEqual(self.clean(text), text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
