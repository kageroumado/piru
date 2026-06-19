"""Integrity + regression tests for substance chemical identifiers in the bundled DB.

Guards the 2026-06 identifier cleanup, which corrected ~280 substances whose
upstream InChIKey or SMILES was wrong (LLM-fabricated keys in the enrichment
swarm; wrong-regioisomer SMILES in the NPS vendor dump) and drove the
InChIKey↔SMILES wrong-skeleton count from 158 → 4.

Two complementary checks:
  1. Integrity (needs OpenBabel): no substance's stored InChIKey skeleton may
     disagree with the InChIKey recomputed from its own SMILES, beyond the
     documented allowlist. Catches *new* corruption (e.g. a re-fetched enrichment
     batch). Skipped where obabel is unavailable; CI installs it.
  2. Regression anchors (no tools): a curated set of substances the cleanup fixed
     must keep their verified InChIKeys. Always runs — pins the fixes.

Run from the repo root:
    python3 pipeline/build/tests/test_identifier_integrity.py
"""

import importlib.util
import sqlite3
import unittest
from pathlib import Path

_REPO = Path(__file__).resolve().parents[3]
_DB = _REPO / "Piru/Data/piru-substances.sqlite"

_spec = importlib.util.spec_from_file_location(
    "cii", _REPO / "pipeline/build/check_identifier_integrity.py"
)
_cii = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_cii)

# Substances the cleanup fixed (and a few controls), with their verified-correct
# InChIKey. Mix of both failure modes: wrong-key/right-SMILES (DOB, DET, DPT,
# Carfentanil, Codeine, Morphine) and right-key/wrong-SMILES (2C-B, LSD); plus
# the curated manual fixes (Theobromine, Busulfan, Salvinorin B, MXiPr, Cocaine,
# L-Tryptophan, Tianeptine). A regression in any source or pass that re-breaks
# these fails here.
ANCHORS = {
    "2C-B": "YMHOBZXQZVXHBM-UHFFFAOYSA-N",
    "AMT": "QSQQQURBVYWZKJ-UHFFFAOYSA-N",
    "Bromazepam": "VMIYHDSEFNYJSL-UHFFFAOYSA-N",
    "Busulfan": "COVZYZSDYWQREU-UHFFFAOYSA-N",
    "Carfentanil": "YDSDEBIZUNNPOB-UHFFFAOYSA-N",
    "Cocaine": "ZPUCINDJVBIVPJ-UHFFFAOYSA-N",
    "Codeine": "OROGSEYTTFOCAN-DNJOTXNNSA-N",
    "DET": "LSSUMOWDTKZHHT-UHFFFAOYSA-N",
    "DOB": "FXMWUTGUCAKGQL-UHFFFAOYSA-N",
    "DOC": "ACRITBNCBMTINK-UHFFFAOYSA-N",
    "DOM": "NTJQREUGJKIARY-UHFFFAOYSA-N",
    "DPT": "BOOQTIHIKDDPRW-UHFFFAOYSA-N",
    "Etizolam": "VMZUTJCNQWMAGF-UHFFFAOYSA-N",
    "Lysergic Acid Diethylamide": "VAYOSLLFUXYJDT-RDTXWAMCSA-N",
    "MXiPr": "FTQIVDGNGXPEKP-UHFFFAOYSA-N",
    "Morphine": "BQJCRHHNABKAKU-NOSXKOESSA-N",
    "Oxiracetam": "IHLAQQPQKRMGSS-UHFFFAOYSA-N",
    "Phenmetrazine": "OOBHFESNSZDWIU-UHFFFAOYSA-N",
    "Salvinorin B": "BLTMVAIOAAGYAR-CEFSSPBYSA-N",
    "Theobromine": "YAPQBXQYLJRXSA-UHFFFAOYSA-N",
    "Tianeptine": "APNKSKXHMUCNSY-UHFFFAOYSA-N",
}


class IdentifierIntegrityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.con = sqlite3.connect(f"file:{_DB}?mode=ro", uri=True)

    @classmethod
    def tearDownClass(cls):
        cls.con.close()

    def test_known_identifier_anchors(self):
        """Fixed substances keep their verified InChIKeys (no tools needed)."""
        for name, expected in ANCHORS.items():
            row = self.con.execute(
                "SELECT inchikey FROM substances WHERE canonical_name = ?", (name,)
            ).fetchone()
            self.assertIsNotNone(row, f"{name} missing from bundled DB")
            self.assertEqual(row[0], expected, f"{name} InChIKey regressed")

    def test_no_unexpected_inchikey_smiles_mismatches(self):
        """Every stored InChIKey agrees with its SMILES, modulo the allowlist."""
        if not _cii.obabel_available():
            self.skipTest("OpenBabel (obabel) not installed")
        mismatches = _cii.find_mismatches(_DB)
        self.assertEqual(
            mismatches,
            [],
            "stored InChIKey disagrees with SMILES for: "
            + ", ".join(m[0] for m in mismatches)
            + " — fix via reconcile_identifiers_pubchem.py or add to ALLOWLIST with a reason",
        )

    def test_allowlist_substances_exist(self):
        """Allowlisted names should exist (else the allowlist is stale)."""
        for name in _cii.ALLOWLIST:
            row = self.con.execute(
                "SELECT 1 FROM substances WHERE canonical_name = ?", (name,)
            ).fetchone()
            self.assertIsNotNone(row, f"allowlisted '{name}' not in DB — prune ALLOWLIST")


if __name__ == "__main__":
    unittest.main()
