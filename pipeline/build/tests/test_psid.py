"""Unit tests for the PSID (Piru Substance ID) primitives in pipeline/psid.py.

Pure logic — no built DB needed. Covers the ISO 7064 MOD 37,36 check character
(round-trip + error detection), the name-hash FAMILY format, and compose/parse.
See Specs/stereoisomer-and-release-form-axes.md (Stage 0.1).
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))  # pipeline/
import psid  # noqa: E402

_ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"


def _lcg(seed):
    x = seed
    while True:
        x = (1103515245 * x + 12345) & 0x7FFFFFFF
        yield x


def _payloads(n, length, seed=42):
    g = _lcg(seed)
    return ["".join(_ALPHABET[next(g) % 36] for _ in range(length)) for _ in range(n)]


class CheckCharTests(unittest.TestCase):
    def test_roundtrip_valid(self):
        for body in _payloads(400, 17):
            chk = psid.iso7064_check_char(body)
            # Re-deriving the check char over the same body is stable.
            self.assertEqual(psid.iso7064_check_char(body), chk)

    def test_all_single_char_substitutions_detected(self):
        undetected = 0
        for body in _payloads(300, 17):
            full = body + psid.iso7064_check_char(body)
            for i in range(len(full)):
                for c in _ALPHABET:
                    if c == full[i]:
                        continue
                    bad = full[:i] + c + full[i + 1 :]
                    if psid.iso7064_check_char(bad[:-1]) == bad[-1]:
                        undetected += 1
        self.assertEqual(undetected, 0, "a single-character substitution went undetected")

    def test_adjacent_transposition_detection_is_strong(self):
        # The hybrid MOD 37,36 (like Luhn) detects the vast majority of adjacent
        # transpositions, not literally all — assert the slip rate stays tiny.
        undetected = total = 0
        for body in _payloads(300, 17):
            full = body + psid.iso7064_check_char(body)
            for i in range(len(full) - 1):
                if full[i] == full[i + 1]:
                    continue
                total += 1
                bad = full[:i] + full[i + 1] + full[i] + full[i + 2 :]
                if psid.iso7064_check_char(bad[:-1]) == bad[-1]:
                    undetected += 1
        self.assertLess(undetected / total, 0.01, "transposition detection unexpectedly weak")


class FamilyTests(unittest.TestCase):
    def test_block1_family_recognized(self):
        self.assertTrue(psid.is_block1_family("DUGOZIWVEXMGBE"))
        self.assertTrue(psid.is_wellformed_family("DUGOZIWVEXMGBE"))
        self.assertFalse(psid.is_name_hash_family("DUGOZIWVEXMGBE"))

    def test_name_hash_format(self):
        fam = psid.name_hash_family("cannabis")
        self.assertEqual(len(fam), 14)
        self.assertTrue(fam[0].isdigit(), "name-hash must start with a sentinel digit")
        self.assertTrue(fam[1:].isalpha() and fam[1:].isupper())
        self.assertTrue(psid.is_name_hash_family(fam))
        self.assertTrue(psid.is_wellformed_family(fam))
        self.assertFalse(psid.is_block1_family(fam))

    def test_name_hash_deterministic_and_distinct(self):
        self.assertEqual(psid.name_hash_family("cannabis"), psid.name_hash_family("cannabis"))
        self.assertNotEqual(psid.name_hash_family("cannabis"), psid.name_hash_family("kratom"))

    def test_malformed_rejected(self):
        for bad in ["", "SHORT", "toolongfamilyvalue", "dugoziwvexmgbe", "12345678901234"]:
            self.assertFalse(psid.is_wellformed_family(bad), f"{bad!r} should be malformed")


class ComposeParseTests(unittest.TestCase):
    def test_compose_parse_roundtrip(self):
        p = psid.compose("DUGOZIWVEXMGBE")
        self.assertEqual(p, "P1-DUGOZIWVEXMGBE-0-0-0-" + p[-1])
        self.assertTrue(psid.is_valid(p))
        parsed = psid.parse(p)
        self.assertEqual(parsed["family"], "DUGOZIWVEXMGBE")
        self.assertEqual((parsed["stereo"], parsed["salt"], parsed["release"]), ("0", "0", "0"))

    def test_compose_with_facets(self):
        p = psid.compose("DUGOZIWVEXMGBE", stereo="R", release="XR")
        parsed = psid.parse(p)
        self.assertEqual(parsed["stereo"], "R")
        self.assertEqual(parsed["release"], "XR")
        self.assertTrue(psid.is_valid(p))

    def test_tampered_check_char_rejected(self):
        p = psid.compose("DUGOZIWVEXMGBE")
        bad = p[:-1] + ("X" if p[-1] != "X" else "Y")
        self.assertFalse(psid.is_valid(bad))
        self.assertIsNone(psid.parse(bad))

    def test_malformed_strings_rejected(self):
        for bad in ["", "P1-DUGOZIWVEXMGBE-0-0-0", "X1-DUGOZIWVEXMGBE-0-0-0-0", "garbage"]:
            self.assertIsNone(psid.parse(bad))


if __name__ == "__main__":
    unittest.main()
