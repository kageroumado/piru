#!/usr/bin/env python3
"""What the dose.wiki snapshot must never contain, and what the ingest must read.

Run: python3 pipeline/build/tests/test_dosewiki.py
"""

from __future__ import annotations

import importlib.util
import json
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
SNAPSHOT = REPO / "data/sources/dosewiki.json"


def _load_fetcher():
    spec = importlib.util.spec_from_file_location(
        "dosewiki_fetch", REPO / "pipeline/fetch/dosewiki.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


fetcher = _load_fetcher()


def _walk(node):
    """Every (key, value) pair anywhere in a JSON tree."""
    if isinstance(node, dict):
        for key, value in node.items():
            yield key, value
            yield from _walk(value)
    elif isinstance(node, list):
        for item in node:
            yield from _walk(item)


class TestSnapshot(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not SNAPSHOT.exists():
            raise unittest.SkipTest(f"{SNAPSHOT} not fetched; run pipeline/fetch/dosewiki.py")
        cls.payload = json.loads(SNAPSHOT.read_text())
        cls.records = cls.payload["records"]

    def test_no_stripped_key_survives_anywhere_in_the_file(self):
        """The license-blocked and content-dropped fields, at any depth.

        Checked over the whole tree rather than the record's top level: an
        allowlist that grew a nested key back would still pass a top-level
        check, and the licensing half of this list is not a matter of taste.
        """
        blocked = set(fetcher.LICENSE_BLOCKED)
        blocked |= {key.rsplit(".", 1)[-1] for key in fetcher.DROPPED}
        seen = {key for key, _ in _walk(self.payload)} & blocked
        self.assertEqual(set(), seen)

    def test_every_record_carries_its_slug_and_revision(self):
        for record in self.records:
            self.assertTrue(record.get("slug"))
            self.assertTrue(record.get("publicRevision"))

    def test_records_are_sorted_by_slug(self):
        slugs = [record["slug"] for record in self.records]
        self.assertEqual(sorted(slugs), slugs)
        self.assertEqual(len(set(slugs)), len(slugs))

    def test_the_snapshot_names_its_license_and_fetch_time(self):
        self.assertIn("CC0", self.payload["license"])
        self.assertTrue(self.payload["fetched_at"])

    def test_drafts_are_absent(self):
        self.assertEqual([], [r["slug"] for r in self.records if r.get("priority") == "low"])

    def test_every_reference_names_a_work_a_reader_can_reach(self):
        for record in self.records:
            for reference in record.get("references") or []:
                self.assertTrue(
                    reference.get("doi") or reference.get("pmid"),
                    f"{record['slug']}: reference with no DOI and no PMID",
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
