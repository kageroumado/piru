"""Exercise lossless dose references through the real importer and SQLite schema."""

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
from drug_community_dose_references import reference_row, validate_model
from drug_community_timelines import digest

spec = importlib.util.spec_from_file_location("piru_build", REPO / "pipeline/build/sqlite.py")
build_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_module)


def model_fixture():
    units = "mg (stated material)"
    amounts = [
        ("upper_bound", None, 2, None, False, "parsed_text"),
        ("range", 2, 4, None, None, "source_numeric"),
        ("exact", 4, 4, True, True, "parsed_text"),
        ("lower_bound", 4, None, False, None, "parsed_text"),
        ("text", None, None, None, None, "unparsed"),
    ]
    bands = []
    for index, (kind, lower, upper, lower_inclusive, upper_inclusive, basis) in enumerate(amounts):
        bands.append(
            {
                "id": f"source-route:band:{index}",
                "band": f"source_label_{index}",
                "label": f"Published label {index}",
                "text": "Unparsed source wording" if kind == "text" else f"Original {kind} wording",
                "amount": {
                    "kind": kind,
                    "lower": lower,
                    "upper": upper,
                    "lowerInclusive": lower_inclusive,
                    "upperInclusive": upper_inclusive,
                    "units": None if kind == "text" else units,
                    "basis": basis,
                },
                "status": "published_observation",
                "confidence": None if index == 0 else "low",
                "sourceIds": ["source-original-id"],
                "sourceObservationIds": ["observation-original-id"],
                "notes": ["Source colour and harm reduction quotation stay exact."],
                "calculationEligible": None,
                "provenance": {"literal": "source wording", "missing": None, "numbers": [0, 2.5]},
            }
        )
    return {
        "schemaVersion": "drug-community-dose-bands/1",
        "status": "available",
        "groups": [
            {
                "id": "source-route",
                "kind": "published_route",
                "sourcePath": "/dosages/routes_of_administration/0",
                "route": "oral",
                "units": units,
                "formulation": "Source preparation A",
                "materialBasis": "Source-stated material",
                "populationLimits": "Population was not established.",
                "notes": ["Original group note"],
                "warnings": ["Uncertainty retained."],
                "calculationEligible": None,
                "sources": [
                    {
                        "id": "source-original-id",
                        "title": "Fictional fixture source",
                        "url": None,
                        "details": {"quoted": "original colour", "unknown": None},
                    }
                ],
                "observations": [
                    {
                        "id": "observation-original-id",
                        "source_ids": ["source-original-id"],
                        "context": None,
                    }
                ],
                "bands": bands,
            }
        ],
        "notes": ["Published model note"],
        "warnings": [],
        "reportedAmountDistributions": [
            {"id": "distribution-1", "observational": True, "unknown": None}
        ],
    }


def record_fixture(name="Fictional compound"):
    return {"drug_name": name, "dosages": {"dose_bands": model_fixture()}}


class DoseReferenceImportTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "drug-community.json"
        self.db = self.database()
        self.build = build_module.Build(self.db)
        self.build.seed_sources()
        self.build.seed_effect_vocab()

    def database(self):
        db = sqlite3.connect(":memory:")
        self.addCleanup(db.close)
        db.row_factory = sqlite3.Row
        db.executescript(build_module.SCHEMA_SQL)
        return db

    def ingest(self, records):
        self.path.write_text(json.dumps(records))
        self.build.ingest_drug_community(self.path)
        return self.rows()

    def rows(self):
        return self.db.execute(
            "SELECT * FROM drug_community_dose_references ORDER BY source_name"
        ).fetchall()

    def test_every_amount_kind_and_original_evidence_survives_prose_passes(self):
        record = record_fixture()
        record["dosages"]["dose_bands"]["extension"] = {"additional": None}
        rows = self.ingest([record])
        build_module.enforce_us_english(self.db)
        build_module.enforce_voice_rule(self.db)
        self.assertEqual(len(rows), 1)
        row = self.rows()[0]
        model = json.loads(row["model_json"])
        self.assertEqual(model, record["dosages"]["dose_bands"])
        self.assertEqual(
            {band["amount"]["kind"] for band in model["groups"][0]["bands"]},
            {"exact", "range", "lower_bound", "upper_bound", "text"},
        )
        self.assertIsNone(model["groups"][0]["calculationEligible"])
        self.assertIsNone(model["groups"][0]["bands"][0]["confidence"])
        self.assertEqual(row["profile_sha256"], digest(record))
        self.assertEqual(row["snapshot_sha256"], hashlib.sha256(self.path.read_bytes()).hexdigest())
        self.assertIsNone(row["release_id"])

    def test_provisional_and_fatal_bands_are_retained_without_calculator_promotion(self):
        record = record_fixture()
        group = record["dosages"]["dose_bands"]["groups"][0]
        group["kind"] = "provisional_human"
        group["calculationEligible"] = False
        for band in group["bands"]:
            band["calculationEligible"] = False
        group["bands"][-1]["band"] = "fatal"
        rows = self.ingest([record])
        self.assertEqual(json.loads(rows[0]["model_json"]), record["dosages"]["dose_bands"])
        for table in ("dose_ranges", "durations", "half_lives", "pk_routes", "tolerance"):
            self.assertEqual(
                self.db.execute(f"SELECT count(*) FROM {table}").fetchone()[0], 0, table
            )

    def test_duplicate_routes_formulations_and_ids_stay_separate(self):
        record = record_fixture()
        model = record["dosages"]["dose_bands"]
        second = copy.deepcopy(model["groups"][0])
        second["id"] = "source-route-two"
        second["sourcePath"] = "/dosages/routes_of_administration/1"
        second["formulation"] = "Source preparation B"
        model["groups"].append(second)
        row = self.ingest([record])[0]
        self.assertEqual(json.loads(row["model_json"]), model)
        self.assertEqual(len(json.loads(row["model_json"])["groups"]), 2)

    def test_unavailable_and_withdrawn_models_retain_published_reasons(self):
        for status in ("unavailable", "withdrawn"):
            with self.subTest(status=status):
                record = record_fixture()
                model = record["dosages"]["dose_bands"]
                model.update(
                    status=status,
                    groups=[],
                    reportedAmountDistributions=[],
                    warnings=["Published reason"],
                )
                row = self.ingest([record])[0]
                self.assertEqual(json.loads(row["model_json"]), model)
                self.assertEqual(len(self.rows()), 1)

    def test_unavailable_can_retain_empty_route_context(self):
        record = record_fixture()
        model = record["dosages"]["dose_bands"]
        model["status"] = "unavailable"
        model["groups"][0]["bands"] = []
        row = self.ingest([record])[0]
        self.assertEqual(json.loads(row["model_json"]), model)

    def test_missing_legacy_field_does_not_create_or_backfill_reference(self):
        self.assertEqual(self.ingest([{"drug_name": "Fictional legacy compound"}]), [])
        self.assertEqual(
            self.ingest(
                [
                    {
                        "drug_name": "Fictional legacy compound",
                        "dosages": {"routes_of_administration": []},
                    }
                ]
            ),
            [],
        )

    def test_source_refresh_removes_missing_profiles_and_missing_references(self):
        self.assertEqual(
            len(self.ingest([record_fixture("Fictional one"), record_fixture("Fictional two")])), 2
        )
        self.assertEqual(self.ingest([{"drug_name": "Fictional one"}]), [])
        self.assertEqual(len(self.ingest([record_fixture("Fictional two")])), 1)
        self.assertEqual(self.ingest([]), [])

    def test_dedup_remaps_foreign_key_without_losing_original_source_profiles(self):
        rows = self.ingest([record_fixture("Fictional one"), record_fixture("Fictional two")])
        self.assertIn("drug_community_dose_references", self.build._substance_tables())
        self.build._merge_into(rows[0]["substance_id"], rows[1]["substance_id"])
        build_module.dedupe_database(self.db)
        merged = self.rows()
        self.assertEqual(len(merged), 2)
        self.assertEqual({row["substance_id"] for row in merged}, {rows[0]["substance_id"]})
        self.assertEqual({row["source_name"] for row in merged}, {"Fictional one", "Fictional two"})
        self.assertEqual({row["record_key"] for row in merged}, {row["record_key"] for row in rows})
        self.assertEqual(self.db.execute("PRAGMA foreign_key_check").fetchall(), [])

    def test_verified_release_binding_and_tampered_snapshot_refusal(self):
        record = record_fixture()
        self.path.write_text(json.dumps([record]))
        self.path.with_suffix(".meta.json").write_text(
            json.dumps(
                {
                    "snapshot_sha256": hashlib.sha256(self.path.read_bytes()).hexdigest(),
                    "release_id": "fixture-release",
                }
            )
        )
        self.build.ingest_drug_community(self.path)
        self.assertEqual(self.rows()[0]["release_id"], "fixture-release")
        before = [tuple(row) for row in self.rows()]
        self.path.write_text(self.path.read_text() + "\n")
        with self.assertRaisesRegex(ValueError, "snapshot does not match"):
            self.build.ingest_drug_community(self.path)
        self.assertEqual([tuple(row) for row in self.rows()], before)

    def test_reference_models_do_not_change_any_legacy_tables(self):
        record = record_fixture()
        record["dosages"]["routes_of_administration"] = [
            {
                "route": "oral",
                "units": "mg",
                "dose_ranges": {"common": "2-4 mg"},
                "notes": "Legacy note",
            }
        ]
        legacy = copy.deepcopy(record)
        del legacy["dosages"]["dose_bands"]
        baseline_db = self.database()
        baseline = build_module.Build(baseline_db)
        baseline.seed_sources()
        baseline.seed_effect_vocab()
        legacy_path = Path(self.directory.name) / "legacy.json"
        legacy_path.write_text(json.dumps([legacy]))
        baseline.ingest_drug_community(legacy_path)
        self.ingest([record])
        # The only added rows belong to this reference table. Even identifiers,
        # citations and logger/model inputs stay equal to a legacy-only import.
        for (table,) in baseline_db.execute("SELECT name FROM sqlite_master WHERE type='table'"):
            if table == "drug_community_dose_references":
                continue
            with self.subTest(table=table):
                self.assertEqual(
                    [tuple(row) for row in self.db.execute(f'SELECT * FROM "{table}"')],
                    [tuple(row) for row in baseline_db.execute(f'SELECT * FROM "{table}"')],
                )

    def test_unknown_schema_status_and_malformed_groups_fail_the_import(self):
        mutations = [
            ("schemaVersion", "drug-community-dose-bands/2"),
            ("status", "experimental"),
            ("groups", None),
            ("groups", [{}]),
            ("groups", "oral"),
            ("reportedAmountDistributions", {}),
            ("notes", [None]),
        ]
        for key, value in mutations:
            with self.subTest(key=key, value=value):
                record = record_fixture()
                record["dosages"]["dose_bands"][key] = value
                with self.assertRaisesRegex(ValueError, "invalid dose reference"):
                    self.ingest([record])
        with self.assertRaisesRegex(ValueError, "invalid dose reference"):
            self.ingest([{"drug_name": "Fictional compound", "dosages": {"dose_bands": None}}])


class DoseReferenceValidationTests(unittest.TestCase):
    def test_amount_bound_types_units_and_basis_fail_closed(self):
        mutations = [
            {"kind": "estimated"},
            {"lower": True},
            {"upper": -1},
            {"upper": float("nan")},
            {"upperInclusive": "false"},
            {"units": "g"},
            {"basis": "inferred"},
            {"kind": "exact", "lower": 1, "upper": 2},
            {"kind": "range", "lower": 3, "upper": 2},
            {"kind": "lower_bound", "lower": 1, "upper": 2},
            {"kind": "text", "basis": "unparsed"},
        ]
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                model = model_fixture()
                model["groups"][0]["bands"][0]["amount"].update(mutation)
                with self.assertRaises(ValueError):
                    validate_model(model)

    def test_duplicate_ids_unresolved_evidence_and_false_eligibility_are_required(self):
        def invalid_model(mutator):
            model = model_fixture()
            mutator(model, model["groups"][0], model["groups"][0]["bands"][0])
            with self.assertRaises(ValueError):
                validate_model(model)

        mutations = [
            lambda model, group, band: model["groups"].append(copy.deepcopy(group)),
            lambda model, group, band: group["bands"].append(copy.deepcopy(band)),
            lambda model, group, band: group["sources"].append(copy.deepcopy(group["sources"][0])),
            lambda model, group, band: band.update(sourceIds=["missing-source"]),
            lambda model, group, band: band.update(sourceObservationIds=["missing-observation"]),
            lambda model, group, band: group.update(
                kind="provisional_human", calculationEligible=None
            ),
            lambda model, group, band: group.update(
                kind="provisional_human", calculationEligible=False
            ),
            lambda model, group, band: band.update(band="fatal", calculationEligible=True),
            lambda model, group, band: group.update(kind="unrecognized"),
            lambda model, group, band: band.update(calculationEligible=1),
            lambda model, group, band: band.update(confidence=True),
            lambda model, group, band: band.update(provenance=[]),
        ]
        for index, mutation in enumerate(mutations):
            with self.subTest(index=index):
                invalid_model(mutation)

    def test_status_cannot_contradict_published_bands(self):
        for status in ("unavailable", "withdrawn"):
            with self.subTest(status=status):
                model = model_fixture()
                model["status"] = status
                with self.assertRaises(ValueError):
                    validate_model(model)
        model = model_fixture()
        model["groups"] = []
        with self.assertRaises(ValueError):
            validate_model(model)
        model["status"] = "withdrawn"
        with self.assertRaises(ValueError):
            validate_model(model)  # withdrawn distributions must disappear too

    def test_nonfinite_opaque_evidence_cannot_escape_json_validation(self):
        model = model_fixture()
        model["groups"][0]["sources"][0]["details"]["not_json"] = float("inf")
        with self.assertRaises(ValueError):
            validate_model(model)

    def test_record_key_changes_with_snapshot_or_source_identity(self):
        first = reference_row(record_fixture("Fictional one"), "snapshot-a")
        second = reference_row(record_fixture("Fictional two"), "snapshot-a")
        refreshed = reference_row(record_fixture("Fictional one"), "snapshot-b")
        self.assertEqual(len({row["record_key"] for row in (first, second, refreshed)}), 3)


if __name__ == "__main__":
    unittest.main()
