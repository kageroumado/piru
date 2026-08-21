"""Tests for the pure logic in pipeline/audit/data_usage.py.

The report is a grep, so what needs pinning is the grep's accept/reject line:
the cases where naming a thing does *not* count as using it. Each test below
is a false positive that was live while the tool was being written, and each
one hid a real blind spot.

No database and no network — every input is a literal.

Run from the repo root:
    python3 pipeline/audit/tests/test_data_usage.py
"""

import importlib.util
import unittest
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    "data_usage", Path(__file__).resolve().parent.parent / "data_usage.py"
)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)


class Camel(unittest.TestCase):
    def test_snake_becomes_camel(self):
        self.assertEqual(_mod.camel("protein_binding_pct"), "proteinBindingPct")
        self.assertEqual(_mod.camel("target"), "target")
        self.assertEqual(_mod.camel("ki_nm"), "kiNm")


class WordBoundary(unittest.TestCase):
    def test_substring_is_not_a_match(self):
        # `dosage_form` in the extractor must not mask the unread Dosage section.
        self.assertFalse(_mod.word_in("dosage", "dosage_form = e.get('dosageForm')"))

    def test_whole_word_matches(self):
        self.assertTrue(_mod.word_in("Half-life", 'fields.get("Half-life")'))


class CodeOnly(unittest.TestCase):
    def test_comment_naming_a_dropped_field_is_not_usage(self):
        source = (
            "# ONLY the Mechanism Of Action field. The rest is absorption,\n"
            "# protein binding, clearance and half-life.\n"
            'pharm = fields.get("Mechanism Of Action", "")\n'
        )
        code = _mod._code_only(source)
        self.assertIn("Mechanism Of Action", code)
        self.assertNotIn("protein binding", code)

    def test_docstring_is_stripped(self):
        source = '"""Reads half-life and clearance."""\nx = 1\n'
        self.assertNotIn("half-life", _mod._code_only(source))


class Classification(unittest.TestCase):
    def test_empty_column_is_never_a_loss(self):
        self.assertEqual(_mod.classify("t", "pka", 0, "", "", ""), "empty")

    def test_column_only_in_sql_is_read_not_shown(self):
        near = "SELECT protein_binding_pct FROM pk_routes"
        self.assertEqual(
            _mod.classify("pk_routes", "protein_binding_pct", 99, near, "", near), "read"
        )

    def test_column_in_a_view_is_shown(self):
        views = "Text(row.proteinBindingPct.formatted())"
        self.assertEqual(
            _mod.classify("pk_routes", "protein_binding_pct", 99, views, views, ""), "shown"
        )

    def test_unmentioned_column_is_unused(self):
        self.assertEqual(_mod.classify("bindings", "kd_nm", 18, "", "", ""), "unused")

    def test_ambiguous_short_name_needs_sql_proximity(self):
        # "target" appears all over SwiftUI; a bare hit proves nothing.
        corpus = "struct Foo { let target: Int }"
        self.assertEqual(_mod.classify("bindings", "target", 10, corpus, corpus, ""), "unused")


class LabelHeaders(unittest.TestCase):
    def test_pharmacology_table_headers_are_enumerated(self):
        section = {
            "content_full": [
                {"text": "<text class='druglabel_header'>Half-life</text>"},
                {"text": "1-4 hours"},
                {"text": "<text class='druglabel_header'>Protein Binding</text>"},
            ],
            "content": {},
        }
        self.assertEqual(_mod._label_headers(section), ["Half-life", "Protein Binding"])


class SurfaceMap(unittest.TestCase):
    def test_every_mapped_surface_is_a_real_detail_section(self):
        """A typo'd surface name would silently mean "nowhere"."""
        import json
        import re

        repo = Path(__file__).resolve().parents[3]
        declared = json.loads((repo / "pipeline/audit/data_surfaces.json").read_text())
        profile = (repo / "Piru/Data/Services/UserProfile.swift").read_text()
        block = profile[profile.index("enum DetailSection") :]
        block = block[: block.index("\n}")]
        cases = set(re.findall(r"case (\w+)", block))
        self.assertTrue(cases, "could not read DetailSection cases")
        # Sections that render without a DisclosurePolicy row: the identity
        # header, the overview prose, and the class screen.
        extra = {"identity", "overview", "drugClass"}
        for table, entry in declared["tables"].items():
            surface = entry.get("surface")
            if surface is None:
                continue
            self.assertIn(surface, cases | extra, f"{table} -> unknown surface {surface!r}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
