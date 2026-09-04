"""Tests for the product-code primitives in pipeline/product_codes.py: GTIN
arithmetic (NDC → GTIN-14, EAN check digits), name folding both registries
resolve through, and the two package-description parsers. Pure logic — no
built DB needed.

Run from the repo root:
    python3 pipeline/build/tests/test_product_codes.py
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))  # pipeline/
import product_codes as pc  # noqa: E402


class GTINTests(unittest.TestCase):
    def test_check_digit_matches_gs1_examples(self):
        # EAN-13 3400949497294 (a real CIP13): data 340094949729 → check 4.
        self.assertEqual(pc.gtin_check_digit("340094949729"), "4")
        # UPC-A 036000291452: data 03600029145 → check 2.
        self.assertEqual(pc.gtin_check_digit("03600029145"), "2")

    def test_package_ndc_becomes_003_prefixed_gtin14(self):
        gtin = pc.gtin14_from_ndc("71376-203-03")
        self.assertEqual(len(gtin), 14)
        self.assertTrue(gtin.startswith("003"))
        self.assertEqual(gtin[3:13], "7137620303")
        self.assertEqual(gtin[-1], pc.gtin_check_digit(gtin[:-1]))

    def test_every_hyphenation_yields_the_same_gtin(self):
        self.assertEqual(pc.gtin14_from_ndc("5045-8586-01"), pc.gtin14_from_ndc("50458-586-01"))

    def test_non_ten_digit_ndc_is_rejected(self):
        self.assertIsNone(pc.gtin14_from_ndc("50458-586"))
        self.assertIsNone(pc.gtin14_from_ndc(""))

    def test_ean13_pads_to_14_after_check(self):
        self.assertEqual(pc.gtin14_from_ean("3400949497294"), "03400949497294")
        self.assertIsNone(pc.gtin14_from_ean("3400949497295"))  # bad check digit
        self.assertIsNone(pc.gtin14_from_ean("12345"))


class NameKeyTests(unittest.TestCase):
    def test_french_salt_phrase_folds_to_parent(self):
        self.assertIn("methylphenidate", pc.name_keys("CHLORHYDRATE DE MÉTHYLPHÉNIDATE"))
        self.assertIn("methylphenidate", pc.name_keys("MÉTHYLPHÉNIDATE (CHLORHYDRATE DE)"))

    def test_english_salt_suffix_folds_to_parent(self):
        self.assertEqual(
            pc.name_keys("Methylphenidate Hydrochloride"),
            ["methylphenidate hydrochloride", "methylphenidate"],
        )
        self.assertIn("lisdexamfetamine", pc.name_keys("Lisdexamfetamine Dimesylate"))

    def test_plain_name_is_its_own_only_key(self):
        self.assertEqual(pc.name_keys("Ibuprofen"), ["ibuprofen"])
        self.assertEqual(pc.name_keys(""), [])


class USPackageTests(unittest.TestCase):
    def test_single_level(self):
        self.assertEqual(
            pc.parse_us_package("100 CAPSULE in 1 BOTTLE (71376-203-03)"), (100.0, "capsule")
        )
        self.assertEqual(
            pc.parse_us_package("30 TABLET, FILM COATED in 1 BOTTLE (1-2-3)"), (30.0, "tablet")
        )

    def test_nested_levels_multiply(self):
        desc = "10 BLISTER PACK in 1 CARTON (0093-5211-58)  > 10 TABLET in 1 BLISTER PACK"
        self.assertEqual(pc.parse_us_package(desc), (100.0, "tablet"))

    def test_volume(self):
        self.assertEqual(
            pc.parse_us_package("1 BOTTLE in 1 CARTON (x) > 118 mL in 1 BOTTLE"), (118.0, "mL")
        )

    def test_container_only_is_no_count(self):
        self.assertIsNone(pc.parse_us_package("1 BOTTLE in 1 CARTON (x)"))
        self.assertIsNone(pc.parse_us_package(""))


class FRPresentationTests(unittest.TestCase):
    def test_blister_of_tablets(self):
        self.assertEqual(
            pc.parse_fr_presentation("plaquette(s) PVC PVDC aluminium de 30 comprimé(s)"),
            (30.0, "tablet"),
        )

    def test_leading_container_count_multiplies(self):
        self.assertEqual(
            pc.parse_fr_presentation("3 pilulier(s) polypropylène de 30 comprimé(s)"),
            (90.0, "tablet"),
        )

    def test_first_content_wins_over_outer_wrapping(self):
        label = "20 récipient(s) unidose(s) polyéthylène de 2 ml suremballée(s) par plaquette de 5 récipients unidoses"
        self.assertEqual(pc.parse_fr_presentation(label), (40.0, "mL"))

    def test_unparsed(self):
        self.assertIsNone(pc.parse_fr_presentation("boîte de 1 étui"))


if __name__ == "__main__":
    unittest.main()
