"""Tests for pipeline/build/molecule_shapes.py — the offline OpenBabel-backed
2D structure generator that feeds the `molecule_shapes` SQLite table.

Requires the `obabel` CLI on PATH (same dependency the build itself has); the
tests skip themselves gracefully when it's unavailable rather than failing CI
on a machine without OpenBabel installed.

Run from the repo root:
    python3 pipeline/build/tests/test_molecule_shapes.py
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # pipeline/build/
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))  # pipeline/ — shared modules

from chem_ids import obabel_available  # noqa: E402
from molecule_shapes import (  # noqa: E402
    DEFAULT_BOX,
    DEFAULT_MARGIN,
    generate_molecule_shapes,
)

# Cocaine (benzoylmethylecgonine), C17H21NO4 — 22 heavy atoms, a well-known
# structure with a ring system, an ester, ring fusion, and ~2 stereocenters —
# a representative "real" molecule rather than a toy.
COCAINE_SMILES = "CN1C2CCC1C(C(C2)OC(=O)c1ccccc1)C(=O)OC"
ASPIRIN_SMILES = "CC(=O)Oc1ccccc1C(=O)O"
ETHANOL_SMILES = "CCO"

# Afamelanotide, a 13-residue peptide (118 heavy atoms / 123 bonds) — real
# substance from the bundled DB. Regression fixture for the MDL V2000
# fixed-width counts-line bug: obabel emits its counts line as "118123  0  0
# 1 ..." (3-digit atom count immediately touching the 3-digit bond count, no
# separating space), which `.split()` merges into one bogus 118123 token.
# Also exercises bond lines whose atom indices are >= 100, which collide the
# same way ("100101  1  0  0  0  0").
AFAMELANOTIDE_SMILES = (
    "CCCC[C@@H](C(=O)N[C@@H](CCC(=O)O)C(=O)N[C@@H](CC1=CN=CN1)C(=O)N[C@H]"
    "(CC2=CC=CC=C2)C(=O)N[C@@H](CCCNC(=N)N)C(=O)N[C@@H](CC3=CNC4=CC=CC=C43)"
    "C(=O)NCC(=O)N[C@@H](CCCCN)C(=O)N5CCC[C@H]5C(=O)N[C@@H](C(C)C)C(=O)N)"
    "NC(=O)[C@H](CO)NC(=O)[C@H](CC6=CC=C(C=C6)O)NC(=O)[C@H](CO)NC(=O)C"
)


@unittest.skipUnless(obabel_available(), "obabel not on PATH")
class TestGenerateMoleculeShapes(unittest.TestCase):
    def test_cocaine_atom_and_bond_counts_are_plausible(self):
        shapes, failed = generate_molecule_shapes([("cocaine", COCAINE_SMILES)])
        self.assertEqual(failed, [])
        self.assertIn("cocaine", shapes)
        shape = shapes["cocaine"]
        # C17H21NO4 → 17 C + 1 N + 4 O = 22 heavy atoms (H stripped by SDF gen).
        self.assertEqual(len(shape["atoms"]), 22)
        # A tropane ring-fusion + ester heavy-atom skeleton has ~24 bonds.
        self.assertEqual(len(shape["bonds"]), 24)
        elements = {a["el"] for a in shape["atoms"]}
        self.assertIn("N", elements)
        self.assertIn("O", elements)
        # At least one double bond (the two C=O esters).
        self.assertTrue(any(b["order"] == 2 for b in shape["bonds"]))

    def test_atom_coordinates_fit_the_normalized_box(self):
        shapes, _ = generate_molecule_shapes([("cocaine", COCAINE_SMILES)])
        shape = shapes["cocaine"]
        xs = [a["x"] for a in shape["atoms"]]
        ys = [a["y"] for a in shape["atoms"]]
        self.assertGreaterEqual(min(xs), 0)
        self.assertLessEqual(max(xs), DEFAULT_BOX)
        self.assertGreaterEqual(min(ys), 0)
        self.assertLessEqual(max(ys), DEFAULT_BOX)
        # At least one atom should sit at (or very near) the margin on the
        # long axis — otherwise normalization isn't actually filling the box.
        self.assertLessEqual(min(min(xs), min(ys)), DEFAULT_MARGIN + 0.5)

    def test_bond_indices_reference_valid_atoms(self):
        shapes, _ = generate_molecule_shapes([("aspirin", ASPIRIN_SMILES)])
        shape = shapes["aspirin"]
        n = len(shape["atoms"])
        for bond in shape["bonds"]:
            self.assertGreaterEqual(bond["a"], 0)
            self.assertLess(bond["a"], n)
            self.assertGreaterEqual(bond["b"], 0)
            self.assertLess(bond["b"], n)

    def test_invalid_smiles_is_skipped_without_dropping_later_valid_entries(self):
        # Regression test for OpenBabel's line-oriented .smi reader: it aborts
        # the ENTIRE read at the first malformed line, silently dropping every
        # subsequent molecule unless generate_molecule_shapes retries around
        # it. Ethanol sits after the bad line here specifically to catch that.
        pairs = [
            ("cocaine", COCAINE_SMILES),
            ("bad", "THISISNOTVALIDSMILES###"),
            ("aspirin", ASPIRIN_SMILES),
            ("ethanol", ETHANOL_SMILES),
        ]
        shapes, failed = generate_molecule_shapes(pairs)
        self.assertEqual(failed, ["bad"])
        self.assertEqual(set(shapes.keys()), {"cocaine", "aspirin", "ethanol"})

    def test_large_peptide_atom_count_over_99_parses_correctly(self):
        # Regression test for the MDL V2000 fixed-width counts/bond-line bug
        # (see AFAMELANOTIDE_SMILES docstring above) — this molecule crosses
        # the 100-atom boundary where naive whitespace-split parsing corrupts
        # both the counts line and any bond referencing atom index >= 100.
        pairs = [
            ("cocaine", COCAINE_SMILES),
            ("afamelanotide", AFAMELANOTIDE_SMILES),
            ("aspirin", ASPIRIN_SMILES),
        ]
        shapes, failed = generate_molecule_shapes(pairs)
        self.assertEqual(failed, [])
        self.assertEqual(set(shapes.keys()), {"cocaine", "afamelanotide", "aspirin"})
        shape = shapes["afamelanotide"]
        self.assertEqual(len(shape["atoms"]), 118)
        self.assertEqual(len(shape["bonds"]), 123)
        n = len(shape["atoms"])
        for bond in shape["bonds"]:
            self.assertGreaterEqual(bond["a"], 0)
            self.assertLess(bond["a"], n)
            self.assertGreaterEqual(bond["b"], 0)
            self.assertLess(bond["b"], n)
        # A neighboring molecule's shapes must not be corrupted by the large
        # one sharing a batch with it.
        self.assertEqual(len(shapes["cocaine"]["atoms"]), 22)

    def test_empty_and_blank_smiles_fail_cleanly(self):
        shapes, failed = generate_molecule_shapes([("empty", ""), ("blank", "   ")])
        self.assertEqual(shapes, {})
        self.assertEqual(sorted(failed), ["blank", "empty"])

    def test_no_pairs_returns_empty(self):
        self.assertEqual(generate_molecule_shapes([]), ({}, []))


if __name__ == "__main__":
    unittest.main()
