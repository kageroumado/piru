#!/usr/bin/env python3
"""What the dose.wiki snapshot must never contain, and what the ingest must read.

Run: python3 pipeline/build/tests/test_dosewiki.py
"""

from __future__ import annotations

import importlib.util
import json
import sqlite3
import sys
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
SNAPSHOT = REPO / "data/sources/dosewiki.json"
CURATED_IDS = REPO / "data/curated/dosewiki-ids.json"
SUBSTANCE_IDS = REPO / "data/curated/substance-ids.json"
DB = REPO / "Piru/Data/piru-substances.sqlite"

sys.path.insert(0, str(REPO / "pipeline" / "build"))
import sqlite as build  # noqa: E402


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


class TestCuratedJoin(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not SNAPSHOT.exists() or not CURATED_IDS.exists():
            raise unittest.SkipTest("dose.wiki snapshot or curated join not present")
        cls.records = json.loads(SNAPSHOT.read_text())["records"]
        cls.entries = build.load_dosewiki_ids()

    def test_every_published_slug_is_decided(self):
        """A slug is either joined to a substance or explicitly unmapped.

        `ingest_dosewiki` fails the build on an undecided slug; this says so
        before the build does, and names them.
        """
        undecided = [r["slug"] for r in self.records if r["slug"] not in self.entries]
        self.assertEqual([], undecided)

    def test_an_unmapped_slug_says_why(self):
        for slug, entry in self.entries.items():
            if entry.get("substance_uid") is None:
                self.assertTrue(entry.get("note"), f"{slug}: unmapped with no note")

    def test_every_mapped_uid_matches_its_pinned_name(self):
        """The PSID registry is what makes the uid the durable half of an entry.

        `substance_uid` is assigned long after ingest, so the ingest resolves by
        name; the uid is the check that the name still points where the join
        said it did.
        """
        pinned = {
            name: uid
            for name, uid in json.loads(SUBSTANCE_IDS.read_text()).items()
            if not name.startswith("_")
        }
        wrong = [
            f"{slug}: {entry['name']} is pinned {pinned.get(entry['name'])!r}, "
            f"entry says {entry['substance_uid']!r}"
            for slug, entry in self.entries.items()
            if entry.get("substance_uid")
            and pinned.get(entry.get("name")) != entry["substance_uid"]
        ]
        self.assertEqual([], wrong)


class TestParsers(unittest.TestCase):
    def test_dose_tier_names_land_on_pirus_ladder(self):
        self.assertEqual("common", build.DOSEWIKI_TIERS["moderate"])
        self.assertEqual("light", build.DOSEWIKI_TIERS["light"])

    def test_both_micro_signs_read_as_one_unit(self):
        for sign in ("µg", "μg"):
            self.assertEqual("µg", build.canonical_mass_unit(sign))

    def test_route_casing_and_abbreviation(self):
        self.assertEqual("oral", build.normalise_route("Oral"))
        self.assertEqual("insufflation", build.normalise_route("Insufflated"))
        self.assertEqual("intramuscular", build.normalise_route("I.M."))
        self.assertEqual("inhalation", build.normalise_route("vapourized"))

    def test_duration_stages_convert_to_minutes(self):
        stages = {
            "onset": {"min": 20, "max": 70, "unit": "minutes"},
            "come_up": {"min": 30, "max": 60, "unit": "minutes"},
            "peak": {"min": 2, "max": 3.5, "unit": "hours"},
            "after_effects": {"min": 2, "max": 24, "unit": "hours"},
            "total_duration": {"min": 3, "max": 6, "unit": "hours"},
        }
        profile = build.dosewiki_duration_profile(stages)
        self.assertEqual({"min": 20.0, "max": 70.0}, profile["onset"])
        self.assertEqual({"min": 30.0, "max": 60.0}, profile["comeup"])
        self.assertEqual({"min": 120.0, "max": 210.0}, profile["peak"])
        self.assertEqual({"min": 120.0, "max": 1440.0}, profile["afterglow"])
        self.assertEqual({"min": 180.0, "max": 360.0}, profile["total"])

    def test_half_life_text_yields_a_midpoint(self):
        self.assertEqual(510.0, build.dosewiki_half_life_minutes("7-10 hours"))
        self.assertEqual(39.0, build.dosewiki_half_life_minutes("~39 minutes"))
        self.assertEqual(3.0 * 1440, build.dosewiki_half_life_minutes("3 days"))
        for text in ("", "variable", "several hours", "unknown"):
            self.assertIsNone(build.dosewiki_half_life_minutes(text))

    def test_only_a_stated_value_with_a_unit_is_an_affinity(self):
        self.assertEqual(("ec50_nm", 74.3), build.dosewiki_affinity("EC50 74.3 nM (racemate)"))
        self.assertEqual(("ki_nm", 345.0), build.dosewiki_affinity("Ki 345 ± 118 nM in an assay"))
        self.assertEqual(("ic50_nm", 1280.0), build.dosewiki_affinity("IC50 1.28 µM"))
        for text in (
            "Ki <10 μM",
            "Ki >30,000 nM",
            "pKi 9.4",
            "nanomolar",
            "Lower affinity",
            "40 nM (DXM), 484 nM (DXO)",
            "",
        ):
            self.assertIsNone(build.dosewiki_affinity(text), text)

    def test_an_action_is_mapped_or_the_row_is_dropped(self):
        self.assertEqual(
            "partialAgonist", build.dosewiki_action("5-HT2A receptor agonist (partial)", None)
        )
        self.assertEqual("agonist", build.dosewiki_action("5-HT2A receptor agonist (full)", None))
        self.assertEqual("releasingAgent", build.dosewiki_action("Serotonin releasing agent", None))
        self.assertEqual(
            "positiveAllostericModulator",
            build.dosewiki_action(
                "GABA-A receptor positive allosteric modulator (benzo site)", None
            ),
        )
        self.assertEqual("antagonist", build.dosewiki_action(None, "Antagonist"))
        self.assertEqual(
            "enzymeInhibitor", build.dosewiki_action("Monoamine oxidase inhibitor (MAO-A)", None)
        )
        # A row whose tag and efficacy name different actions, and one that
        # names none: both are dropped rather than guessed at. The second pair
        # is methylone's SERT row, where "also acts as" adds an action the
        # single `action` column has no room for.
        self.assertIsNone(
            build.dosewiki_action("Alpha-1 adrenergic receptor agonist", "Antagonist")
        )
        self.assertIsNone(
            build.dosewiki_action("Serotonin releasing agent", "Also acts as reuptake inhibitor")
        )
        self.assertIsNone(build.dosewiki_action(None, None))
        self.assertIsNone(build.dosewiki_action("Potential target; unverified", None))
        self.assertIsNone(
            build.dosewiki_action(
                "Described as full agonist in some sources and partial agonist in others", None
            )
        )

    def test_a_transporter_row_states_the_measure_its_action_implies(self):
        self.assertTrue(build.dosewiki_measure_fits_action("SERT", "releasingAgent", "ec50_nm"))
        self.assertTrue(build.dosewiki_measure_fits_action("DAT", "reuptakeInhibitor", "ki_nm"))
        self.assertFalse(build.dosewiki_measure_fits_action("DAT", "releasingAgent", "ki_nm"))
        self.assertFalse(build.dosewiki_measure_fits_action("NET", "reuptakeInhibitor", "ec50_nm"))
        # Only the monoamine transporters carry the release/uptake distinction.
        self.assertTrue(build.dosewiki_measure_fits_action("5-HT2A", "agonist", "ki_nm"))

    def test_only_a_row_naming_its_own_source_is_citable(self):
        references = {"doi-x": {"doi": "10.1000/x"}, "pm-y": {"pmid": "123456"}}
        self.assertEqual(
            "doi:10.1000/x",
            build.dosewiki_row_reference({"affinity": "Ki 4 nM[cite:doi-x]"}, references),
        )
        self.assertEqual(
            "pmid:123456", build.dosewiki_row_reference({"tag": "agonist[cite:pm-y]"}, references)
        )
        self.assertIsNone(build.dosewiki_row_reference({"affinity": "Ki 4 nM"}, references))
        self.assertIsNone(
            build.dosewiki_row_reference({"affinity": "Ki 4 nM[cite:missing]"}, references)
        )

    def test_a_cas_number_passes_its_own_check_digit(self):
        self.assertTrue(build.cas_check_digit_holds("50-78-2"))  # aspirin
        self.assertTrue(build.cas_check_digit_holds("42542-10-9"))  # MDMA
        self.assertFalse(build.cas_check_digit_holds("42542-10-8"))
        self.assertFalse(build.cas_check_digit_holds("not-a-cas"))

    def test_a_target_folds_the_way_the_app_folds_it(self):
        self.assertEqual("NMDA", build.display_receptor_target("NMDA receptor (PCP site)"))
        self.assertEqual("MOR", build.display_receptor_target("MOR (+)-tramadol"))
        self.assertEqual("5-ht2a", build.fold_receptor_target("5-HT2A  receptor"))


class TestBuiltDatabase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not DB.exists():
            raise unittest.SkipTest("piru-substances.sqlite not built")
        cls.db = sqlite3.connect(DB)
        cls.db.row_factory = sqlite3.Row
        row = cls.db.execute("SELECT id FROM sources WHERE slug='dosewiki'").fetchone()
        if row is None:
            raise unittest.SkipTest("dosewiki not in the shipped sources table")
        cls.source_id = row["id"]

    @classmethod
    def tearDownClass(cls):
        if hasattr(cls, "db"):
            cls.db.close()

    def test_dosewiki_is_last_in_the_default_order(self):
        last = self.db.execute(
            "SELECT slug FROM sources ORDER BY default_priority DESC LIMIT 1"
        ).fetchone()
        self.assertEqual("dosewiki", last["slug"])

    def test_it_never_drives_a_class_field(self):
        """Category and tags are what the interaction engine keys on, so
        dose.wiki is barred from them the same way drug.community is."""
        for table in ("categories", "tags"):
            count = self.db.execute(
                f"SELECT COUNT(*) FROM {table} WHERE source_id = ?", (self.source_id,)
            ).fetchone()[0]
            self.assertEqual(0, count, table)

    def test_every_binding_carries_a_number_a_citation_and_a_low_confidence(self):
        rows = self.db.execute(
            "SELECT ki_nm, ec50_nm, ic50_nm, confidence, action, citation_id"
            "  FROM bindings WHERE source_id = ?",
            (self.source_id,),
        ).fetchall()
        for row in rows:
            self.assertTrue(
                row["ki_nm"] is not None or row["ec50_nm"] is not None or row["ic50_nm"] is not None
            )
            self.assertIsNotNone(row["citation_id"])
            self.assertEqual("LOW", row["confidence"])
            self.assertNotEqual("modulator", row["action"])

    def test_dose_rows_carry_the_recreational_regime(self):
        """`salt_form` is deliberately not checked: dose.wiki never states a
        basis so the ingester writes NULL, and `apply_salt_metadata` then stamps
        the family's salt onto every row of a salt member, dose.wiki's included.
        """
        rows = self.db.execute(
            "SELECT dose_context FROM dose_ranges WHERE source_id = ?", (self.source_id,)
        ).fetchall()
        self.assertTrue(rows)
        for row in rows:
            self.assertEqual("recreational", row["dose_context"])

    def test_a_half_life_says_which_route_and_what_the_source_wrote(self):
        """The stored number is the midpoint of a range; the note is what makes
        the interval and the approximation sign it came from readable."""
        rows = self.db.execute(
            "SELECT half_life_minutes, notes FROM half_lives WHERE source_id = ?",
            (self.source_id,),
        ).fetchall()
        self.assertTrue(rows)
        for row in rows:
            self.assertGreater(row["half_life_minutes"], 0)
            self.assertIn(":", row["notes"] or "")

    def test_a_reviewed_summary_outranks_the_copied_and_translated_ones(self):
        """The field-priority override is what puts it there; on source priority
        alone dose.wiki resolves last, behind both."""
        override = self.db.execute(
            "SELECT priority FROM source_field_priority"
            " WHERE field = 'descriptions' AND source_id = ?",
            (self.source_id,),
        ).fetchone()
        self.assertIsNotNone(override)
        for slug in ("psychonautwiki", "freeodwiki"):
            rank = self.db.execute(
                "SELECT default_priority - 1 FROM sources WHERE slug = ?", (slug,)
            ).fetchone()[0]
            self.assertLess(override["priority"], rank)


class IdentityCorrectionTests(unittest.TestCase):
    """`dosewiki_identity_corrections` writes only where the stored row
    contradicts itself and dose.wiki's record is consistent with itself."""

    def test_key_from_own_smiles(self):
        # 4-EMC: flat SMILES, a stereo layer fabricated onto the key.
        stored = {
            "smiles": "CC(NC)C(=O)c1ccc(CC)cc1",
            "inchikey": "FUYPDKFWOHBUFT-VIFPVBQESA-N",
            "cas": None,
        }
        claimed = {"smiles": "CC(NC)C(=O)c1ccc(CC)cc1", "inchikey": "", "cas": ""}
        self.assertEqual(
            [("inchikey", "FUYPDKFWOHBUFT-UHFFFAOYSA-N", "key_from_own_smiles")],
            build.dosewiki_identity_corrections(stored, claimed),
        )

    def test_smiles_from_own_key(self):
        # 2C-B drawn as the 2,4-dimethoxy-5-bromo regioisomer under the right key.
        stored = {
            "smiles": "NCCc1cc(Br)c(OC)cc1OC",
            "inchikey": "YMHOBZXQZVXHBM-UHFFFAOYSA-N",
            "cas": None,
        }
        claimed = {"smiles": "BrC1=CC(=C(C=C1OC)CCN)OC", "inchikey": "", "cas": ""}
        rules = [rule for _, _, rule in build.dosewiki_identity_corrections(stored, claimed)]
        self.assertEqual(["smiles_from_own_key"], rules)

    def test_freebase_replaces_salt(self):
        stored = {
            "smiles": "[Cl-].CC(N)Cc1cccs1.[H+]",
            "inchikey": "MJRDCJBNRNAXIK-UHFFFAOYSA-N",
            "cas": None,
        }
        claimed = {"smiles": "CC(CC1=CC=CS1)N", "inchikey": "", "cas": ""}
        out = build.dosewiki_identity_corrections(stored, claimed)
        self.assertEqual({"smiles", "inchikey", "formula"}, {column for column, _, _ in out})
        self.assertTrue(all(rule == "freebase_replaces_salt" for _, _, rule in out))

    def test_consistent_rows_are_left_alone(self):
        stored = {
            "smiles": "CC(CC1=CC=CS1)N",
            "inchikey": "NYVQQTOGYLBBDQ-UHFFFAOYSA-N",
            "cas": "30433-93-3",
        }
        claimed = {"smiles": "CC(CC1=CC=CS1)N", "inchikey": "", "cas": "30433-93-3"}
        self.assertEqual([], build.dosewiki_identity_corrections(stored, claimed))

    def test_two_stereo_layers_are_never_settled(self):
        # Morphine as stored before 2026-09-11 (isomorphine) against dose.wiki's
        # morphine: same skeleton, both stereo-specified, consistent on each
        # side — no rule may pick one.
        stored = {
            "smiles": "CN1CC[C@]23c4c5ccc(O)c4O[C@H]2[C@H](O)C=C[C@H]3[C@H]1C5",
            "inchikey": "BQJCRHHNABKAKU-NOSXKOESSA-N",
            "cas": "57-27-2",
        }
        claimed = {
            "smiles": "CN1CC[C@]23[C@@H]4[C@H]1CC5=C2C(=C(C=C5)O)O[C@H]3[C@H](C=C4)O",
            "inchikey": "",
            "cas": "57-27-2",
        }
        self.assertEqual([], build.dosewiki_identity_corrections(stored, claimed))

    def test_bad_check_digit_yields_to_a_valid_cas(self):
        stored = {
            "smiles": "CC(CC1=CC=CS1)N",
            "inchikey": "NYVQQTOGYLBBDQ-UHFFFAOYSA-N",
            "cas": "30433-93-4",
        }
        claimed = {"smiles": "CC(CC1=CC=CS1)N", "inchikey": "", "cas": "30433-93-3"}
        self.assertEqual(
            [("cas", "30433-93-3", "cas_check_digit")],
            build.dosewiki_identity_corrections(stored, claimed),
        )

    def test_a_self_inconsistent_claim_is_no_arbiter(self):
        stored = {
            "smiles": "CC(NC)C(=O)c1ccc(CC)cc1",
            "inchikey": "FUYPDKFWOHBUFT-VIFPVBQESA-N",
            "cas": None,
        }
        claimed = {
            "smiles": "CC(NC)C(=O)c1ccc(CC)cc1",
            "inchikey": "FUYPDKFWOHBUFT-VIFPVBQESA-N",  # does not recompute
            "cas": "",
        }
        self.assertEqual([], build.dosewiki_identity_corrections(stored, claimed))


class DoseGateTests(unittest.TestCase):
    """The rules in `build/dose_gates.py` against a throwaway database."""

    @classmethod
    def setUpClass(cls):
        import importlib.util
        import sqlite3

        spec = importlib.util.spec_from_file_location(
            "dose_gates", Path(__file__).resolve().parents[1] / "dose_gates.py"
        )
        cls.gates = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.gates)
        cls.sqlite3 = sqlite3

    def _db(self):
        con = self.sqlite3.connect(":memory:")
        con.executescript(
            """
            CREATE TABLE substances (id INTEGER PRIMARY KEY, canonical_name TEXT);
            CREATE TABLE sources (id INTEGER PRIMARY KEY, slug TEXT);
            CREATE TABLE class_contexts (id INTEGER PRIMARY KEY, slug TEXT);
            CREATE TABLE substance_classes (substance_id INTEGER, class_context_id INTEGER);
            CREATE TABLE dose_ranges (id INTEGER PRIMARY KEY, substance_id INTEGER, route TEXT,
                source_id INTEGER, unit TEXT, threshold REAL, light_lower REAL, light_upper REAL,
                common_lower REAL, common_upper REAL, strong_lower REAL, strong_upper REAL,
                heavy REAL, citation_id INTEGER);
            CREATE TABLE durations (id INTEGER PRIMARY KEY, substance_id INTEGER, route TEXT,
                source_id INTEGER, phase TEXT, min_minutes REAL, max_minutes REAL);
            INSERT INTO substances VALUES (1, 'Acetylfentanyl'), (2, 'Fentanyl'), (3, 'Meth');
            INSERT INTO sources VALUES (1, 'tripsit'), (2, 'piru-curated');
            INSERT INTO class_contexts VALUES (10, 'fentanyl-anilidopiperidines');
            INSERT INTO substance_classes VALUES (1, 10), (2, 10);
            INSERT INTO dose_ranges (substance_id, route, source_id, unit, common_lower, common_upper)
                VALUES (1, 'oral', 1, 'mg', 3, 5),       -- milligrams on a fentanyl: gated
                       (2, 'oral', 1, 'µg', 50, 100),    -- micrograms: kept
                       (1, 'oral', 2, 'mg', 3, 5);       -- exempt source: kept
            INSERT INTO dose_ranges (substance_id, route, source_id, unit, common_lower, common_upper, citation_id)
                VALUES (1, 'sublingual', 1, 'mg', 3, 5, 7);  -- cited: kept
            INSERT INTO durations (substance_id, route, source_id, phase, min_minutes, max_minutes)
                VALUES (3, 'oral', 1, 'comeup', 0.08, 0.17),   -- seconds on a pill: gated
                       (3, 'intravenous', 1, 'comeup', 0.08, 0.17),  -- seconds IV: kept
                       (3, 'oral', 1, 'onset', 15, 45);
            """
        )
        return con

    def test_class_ceiling_and_absorption_floor(self):
        con = self._db()
        gates = [
            {
                "class_context": "fentanyl-anilidopiperidines",
                "max_tier_mg": 2.0,
                "exempt_sources": ["piru-curated"],
                "reason": "test",
            }
        ]
        result = self.gates.GateResult()
        self.gates.apply_class_ceilings(con.cursor(), gates, result)
        self.gates.apply_absorption_floor(con.cursor(), result)
        self.assertEqual(
            [("Acetylfentanyl", "tripsit", "oral"), ("Meth", "tripsit", "oral")],
            sorted((h.substance, h.source, h.route) for h in result.hits),
        )
        self.assertEqual(3, con.execute("SELECT COUNT(*) FROM dose_ranges").fetchone()[0])
        self.assertEqual(2, con.execute("SELECT COUNT(*) FROM durations").fetchone()[0])

    def test_non_mass_units_are_outside_the_ceiling(self):
        self.assertIsNone(self.gates.mg_factor("µg/kg"))
        self.assertEqual(0.001, self.gates.mg_factor("µg"))
        self.assertEqual(1.0, self.gates.mg_factor("mg (freebase)"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
