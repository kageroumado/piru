"""Regression tests for the FreeOD Wiki dose-cell parser (freeodwiki_extract.py).

Guards the unit-detection bug that silently relabeled microgram doses as grams.
FreeOD Wiki dose tables write micrograms with BOTH the Greek small mu (μ, U+03BC)
and the micro sign (µ, U+00B5) — sometimes within one page — and also use native
Chinese units (微克/毫克/克/毫升). The original detector knew only the micro sign
and latin units, so "25 μg" (clonidine) and "50 微克" (flubromazolam) fell through
to a bare "g" substring match → unit "g" / default "mg" — a 1000× dosing error.

Run from the repo root:
    python3 pipeline/fetch/brushers/test_freeodwiki_extract.py
"""

import importlib.util
import tempfile
import unittest
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    "fow", Path(__file__).resolve().parent / "freeodwiki_extract.py"
)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
parse = _mod.parse_dose_value
parse_page = _mod.parse_page


def _parse_md(text: str) -> dict:
    """Run parse_page over an in-memory markdown fixture."""
    with tempfile.NamedTemporaryFile("w", suffix=".md", encoding="utf-8", delete=False) as fh:
        fh.write(text)
        path = Path(fh.name)
    try:
        return parse_page(path) or {}
    finally:
        path.unlink()


class TestMicrogramMuVariants(unittest.TestCase):
    def test_greek_mu_is_micrograms_not_grams(self):
        # The clonidine bug: "25 μg" with a Greek mu used to parse as unit "g".
        self.assertEqual(parse("25 μg"), ("scalar", 25.0, "µg"))
        self.assertEqual(parse("50 - 75 μg"), ("range", {"min": 50.0, "max": 75.0}, "µg"))

    def test_micro_sign_is_micrograms(self):
        self.assertEqual(parse("50 µg"), ("scalar", 50.0, "µg"))

    def test_greek_mu_without_space(self):
        # Sufentanil writes "0.1μg" / "25μg+" with no separating space.
        self.assertEqual(parse("0.1μg"), ("scalar", 0.1, "µg"))
        self.assertEqual(parse("25μg+"), ("scalar", 25.0, "µg"))

    def test_mixed_within_one_page_range(self):
        # 25N-NBOMe mixes micro-sign and Greek-mu rows; the strong row is Greek.
        self.assertEqual(parse("800 - 1300 μg"), ("range", {"min": 800.0, "max": 1300.0}, "µg"))


class TestChineseUnits(unittest.TestCase):
    def test_chinese_micrograms(self):
        self.assertEqual(parse("50 微克"), ("scalar", 50.0, "µg"))

    def test_chinese_grams(self):
        self.assertEqual(parse("0.25 - 0.5克"), ("range", {"min": 0.25, "max": 0.5}, "g"))

    def test_chinese_milligrams(self):
        self.assertEqual(parse("2 毫克"), ("scalar", 2.0, "mg"))

    def test_chinese_millilitres(self):
        self.assertEqual(parse("0.3 毫升"), ("scalar", 0.3, "ml"))

    def test_chinese_mg_per_kg_keeps_mass_unit(self):
        # "15 - 22 毫克/千克体重" → the mass unit is mg (the /kg is dropped).
        self.assertEqual(
            parse("15 - 22 毫克/千克体重"), ("range", {"min": 15.0, "max": 22.0}, "mg")
        )


class TestGenuineGramsUnchanged(unittest.TestCase):
    def test_grams_stay_grams(self):
        # Alcohol/GHB/kratom/piracetam are genuinely dosed in grams — must NOT
        # become micrograms or milligrams.
        self.assertEqual(parse("10 - 20 g"), ("range", {"min": 10.0, "max": 20.0}, "g"))
        self.assertEqual(parse("0.5 - 1 g"), ("range", {"min": 0.5, "max": 1.0}, "g"))

    def test_milligrams_stay_milligrams(self):
        self.assertEqual(parse("300 mg +"), ("scalar", 300.0, "mg"))


class TestRobustnessGuards(unittest.TestCase):
    def test_bare_letter_in_prose_is_not_a_unit(self):
        # A prose "heavy" cell (e.g. a "…fatal…" warning) must not yield a stray
        # unit from a bare latin "g"/"l"; with no number-attached unit it returns
        # None for the unit so the caller keeps the route's real unit.
        _, _, unit = parse("300 µg + 在严重剂量下可能是致命的")
        self.assertEqual(unit, "µg")  # the real number-attached unit wins
        self.assertIsNone(parse("（待测定）mg"))  # no number → no dose at all

    def test_unit_attached_to_number_wins_over_substring(self):
        # "µg" must win over a bare "g" substring elsewhere in the cell.
        self.assertEqual(parse("< 100 µg"), ("scalar", 100.0, "µg"))

    def test_descending_range_is_rejected_as_garbled(self):
        # A min > max range comes from a malformed/prose cell — drop it.
        self.assertIsNone(parse("25 - 2"))

    def test_no_numbers_returns_none(self):
        self.assertIsNone(parse("（待测定）"))


class TestPerRouteSectionHeaders(unittest.TestCase):
    def test_plain_route_header_rows_split_routes(self):
        # Morphine layout: "| [口服] | |" then "---" then a per-route grid, twice.
        # Without route-header detection the second table overwrites the first
        # under the default "oral".
        md = (
            "| [口服](/x.md) | |\n"
            "| --- | --- |\n"
            "| **[剂量](/x.md)** | |\n"
            "| [阈值](/x.md) | < 10 mg |\n"
            "| [严重](/x.md) | 30 mg + |\n"
            "\n"
            "| [静脉注射](/x.md) | |\n"
            "| --- | --- |\n"
            "| **[剂量](/x.md)** | |\n"
            "| [阈值](/x.md) | < 3.33 mg |\n"
            "| [严重](/x.md) | 10 mg + |\n"
        )
        doses = _parse_md(md)["doses"]
        self.assertEqual(set(doses), {"oral", "intravenous"})
        self.assertEqual(doses["oral"]["threshold"], 10.0)
        self.assertEqual(doses["intravenous"]["threshold"], 3.33)

    def test_arrow_bold_route_headers_split_routes(self):
        # 25I-NBOMe layout: "**⬇ [舌下含服]**" / "**⬇ [鼻吸]**" (U+2B07 arrow,
        # distinct from the ⇣ that the inline header branch handles).
        md = (
            "| **⬇ [舌下含服](/x.md)** | |\n"
            "| [阈值](/x.md) | 50 µg |\n"
            "| [中等](/x.md) | 500 - 700 µg |\n"
            "| **⬇ [鼻吸](/x.md#鼻吸)** | |\n"
            "| [阈值](/x.md) | 40 µg |\n"
            "| [中等](/x.md) | 400 - 600 µg |\n"
        )
        doses = _parse_md(md)["doses"]
        self.assertEqual(set(doses), {"sublingual", "insufflation"})
        self.assertEqual(doses["sublingual"]["threshold"], 50.0)
        self.assertEqual(doses["insufflation"]["threshold"], 40.0)

    def test_bold_section_headers_are_not_mistaken_for_routes(self):
        # "**[剂量]**" / "**持续时间**" are empty-value bold headers that must NOT
        # match a route (they share the short-cell shape with a route header).
        md = (
            "| **[剂量](/x.md)** | |\n"
            "| [阈值](/x.md) | 100 mg |\n"
            "| **持续时间** | |\n"
            "| [总时长](/x.md) | 4 - 6 小时 |\n"
        )
        doses = _parse_md(md)["doses"]
        self.assertEqual(set(doses), {"oral"})  # stays on the default route


if __name__ == "__main__":
    unittest.main(verbosity=2)
