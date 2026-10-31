"""Tests for the pure logic in pipeline/audit/validate_links.py (verdict
classification + cache-staleness). No network is touched.

Run from the repo root:
    python3 pipeline/audit/tests/test_validate_links.py
"""

import importlib.util
import unittest
from datetime import date
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    "vl", Path(__file__).resolve().parent.parent / "validate_links.py"
)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
classify = _mod.classify
needs_recheck = _mod.needs_recheck


class TestClassify(unittest.TestCase):
    def test_ok_range(self):
        self.assertEqual(classify(200, None), "ok")
        self.assertEqual(classify(301, None), "ok")
        self.assertEqual(classify(399, None), "ok")

    def test_dead_hard_4xx(self):
        self.assertEqual(classify(404, None), "dead")
        self.assertEqual(classify(410, None), "dead")
        self.assertEqual(classify(400, None), "dead")

    def test_unknown_blocked_or_server(self):
        self.assertEqual(classify(403, None), "unknown")
        self.assertEqual(classify(429, None), "unknown")
        self.assertEqual(classify(500, None), "unknown")
        self.assertEqual(classify(503, None), "unknown")

    def test_unknown_transport_error(self):
        self.assertEqual(classify(None, "TimeoutError"), "unknown")
        self.assertEqual(classify(None, None), "unknown")


class TestNeedsRecheck(unittest.TestCase):
    TODAY = date(2026, 6, 16)

    def test_missing_entry(self):
        self.assertTrue(needs_recheck(None, self.TODAY, 30))

    def test_fresh_ok_skipped(self):
        entry = {"verdict": "ok", "checked": "2026-06-10"}
        self.assertFalse(needs_recheck(entry, self.TODAY, 30))

    def test_stale_ok_rechecked(self):
        entry = {"verdict": "ok", "checked": "2026-04-01"}
        self.assertTrue(needs_recheck(entry, self.TODAY, 30))

    def test_non_ok_always_rechecked(self):
        self.assertTrue(needs_recheck({"verdict": "dead", "checked": "2026-06-16"}, self.TODAY, 30))
        self.assertTrue(
            needs_recheck({"verdict": "unknown", "checked": "2026-06-16"}, self.TODAY, 30)
        )

    def test_corrupt_checked_date(self):
        self.assertTrue(needs_recheck({"verdict": "ok", "checked": "nonsense"}, self.TODAY, 30))


class TestCheckUrl(unittest.TestCase):
    def _check(self, head: int, get: int) -> dict:
        calls = []

        def fake_open(url, method):
            calls.append(method)
            return (head if method == "HEAD" else get), url, None

        original = _mod._open
        _mod._open = fake_open
        try:
            result = _mod.check_url("https://doi.org/10.1055/x")
        finally:
            _mod._open = original
        result["calls"] = calls
        return result

    def test_a_head_404_that_get_serves_is_ok(self):
        result = self._check(404, 200)
        self.assertEqual(result["verdict"], "ok")
        self.assertEqual(result["calls"], ["HEAD", "GET"])

    def test_a_404_on_both_methods_is_dead(self):
        self.assertEqual(self._check(404, 404)["verdict"], "dead")

    def test_a_head_200_needs_no_get(self):
        self.assertEqual(self._check(200, 500)["calls"], ["HEAD"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
