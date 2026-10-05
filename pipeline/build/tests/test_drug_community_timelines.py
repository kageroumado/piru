"""Exercise the real source importer, SQLite storage and audit against published inputs."""

import copy
import hashlib
import importlib.util
import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "pipeline/build"))
from drug_community_timelines import reference_timelines, snapshot_binding

spec = importlib.util.spec_from_file_location("piru_build", REPO / "pipeline/build/sqlite.py")
build_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_module)
audit_spec = importlib.util.spec_from_file_location(
    "upstream_report", REPO / "pipeline/audit/upstream_report.py"
)
audit = importlib.util.module_from_spec(audit_spec)
audit_spec.loader.exec_module(audit)


class TimelineImportTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "drug-community.json"
        self.db = sqlite3.connect(":memory:")
        self.addCleanup(self.db.close)
        self.db.row_factory = sqlite3.Row
        self.db.executescript(build_module.SCHEMA_SQL)
        self.build = build_module.Build(self.db)
        self.build.seed_sources()
        self.build.seed_effect_vocab()

    def ingest(self, records):
        self.path.write_text(json.dumps(records))
        self.build.ingest_drug_community(self.path)
        return self.db.execute(
            "SELECT * FROM drug_community_timelines ORDER BY source_name, entry_index"
        ).fetchall()

    def test_published_snapshot_preserves_every_entry_and_unknown(self):
        path = REPO / "data/sources/drug-community.json"
        records = json.loads(path.read_text())
        rows = self.ingest(records)
        build_module.enforce_us_english(self.db)
        build_module.enforce_voice_rule(self.db)
        rows = self.db.execute("SELECT * FROM drug_community_timelines").fetchall()
        expected = {
            (r["drug_name"], i, kind): entry
            for r in records
            for i, entry in enumerate(r.get("duration_curves") or [])
            for kind in ("duration_curve", "partial_duration_curve")
            if isinstance(entry.get(kind), dict)
        }
        expected.update(
            {
                (r["drug_name"], i, "duration_study"): entry
                for r in records
                for i, entry in enumerate(r.get("duration_studies") or [])
            }
        )
        actual = {
            (r["source_name"], r["entry_index"], r["kind"]): json.loads(r["entry_json"])
            for r in rows
        }
        self.assertEqual(expected, actual)
        self.assertEqual(len(rows), len({r["record_key"] for r in rows}))
        for row in rows:
            record = next(r for r in records if r["drug_name"] == row["source_name"])
            self.assertEqual(json.loads(row["duration_text_json"]), record.get("duration") or {})
            self.assertEqual(json.loads(row["citations_json"]), record.get("citations") or [])
        self.assertEqual(self.db.execute("SELECT count(*) FROM durations").fetchone()[0], 0)
        self.assertEqual(self.db.execute("PRAGMA foreign_key_check").fetchall(), [])

    def test_partial_count_is_visible_to_audit(self):
        records = json.loads((REPO / "data/sources/drug-community.json").read_text())
        findings = audit.dc_internal(records)
        curves = [e for r in records for e in r.get("duration_curves") or []]
        partial = sum(isinstance(e.get("partial_duration_curve"), dict) for e in curves)
        self.assertGreater(partial, 0)
        self.assertEqual(findings["_partial_curves"], [str(partial)])
        self.assertEqual(findings["_curves"], [str(len(curves))])

    def test_duplicate_routes_and_formulations_remain_separate(self):
        entries = [
            {
                "method": "ophthalmic",
                "formulation": "fictional solution",
                "partial_duration_curve": {"units": "days", "onset": {"start": None, "end": 0.2}},
            },
            {
                "method": "ophthalmic",
                "formulation": "fictional ointment",
                "partial_duration_curve": {"units": "days", "onset": {"start": None, "end": 0.2}},
            },
        ]
        rows = self.ingest(
            [{"drug_name": "Fictional compound", "duration_curves": entries + [entries[0]]}]
        )
        self.assertEqual(len(rows), 3)
        self.assertEqual([json.loads(r["entry_json"]) for r in rows], entries + [entries[0]])
        self.assertEqual(len({r["record_key"] for r in rows}), 3)
        self.assertEqual({r["route"] for r in rows}, {"ophthalmic"})

    def test_four_semantic_cases_are_never_projected_as_phase_lengths(self):
        base = {
            "units": "hours",
            "onset": {"start": 0.2, "end": 0.5},
            "peak": {"start": 1, "end": 3},
            "offset": {"start": 2, "end": 3},
            "after_effects": {"start": 6, "end": 9},
        }
        later_tail = copy.deepcopy(base)
        later_tail["after_effects"]["start"] = 8
        unknown = copy.deepcopy(base)
        unknown["onset"]["start"] = None
        unknown_unit = {**base, "units": "unrecognized"}
        entries = [
            {"method": "fictional route", "duration_curve": c}
            for c in (base, later_tail, unknown, unknown_unit)
        ]
        rows = self.ingest([{"drug_name": "Fictional compound", "duration_curves": entries}])
        self.assertEqual([json.loads(r["entry_json"]) for r in rows], entries)
        self.assertEqual(self.db.execute("SELECT count(*) FROM durations").fetchone()[0], 0)

    def test_withdrawal_removes_old_timeline_and_derived_rows(self):
        record = {
            "drug_name": "Fictional compound",
            "duration_curves": [
                {
                    "method": "oral",
                    "duration_curve": {"units": "hours", "peak": {"start": 1, "end": 2}},
                }
            ],
        }
        first = self.ingest([record])
        sid = first[0]["substance_id"]
        self.build.add_duration_profile(
            sid, "drug.community", "oral", {"peak": {"min": 60, "max": 60}}
        )
        self.assertEqual(len(self.ingest([{"drug_name": "Fictional compound"}])), 0)
        self.assertEqual(self.db.execute("SELECT count(*) FROM durations").fetchone()[0], 0)
        successor = self.ingest([record])
        self.assertEqual(len(successor), 1)
        self.assertEqual(json.loads(successor[0]["entry_json"]), record["duration_curves"][0])

    def test_dedup_preserves_separate_source_records(self):
        rows = self.ingest(
            [
                {
                    "drug_name": name,
                    "duration_curves": [
                        {
                            "method": "oral",
                            "duration_curve": {"units": "hours", "peak": {"start": 1, "end": 2}},
                        }
                    ],
                }
                for name in ("Fictional one", "Fictional two")
            ]
        )
        self.build._merge_into(rows[0]["substance_id"], rows[1]["substance_id"])
        merged = self.db.execute("SELECT * FROM drug_community_timelines").fetchall()
        self.assertEqual(len(merged), 2)
        self.assertEqual({r["substance_id"] for r in merged}, {rows[0]["substance_id"]})
        self.assertEqual({r["source_name"] for r in merged}, {"Fictional one", "Fictional two"})

    def test_release_binding_rejects_snapshot_drift(self):
        self.path.write_text("[]")
        sha = hashlib.sha256(self.path.read_bytes()).hexdigest()
        meta = self.path.with_suffix(".meta.json")
        meta.write_text(json.dumps({"snapshot_sha256": sha, "release_id": "fictional-release"}))
        self.assertEqual(snapshot_binding(self.path), (sha, "fictional-release"))
        self.path.write_text("[{}]")
        with self.assertRaisesRegex(ValueError, "does not match"):
            snapshot_binding(self.path)

    def test_old_metadata_does_not_claim_verified_release(self):
        self.path.write_text("[]")
        self.path.with_suffix(".meta.json").write_text('{"release_id":"unbound"}')
        self.assertIsNone(snapshot_binding(self.path)[1])

    def test_unknown_shape_fails_visibly(self):
        with self.assertRaisesRegex(ValueError, "unrecognized"):
            list(
                reference_timelines(
                    {"drug_name": "Fictional", "duration_curves": [{"method": "oral"}]}, "snapshot"
                )
            )


class ReleaseFetchTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location(
            "fetch_drug_community", REPO / "pipeline/fetch/brushers/fetch_drug_community.py"
        )
        self.fetcher = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.fetcher)
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        for name, filename in (
            ("OUT", "drug-community.json"),
            ("META", "drug-community.meta.json"),
        ):
            setattr(self.fetcher, name, Path(self.directory.name) / filename)
        self.fetcher.REPO = Path(self.directory.name)

    def release(self, records):
        body = json.dumps({"drugs": records}).encode()
        descriptor = {
            "url": "/api/data/releases/fixture/bootstrap",
            "sha256": hashlib.sha256(body).hexdigest(),
            "bytes": len(body),
        }
        manifest = {
            "schemaVersion": 2,
            "pipelineVersion": "fixture",
            "release": {
                "id": "fixture",
                "generatedAt": "2026-01-01T00:00:00Z",
                "datasets": {"bootstrap": descriptor},
            },
        }
        return body, descriptor, json.dumps(manifest).encode()

    def test_corrupt_release_bytes_are_refused(self):
        from unittest.mock import patch

        body, descriptor, manifest = self.release([{"drug_name": "Fictional"}])
        with patch.object(self.fetcher, "_get", side_effect=[manifest, body + b" "]):
            release = self.fetcher.Release()
            with self.assertRaisesRegex(SystemExit, "does not match"):
                release.dataset("bootstrap")
            self.assertEqual(release.verified_datasets, {})

    def test_snapshot_metadata_binds_the_exact_local_bytes(self):
        from contextlib import redirect_stdout
        from io import StringIO
        from unittest.mock import patch

        body, descriptor, manifest = self.release([{"drug_name": "Fictional"}])
        with (
            patch.object(self.fetcher, "_get", side_effect=[manifest, body]),
            patch.object(self.fetcher, "fetch_extra_datasets"),
            redirect_stdout(StringIO()),
        ):
            self.assertEqual(self.fetcher.main(), 0)
        meta = json.loads(self.fetcher.META.read_text())
        self.assertEqual(
            meta["snapshot_sha256"], hashlib.sha256(self.fetcher.OUT.read_bytes()).hexdigest()
        )
        self.assertEqual(meta["verified_datasets"]["bootstrap"], descriptor)
        self.assertEqual(snapshot_binding(self.fetcher.OUT)[1], "fixture")

    def test_colliding_slugs_cannot_silently_drop_a_profile(self):
        from unittest.mock import patch

        body, descriptor, manifest = self.release(
            [{"drug_name": "Fictional A"}, {"drug_name": "fictional-a"}]
        )
        self.fetcher.OUT.write_text("previous snapshot")
        with (
            patch.object(self.fetcher, "_get", side_effect=[manifest, body]),
            self.assertRaisesRegex(SystemExit, "duplicate substance slug"),
        ):
            self.fetcher.main()
        self.assertEqual(self.fetcher.OUT.read_text(), "previous snapshot")


if __name__ == "__main__":
    unittest.main()
