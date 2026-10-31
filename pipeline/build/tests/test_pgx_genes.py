"""A pharmacogenetics row's sentence is about the gene the row is filed under.

The build writes one row per gene in a record's `relevant_genes`, all carrying that record's
one sentence. When the sentence says nothing about one of those genes, that row renders a
finding about a different gene under this gene's heading — and a citation attached to it
vouches for the wrong pairing. The whole class is checked here so it cannot come back:

1. **The matcher itself** — a gene is named by any spelling prose actually uses, so a
   difference in notation is never reported as a defect.
2. **The ratchet.** The misfiled rows still in the database are listed in
   `pgx-gene-baseline.json`. A row that is not on that list fails, and a listed row that is
   no longer misfiled fails too, asking for the list to be shortened. The list only shrinks.

    python3 pipeline/build/tests/test_pgx_genes.py
    python3 pipeline/build/tests/test_pgx_genes.py --write-baseline   # after rows are fixed
"""

from __future__ import annotations

import json
import sqlite3
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parents[1]))

from pgx_genes import gene_keys, mentions, mismatches, names_gene, same_gene  # noqa: E402

REPO = HERE.parents[2]
DB = REPO / "Piru/Data/piru-substances.sqlite"
BASELINE = HERE / "pgx-gene-baseline.json"


def misfiled(conn: sqlite3.Connection) -> list[str]:
    """`<substance> | <gene>` for every row whose sentence is about another gene."""
    rows = conn.execute(
        "SELECT s.canonical_name, p.gene, p.phenotype_effects FROM pharmacogenetics p "
        "JOIN substances s ON s.id = p.substance_id"
    ).fetchall()
    by_substance: dict[str, list[tuple[str, str]]] = {}
    for name, gene, text in rows:
        by_substance.setdefault(name, []).append((gene, text or ""))
    out: list[str] = []
    for name, pairs in by_substance.items():
        out += [f"{name} | {gene}" for gene in mismatches(pairs)]
    return sorted(out)


class TestGeneMatcher(unittest.TestCase):
    """The notations prose uses for a gene all name it."""

    def test_plain_symbol(self):
        self.assertTrue(names_gene("CYP2D6 poor metabolizers clear it slowly", "CYP2D6"))

    def test_slash_pair_shares_the_prefix(self):
        self.assertTrue(names_gene("CYP3A4/5 polymorphisms modulate clearance", "CYP3A5"))
        self.assertTrue(names_gene("CYP3A4/5 polymorphisms modulate clearance", "CYP3A4"))

    def test_slash_pair_restating_the_subfamily(self):
        self.assertTrue(names_gene("CYP2C19/2B6 polymorphisms alter exposure", "CYP2B6"))
        self.assertTrue(names_gene("CYP2C19/2B6 polymorphisms alter exposure", "CYP2C19"))

    def test_slash_pair_written_out(self):
        self.assertTrue(names_gene("CYP2D6/CYP2C19 PMs show prolonged exposure", "CYP2C19"))

    def test_family_covers_its_members(self):
        self.assertTrue(names_gene("CYP3A inhibition is the bigger lever", "CYP3A4"))
        self.assertFalse(names_gene("CYP3A inhibition is the bigger lever", "CYP2D6"))

    def test_symbol_inside_a_compound_word(self):
        self.assertTrue(names_gene("PMs and CYP3A4-inhibited patients", "CYP3A4"))

    def test_variant_and_allele_decorations(self):
        self.assertTrue(names_gene("MAOA-uVNTR high-activity allele", "MAO-A VNTR"))
        self.assertTrue(names_gene("UGT2B7*2 (-840G>A) alters PK", "UGT2B7 (*2)"))
        self.assertTrue(names_gene("the CYP1A2*1F (rs762551) allele", "CYP1A2"))
        self.assertTrue(names_gene("HLA-B*15:02 carriers", "HLA-B"))
        self.assertTrue(names_gene("OPRM1 118G carriers may need more", "OPRM1 A118G"))

    def test_written_out_name(self):
        self.assertTrue(names_gene("monoamine oxidase A activity", "MAO-A"))

    def test_a_different_gene_is_not_a_match(self):
        self.assertFalse(names_gene("CYP2C19 PMs accumulate nordazepam", "CYP3A4"))
        self.assertFalse(names_gene("ALDH2*2 would cause accumulation", "ADH1B"))

    def test_same_gene_folds_notations(self):
        self.assertTrue(same_gene("OPRM1", "OPRM1 A118G"))
        self.assertTrue(same_gene("ABCB1 (P-gp)", "ABCB1"))
        self.assertFalse(same_gene("ADH1B", "ADH1C"))

    def test_keys_and_mentions_ignore_english(self):
        self.assertEqual(gene_keys(""), set())
        self.assertNotIn("poor", mentions("poor metabolizers have higher exposure"))

    def test_mismatch_needs_a_sibling_to_blame(self):
        # A sentence naming no gene at all is thin, not misfiled.
        self.assertEqual(mismatches([("CYP2D6", "Limited data; expect slower clearance.")]), [])
        self.assertEqual(
            mismatches(
                [
                    ("CYP3A4", "CYP2C19 PMs accumulate more."),
                    ("CYP2C19", "CYP2C19 PMs accumulate more."),
                ]
            ),
            ["CYP3A4"],
        )


class TestShippedDatabase(unittest.TestCase):
    def test_no_new_misfiled_rows(self):
        if not DB.exists():
            self.skipTest("built DB not present")
        conn = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
        try:
            rows = misfiled(conn)
        finally:
            conn.close()
        baseline = json.loads(BASELINE.read_text())["rows"]
        self.assertEqual(
            sorted(set(rows) - set(baseline)),
            [],
            "a pharmacogenetics row's sentence is about another gene — trim the record's "
            "`relevant_genes` to the genes the sentence names, or give that gene its own "
            "sentence and source",
        )
        self.assertEqual(
            sorted(set(baseline) - set(rows)),
            [],
            f"fixed or gone — delete these lines from {BASELINE.name} "
            "(`--write-baseline` rewrites it)",
        )


def write_baseline() -> None:
    conn = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    try:
        rows = misfiled(conn)
    finally:
        conn.close()
    data = json.loads(BASELINE.read_text()) if BASELINE.exists() else {}
    data["rows"] = rows
    BASELINE.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n")
    print(f"{BASELINE}: {len(rows)} misfiled row(s)")


if __name__ == "__main__":
    if "--write-baseline" in sys.argv:
        write_baseline()
    else:
        unittest.main()
