"""The build's dose gates (`pipeline/build/dose_gates.py`), the Shulgin DOSAGE
rule, the drug.community tier reader and the upstream-drop report: unit tests
on throwaway databases, then invariants over the committed intermediate and the
built database."""

import importlib.util
import json
import re
import sqlite3
import sys
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "pipeline/build"))
import dose_gates  # noqa: E402

_spec = importlib.util.spec_from_file_location("piru_build", REPO / "pipeline/build/sqlite.py")
build_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(build_module)

DB_PATH = REPO / "Piru/Data/piru-substances.sqlite"
SOURCED = REPO / "data/intermediate/sourced-substances.json"
UPSTREAM_DROPS = REPO / "data/snapshots/unparsed-upstream.json"

_SCHEMA = """
CREATE TABLE substances (id INTEGER PRIMARY KEY, canonical_name TEXT);
CREATE TABLE sources (id INTEGER PRIMARY KEY, slug TEXT);
CREATE TABLE dose_ranges (id INTEGER PRIMARY KEY, substance_id INTEGER, route TEXT,
    source_id INTEGER, unit TEXT, threshold REAL, light_lower REAL, light_upper REAL,
    common_lower REAL, common_upper REAL, strong_lower REAL, strong_upper REAL,
    heavy REAL, notes TEXT, isomer TEXT, dose_context TEXT DEFAULT 'recreational',
    citation_id INTEGER);
"""


def _db(rows: list[tuple]) -> sqlite3.Connection:
    """rows: (substance id, source id, route, unit, common lower, common upper,
    strong upper, heavy, citation id, dose context)."""
    con = sqlite3.connect(":memory:")
    con.executescript(_SCHEMA)
    con.executemany(
        "INSERT INTO substances VALUES (?, ?)", [(1, "PMA"), (2, "Morphine"), (3, "Kratom")]
    )
    con.executemany(
        "INSERT INTO sources VALUES (?, ?)",
        [(i, s) for i, s in enumerate(("a", "b", "c", "d", "piru-curated"), start=1)],
    )
    con.executemany(
        "INSERT INTO dose_ranges (substance_id, source_id, route, unit, common_lower,"
        " common_upper, strong_upper, heavy, citation_id, dose_context)"
        " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        rows,
    )
    return con


class ShulginDosageVerdict(unittest.TestCase):
    def test_no_activity_bounds(self):
        for text in (
            "greater than 60 mg.",
            "> 25 mgs",
            ">350 mg (orally)",
            "300 mg or greater.",
            "40 mg and above.",
            "30 mg or more.",
            "probably above 50 mg.",
            "Greater than 5 mg",
            "unknown.",
            "greater than 150 mg (alone) or 100 - 150 mg (with alcohol).",
        ):
            self.assertEqual("bound", dose_gates.shulgin_dosage_verdict(text), text)

    def test_doses(self):
        self.assertEqual("range", dose_gates.shulgin_dosage_verdict("12 - 24 mg."))
        self.assertEqual("range", dose_gates.shulgin_dosage_verdict("60 to 200 micrograms"))
        self.assertEqual("single", dose_gates.shulgin_dosage_verdict("350 mg."))
        self.assertEqual("single", dose_gates.shulgin_dosage_verdict("250 mg, intravenously"))
        self.assertEqual("none", dose_gates.shulgin_dosage_verdict("a few hundred milligrams."))


class ToxicFloors(unittest.TestCase):
    FLOOR = {
        "substance": "PMA",
        "route": "oral",
        "floor_mg": 60,
        "kind": "severe",
        "citation": "x",
    }

    def test_an_uncited_tier_reaching_the_floor_goes(self):
        con = _db(
            [
                (1, 1, "oral", "mg", 50, 80, None, None, None, "recreational"),  # common 80: gated
                (1, 2, "oral", "mg", 20, 40, None, 60, None, "recreational"),  # heavy only: kept
                (1, 3, "oral", "mg", 50, 80, None, None, 9, "recreational"),  # cited: kept
                (1, 4, "oral", "g", 0.05, 0.08, None, None, None, "recreational"),  # 80 mg in g
            ]
        )
        result = dose_gates.GateResult()
        self.assertEqual(2, dose_gates.apply_toxic_floors(con.cursor(), [self.FLOOR], result))
        self.assertEqual(["a", "d"], sorted(h.source for h in result.hits))


class CrossSourceOutliers(unittest.TestCase):
    def test_tenfold_from_three_sources_goes(self):
        con = _db(
            [
                (2, 1, "oral", "mg", 200, 400, None, None, None, "recreational"),  # 17×: gated
                (2, 2, "oral", "mg", 10, 20, None, None, None, "recreational"),
                (2, 3, "oral", "mg", 15, 30, None, None, None, "recreational"),
                (2, 4, "oral", "mg", 10, 25, None, None, None, "recreational"),
                (2, 1, "oral", "mg", 200, 400, None, None, None, "therapeutic"),  # alone: kept
            ]
        )
        result = dose_gates.GateResult()
        self.assertEqual(1, dose_gates.apply_cross_source_outliers(con.cursor(), result))
        self.assertEqual([("Morphine", "a")], [(h.substance, h.source) for h in result.hits])

    def test_two_other_sources_are_not_a_median(self):
        con = _db(
            [
                (2, 1, "oral", "mg", 200, 400, None, None, None, "recreational"),
                (2, 2, "oral", "mg", 10, 20, None, None, None, "recreational"),
                (2, 3, "oral", "mg", 15, 30, None, None, None, "recreational"),
            ]
        )
        self.assertEqual(
            0, dose_gates.apply_cross_source_outliers(con.cursor(), dose_gates.GateResult())
        )

    def test_curated_and_cited_rows_are_never_the_outlier(self):
        for outlier_source, citation in ((5, None), (4, 7)):
            con = _db(
                [
                    (3, 1, "oral", "mg", 10, 20, None, None, None, "recreational"),
                    (3, 2, "oral", "mg", 10, 20, None, None, None, "recreational"),
                    (3, 3, "oral", "mg", 10, 20, None, None, None, "recreational"),
                    *(
                        [(3, 4, "oral", "mg", 10, 20, None, None, None, "recreational")]
                        if outlier_source == 5
                        else [(3, 5, "oral", "mg", 10, 20, None, None, None, "recreational")]
                    ),
                    (3, outlier_source, "oral", "g", 2, 5, None, None, citation, "recreational"),
                ]
            )
            self.assertEqual(
                0, dose_gates.apply_cross_source_outliers(con.cursor(), dose_gates.GateResult())
            )


class ForeignScripts(unittest.TestCase):
    def bad(self, text, *, name=False, foreign_row=False):
        return dose_gates.foreign_characters(text, name_column=name, foreign_row=foreign_row)

    def test_a_letter_inside_a_number_is_refused(self):
        self.assertTrue(self.bad("10ጰ min"))
        self.assertTrue(self.bad("~75ጒ5 mg"))
        self.assertTrue(self.bad("IR: ~10В h"))
        self.assertTrue(self.bad("a lone ጰ letter"))
        self.assertTrue(self.bad("unassigned  private use"))

    def test_text_that_belongs(self):
        self.assertFalse(self.bad("2–6 h, ~5 µg/kg, ≥ 3 × 10⁻² mol, ℓ, Å, ﬁ"))
        self.assertFalse(self.bad("Bromantane (Ladasten / Ладастен) is Russian"))
        self.assertFalse(self.bad("「ボルノレキサントの C max」 (PMDA review)"))
        self.assertFalse(self.bad("Semax（原文标签为Семакс）", foreign_row=True))
        self.assertFalse(self.bad("กระท่อม", name=True))
        self.assertFalse(self.bad("ʻawa"))

    def test_the_gate_drops_the_cell_never_the_characters(self):
        con = sqlite3.connect(":memory:")
        con.executescript(
            """
            CREATE TABLE substances (id INTEGER PRIMARY KEY, canonical_name TEXT);
            CREATE TABLE sources (id INTEGER PRIMARY KEY, slug TEXT);
            CREATE TABLE dose_ranges (id INTEGER PRIMARY KEY, substance_id INTEGER,
                source_id INTEGER, route TEXT, notes TEXT);
            CREATE TABLE timelines (id INTEGER PRIMARY KEY, substance_id INTEGER,
                text_json TEXT NOT NULL);
            INSERT INTO substances VALUES (1, 'Dipentylone');
            INSERT INTO sources VALUES (1, 'drug.community');
            INSERT INTO dose_ranges VALUES (1, 1, 1, 'oral', 'below ~75ጒ5 mg oral');
            INSERT INTO timelines VALUES (1, 1, '{"onset":"10ጰ min","peak":"1–2 h"}');
            """
        )
        result = dose_gates.GateResult()
        self.assertEqual(2, dose_gates.apply_script_gate(con.cursor(), result))
        self.assertIsNone(con.execute("SELECT notes FROM dose_ranges").fetchone()[0])
        self.assertEqual(
            {"onset": None, "peak": "1–2 h"},
            json.loads(con.execute("SELECT text_json FROM timelines").fetchone()[0]),
        )
        self.assertEqual({"Dipentylone"}, {h.substance for h in result.hits})


class DrugCommunityTierReader(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:")
        self.db.executescript(build_module.SCHEMA_SQL)
        self.build = build_module.Build(self.db)
        self.build.seed_sources()

    def read(self, tier, raw, unit="mg"):
        return self.build._read_dc_tier(None, "oral", tier, raw, unit)

    def test_a_lone_figure_in_a_range_tier_is_that_figure(self):
        self.assertEqual({"lower": 1.0, "upper": 1.0}, self.read("common", "1 mg"))
        self.assertEqual({"lower": 1000.0, "upper": 1000.0}, self.read("common", "1 mg", "µg"))
        self.assertEqual([], self.build.upstream_drops)

    def test_what_cannot_be_read_is_reported(self):
        for tier, raw in (
            ("common", "120 or 180 mcg (severity-based initial dose)"),
            ("strong", "≥1 mg (high risk)"),
            ("light", "15 mg/day"),
            ("common", "15ፀ mg"),
            ("threshold", "No activity observed up to 220 mg (sub‑threshold testing only)"),
        ):
            self.assertIsNone(self.read(tier, raw), raw)
        self.assertEqual(5, len(self.build.upstream_drops))

    def test_numbers_a_read_discards_are_reported(self):
        self.assertEqual(15.0, self.read("threshold", "15–25 µg", "µg"))
        self.assertEqual(
            {"lower": 200.0, "upper": 800.0}, self.read("common", "200–800 mg or ~3–10 mg/kg")
        )
        self.assertEqual(
            ["range_in_single_value_tier", "extra_numbers_ignored"],
            [d["reason"] for d in self.build.upstream_drops],
        )

    def test_nothing_stated_is_not_a_drop(self):
        self.assertIsNone(self.read("heavy", "—"))
        self.assertIsNone(self.read("heavy", "Not recommended"))
        self.assertEqual([], self.build.upstream_drops)


class ExceptionsMustSuppressSomething(unittest.TestCase):
    def test_a_lookup_alone_is_not_use(self):
        mapping = build_module.ExceptionMap({"x": {"oral"}, "y": None})
        hit = mapping.get("x")
        self.assertFalse(hit.covers("insufflated"))
        self.assertTrue(hit.covers("oral", effective=False))
        self.assertEqual(set(), mapping.used)
        self.assertTrue(mapping.get("y").covers("IV"))
        self.assertEqual({("y", "intravenous")}, mapping.used)
        self.assertFalse(mapping.get("z"))


# ------------------------------------------------------------ committed data


class ToxicFloorFile(unittest.TestCase):
    def test_every_floor_is_cited_and_names_a_substance(self):
        floors = dose_gates.load_toxic_floors()
        self.assertTrue(floors)
        names = None
        if DB_PATH.exists():
            con = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
            names = {r[0].lower() for r in con.execute("SELECT canonical_name FROM substances")}
            con.close()
        for floor in floors:
            citation = floor.get("citation") or ""
            self.assertRegex(
                citation,
                r"pmid:\d+|doi:10\.|\b10\.\d{4,}/|ISBN [0-9-]+|set ?id",
                f"{floor.get('substance')}: a floor needs a PMID, DOI, ISBN or label set id",
            )
            self.assertTrue((floor.get("quote") or "").strip(), f"{floor['substance']}: quote")
            self.assertIn(floor.get("kind"), ("fatal", "severe"))
            self.assertGreater(float(floor["floor_mg"]), 0)
            if names is not None:
                self.assertIn(floor["substance"].lower(), names, floor["substance"])


class ShulginRecords(unittest.TestCase):
    """The PIHKAL/TIHKAL routes in the committed intermediate."""

    @classmethod
    def setUpClass(cls):
        records = json.loads(SOURCED.read_text())
        cls.routes = [
            (r["provenance"], r["substance"]["name"], route)
            for r in records
            if r["provenance"] in build_module.SHULGIN_BOOK_SLUGS
            for route in r["substance"].get("routes") or []
        ]

    def test_every_dose_carries_the_text_it_came_from(self):
        missing = [(s, n) for s, n, r in self.routes if r.get("doses") and not r.get("dosageText")]
        self.assertEqual(missing, [])

    def test_every_shipped_ladder_is_the_books_own_figures(self):
        """A range ships as the range, a single figure as itself (no invented
        spread), and a no-activity bound never reaches the ingest as a dose."""
        wrong = []
        for slug, name, r in self.routes:
            common = (r.get("doses") or {}).get("common")
            if not common:
                continue
            text = r["dosageText"]
            verdict = dose_gates.shulgin_dosage_verdict(text)
            numbers = [float(n) for n in re.findall(r"\d+(?:\.\d+)?", text.split("(")[0])]
            if verdict == "range":
                ok = [common["lower"], common["upper"]] == numbers[:2]
            elif verdict == "single":
                ok = common["lower"] == common["upper"] == numbers[0]
            else:
                ok = verdict == "bound"
            if not ok:
                wrong.append((slug, name, text, common))
        self.assertEqual(wrong, [])

    @unittest.skipUnless(DB_PATH.exists(), "piru-substances.sqlite not built")
    def test_no_no_activity_bound_ships(self):
        bound = {
            (slug, name.lower())
            for slug, name, r in self.routes
            if r.get("doses") and dose_gates.shulgin_dosage_verdict(r["dosageText"]) == "bound"
        }
        self.assertTrue(bound)
        con = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
        shipped = con.execute(
            "SELECT DISTINCT src.slug, lower(s.canonical_name) FROM dose_ranges d"
            "  JOIN sources src ON src.id = d.source_id"
            "  JOIN substances s ON s.id = d.substance_id"
            " WHERE src.slug IN ('erowid-pihkal', 'erowid-tihkal')"
        ).fetchall()
        con.close()
        self.assertEqual(sorted(bound & set(shipped)), [])
        # A bound record merged into another substance (PSI-2C-T-4 → 2C-T-4) has no
        # row of its own to look for; the gate report is where its refusal shows,
        # and it refuses nothing the book states as a dose.
        report = json.loads(dose_gates.REPORT_PATH.with_suffix(".json").read_text())
        refused = [h for h in report if h["rule"].startswith("Shulgin no-activity bound")]
        self.assertTrue(refused)
        for hit in refused:
            text = hit["detail"].removeprefix("DOSAGE: “").removesuffix("”")
            self.assertEqual("bound", dose_gates.shulgin_dosage_verdict(text), hit)


@unittest.skipUnless(DB_PATH.exists(), "piru-substances.sqlite not built")
class BuiltDatabase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.db = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    def test_no_ladder_is_left_with_only_its_ends_by_an_unread_tier(self):
        """A ladder of a threshold or a heavy mark alone ships only when the source
        itself stated nothing else; one whose middle tiers could not be read is
        the parse failure showing through."""
        unread = {
            (d["source"], d["substance"], d["route"])
            for d in json.loads(UPSTREAM_DROPS.read_text())
            if d["field"] in ("light", "common", "strong")
        }
        degenerate = self.db.execute(
            "SELECT src.slug, s.canonical_name, d.route FROM dose_ranges d"
            "  JOIN substances s ON s.id = d.substance_id JOIN sources src ON src.id = d.source_id"
            " WHERE COALESCE(d.light_lower, d.light_upper, d.common_lower, d.common_upper,"
            "                d.strong_lower, d.strong_upper) IS NULL"
        ).fetchall()
        self.assertEqual(sorted(set(degenerate) & unread), [])

    def test_no_shipped_cell_carries_a_foreign_script(self):
        cells = [
            f"{c['table']}.{c['column']} rowid {c['rowid']}"
            for c in dose_gates.foreign_cells(self.db.cursor())
        ]
        self.assertEqual(cells, [])

    def test_every_drop_is_reported_with_its_value(self):
        drops = json.loads(UPSTREAM_DROPS.read_text())
        for d in drops:
            self.assertTrue(d["source"] and d["field"] and d["reason"], d)
            self.assertTrue(str(d["raw"]).strip(), d)


if __name__ == "__main__":
    unittest.main(verbosity=2)
