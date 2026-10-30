"""Tests for pipeline/audit/citation_topicality.py. No network is touched.

Run from the repo root:
    python3 pipeline/audit/tests/test_citation_topicality.py
"""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1]))

from audit import citation_topicality as ct  # noqa: E402

REPO = HERE.parents[2]
DB = REPO / "Piru/Data/piru-substances.sqlite"


class TestAbstractPersister(unittest.TestCase):
    """An enriching run saves the abstract cache after every batch. The saver
    once called itself, so any run without --no-write-cache recursed until it
    crashed at the first save."""

    def test_enabled_writes_the_dict_as_it_is_at_call_time(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "abstracts.json"
            abstracts = {"pmid:1": "first"}
            persist = ct.abstract_persister(path, abstracts, enabled=True)
            abstracts["pmid:2"] = "second"
            persist()
            self.assertEqual(json.loads(path.read_text()), abstracts)

    def test_disabled_never_writes(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "abstracts.json"
            ct.abstract_persister(path, {"pmid:1": "x"}, enabled=False)()
            self.assertFalse(path.exists())

    @unittest.skipUnless(DB.exists(), "needs the built DB")
    def test_a_run_that_writes_the_cache_completes(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache = Path(tmp) / "abstracts.json"
            cache.write_text(json.dumps({}))
            run = subprocess.run(
                [
                    sys.executable,
                    str(REPO / "pipeline/audit/citation_topicality.py"),
                    "--offline",
                    "--limit",
                    "60",
                    "--abstract-cache",
                    str(cache),
                ],
                capture_output=True,
                text=True,
                timeout=300,
            )
            self.assertNotIn("RecursionError", run.stderr)
            self.assertEqual(run.returncode, 0, run.stderr[-2000:])
            # With a local papers cache the run fills, and therefore saves.
            if "Filled" in run.stderr:
                self.assertTrue(json.loads(cache.read_text()))


if __name__ == "__main__":
    unittest.main()
