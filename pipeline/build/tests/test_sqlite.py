"""Regression tests for drug.community dose-string parser in pipeline/build/sqlite.py.

Covers the three bug classes fixed in the same file:
  1. Comma thousand-separators ("1,000 mg" → 1000.0, not 1.0)
  2. Space / non-breaking-space thousand-separators ("1 200 µg" → 1200.0)
  3. Inline unit mismatch in a range ("1.0–1.5 mg" with row_unit="µg" → 1000–1500)

Run from the repo root:
    python3 pipeline/build/tests/test_sqlite.py
"""

import importlib.util
import sqlite3
import unittest
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    "bsd", Path(__file__).resolve().parent.parent / "sqlite.py"
)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
Builder = _mod.Build  # The class is named Build, not Builder
is_chemistry_noise = _mod.is_chemistry_noise
normalize_category = _mod.normalize_category
smart_title_case = _mod.smart_title_case
_unit_to_mg_factor = _mod._unit_to_mg_factor
_CLASS_DOSE_CEILING_MG = _mod._CLASS_DOSE_CEILING_MG


class TestDcClean(unittest.TestCase):
    """_dc_clean normalises thousand-separators before further parsing."""

    def test_comma_separator(self):
        self.assertEqual(Builder._dc_clean("1,000 mg"), "1000 mg")

    def test_regular_space_separator(self):
        self.assertEqual(Builder._dc_clean("1 200 µg"), "1200 µg")

    def test_nbsp_separator(self):
        self.assertEqual(Builder._dc_clean("1\xa0500 µg"), "1500 µg")

    def test_plain_value_unchanged(self):
        self.assertEqual(Builder._dc_clean("500 mg"), "500 mg")


class TestParseDcScalar(unittest.TestCase):
    """_parse_dc_scalar extracts a single numeric value with unit conversion."""

    def test_simple(self):
        self.assertAlmostEqual(Builder._parse_dc_scalar("500 mg", "mg"), 500.0)

    def test_comma_thousand_separator(self):
        self.assertAlmostEqual(Builder._parse_dc_scalar("1,000 mg", "mg"), 1000.0)

    def test_comma_thousand_with_plus(self):
        self.assertAlmostEqual(Builder._parse_dc_scalar("2,000+ mg", "mg"), 2000.0)

    def test_regular_space_separator(self):
        self.assertAlmostEqual(Builder._parse_dc_scalar("1 200 µg", "µg"), 1200.0)

    def test_nbsp_separator(self):
        self.assertAlmostEqual(Builder._parse_dc_scalar("1\xa0500 µg", "µg"), 1500.0)

    def test_none_input(self):
        self.assertIsNone(Builder._parse_dc_scalar(None, "mg"))

    def test_em_dash_no_digits(self):
        self.assertIsNone(Builder._parse_dc_scalar("—", "mg"))

    def test_empty_string(self):
        self.assertIsNone(Builder._parse_dc_scalar("", "mg"))


class TestParseDcRange(unittest.TestCase):
    """_parse_dc_range extracts lower/upper bounds with unit conversion."""

    def test_simple_hyphen(self):
        result = Builder._parse_dc_range("5-10 mg", "mg")
        self.assertIsNotNone(result)
        self.assertAlmostEqual(result["lower"], 5.0)
        self.assertAlmostEqual(result["upper"], 10.0)

    def test_en_dash_with_comma_separator(self):
        result = Builder._parse_dc_range("500–1,000 mg", "mg")
        self.assertIsNotNone(result)
        self.assertAlmostEqual(result["lower"], 500.0)
        self.assertAlmostEqual(result["upper"], 1000.0)

    def test_space_separated_bounds_with_nbsp(self):
        result = Builder._parse_dc_range("800 – 1 200 µg", "µg")
        self.assertIsNotNone(result)
        self.assertAlmostEqual(result["lower"], 800.0)
        self.assertAlmostEqual(result["upper"], 1200.0)

    def test_inline_unit_between_bound_and_dash_strips_correctly(self):
        """drug.community writes "5 mg - 15 mg" with the unit repeated
        between the lower bound and the dash. Without stripping the inline
        unit ~100 ranges were silently returned as None."""
        self.assertEqual(Builder._parse_dc_range("5 mg - 15 mg"), {"lower": 5.0, "upper": 15.0})
        self.assertEqual(Builder._parse_dc_range("700 mg - 1,400 mg"), {"lower": 700.0, "upper": 1400.0})
        # 0.5–1 g with default row_unit=mg should convert to 500–1000 mg.
        self.assertEqual(Builder._parse_dc_range("0.5 g - 1 g"), {"lower": 500.0, "upper": 1000.0})

    def test_inline_unit_conversion_mg_in_ug_row(self):
        """Inline mg unit in a µg row should be converted: 1.0–1.5 mg = 1000–1500 µg."""
        result = Builder._parse_dc_range("1.0–1.5 mg", "µg")
        self.assertIsNotNone(result)
        self.assertAlmostEqual(result["lower"], 1000.0)
        self.assertAlmostEqual(result["upper"], 1500.0)

    def test_none_input(self):
        self.assertIsNone(Builder._parse_dc_range(None, "mg"))

    def test_no_range_returns_none(self):
        self.assertIsNone(Builder._parse_dc_range("500 mg", "mg"))


class TestDcUnitFactor(unittest.TestCase):
    """_dc_unit_factor returns a scaling factor when inline unit != row unit."""

    def test_same_unit_returns_one(self):
        self.assertAlmostEqual(Builder._dc_unit_factor("5 mg", "mg"), 1.0)

    def test_mg_inline_ug_row_returns_1000(self):
        """Inline mg in a µg row → factor 1000 (multiply by 1000 to get µg)."""
        self.assertAlmostEqual(Builder._dc_unit_factor("1.0 mg", "µg"), 1000.0)

    def test_ug_inline_mg_row_returns_0_001(self):
        """Inline µg in a mg row → factor 0.001."""
        self.assertAlmostEqual(Builder._dc_unit_factor("500 µg", "mg"), 0.001)

    def test_no_unit_inline_returns_one(self):
        """No recognisable unit in the string → assume same as row unit."""
        self.assertAlmostEqual(Builder._dc_unit_factor("500", "mg"), 1.0)


class TestIsChemistryNoise(unittest.TestCase):
    """The Library tab should not surface IUPAC stereo-variants or square-bracket
    chemistry artefacts that arrived via Wikidata's SPARQL net."""

    def test_paren_stereo_prefixes_are_noise(self):
        for n in [
            "(+/-)-noradrenaline",
            "(+)-cathinone",
            "(-)-octopamine",
            "(R)-3-Chloromethcathinone",
            "(S)-3,4-Dimethoxyamphetamine",
            "(E)-N-feruloyltyramine",
            "(E,E)-bastadin 19",
            "(±)-adrenaline",
            "(−)-cathinone",  # U+2212 minus
            "(2E)-3-(4-Hydroxy-3-methoxyphenyl)-N-...",
            "(2R)-1-(3-Chlorophenyl)-2-(methylamino)-1-propanone",
        ]:
            with self.subTest(n=n):
                self.assertTrue(is_chemistry_noise(n), f"should flag: {n!r}")

    def test_real_substances_not_noise(self):
        for n in [
            "Caffeine", "LSD", "MDMA", "Risperidone", "Fluoxetine",
            "Delta-8-THC", "Magnesium Glycinate", "2C-B", "5-MeO-DMT",
            "Modafinil", "BPC-157", "Semaglutide",
        ]:
            with self.subTest(n=n):
                self.assertFalse(is_chemistry_noise(n), f"should NOT flag: {n!r}")

    def test_square_brackets_are_noise(self):
        self.assertTrue(is_chemistry_noise("N-[2-(4-hydroxyphenyl)ethyl]acrylamide"))

    def test_empty_is_noise(self):
        self.assertTrue(is_chemistry_noise(""))
        self.assertTrue(is_chemistry_noise(None))


class TestSmartTitleCase(unittest.TestCase):
    """drug.community ships many substance names lowercase; the build pass
    promotes them to title-case while preserving known acronyms."""

    def test_simple_words_capitalised(self):
        self.assertEqual(smart_title_case("indopan"), "Indopan")
        self.assertEqual(smart_title_case("dextroamphetamine"), "Dextroamphetamine")
        self.assertEqual(smart_title_case("bufotenine"), "Bufotenine")

    def test_acronyms_uppercased(self):
        self.assertEqual(smart_title_case("lsd"), "LSD")
        self.assertEqual(smart_title_case("mdma"), "MDMA")
        self.assertEqual(smart_title_case("dxm"), "DXM")
        self.assertEqual(smart_title_case("thc"), "THC")
        self.assertEqual(smart_title_case("cbd"), "CBD")

    def test_already_mixed_case_passes_through(self):
        # Source-provided casing is trusted.
        self.assertEqual(smart_title_case("Caffeine"), "Caffeine")
        self.assertEqual(smart_title_case("5-MeO-DMT"), "5-MeO-DMT")
        self.assertEqual(smart_title_case("BPC-157"), "BPC-157")

    def test_empty(self):
        self.assertEqual(smart_title_case(""), "")
        self.assertEqual(smart_title_case(None), None)


class TestUnitToMgFactor(unittest.TestCase):
    """`_unit_to_mg_factor` is the mass-conversion lookup the class-dose
    ceiling consults. Unparseable units must return None so the gate
    skips them rather than misclassifying."""

    def test_milligrams_pass_through(self):
        self.assertEqual(_unit_to_mg_factor("mg"), 1.0)
        self.assertEqual(_unit_to_mg_factor("mgs"), 1.0)
        self.assertEqual(_unit_to_mg_factor(None), 1.0)
        self.assertEqual(_unit_to_mg_factor(""), 1.0)

    def test_micrograms_variants(self):
        for u in ("µg", "ug", "mcg", "μg", "micrograms"):
            with self.subTest(unit=u):
                self.assertEqual(_unit_to_mg_factor(u), 0.001)

    def test_grams_variants(self):
        for u in ("g", "gram", "grams"):
            with self.subTest(unit=u):
                self.assertEqual(_unit_to_mg_factor(u), 1000.0)

    def test_patch_per_hour_units(self):
        """`µg/hr` patch numerics ARE microgram quantities — treat as µg."""
        for u in ("µg/hr", "ug/hr", "mcg/hr", "mcg/hour", "mcg/hr (patch)"):
            with self.subTest(unit=u):
                self.assertEqual(_unit_to_mg_factor(u), 0.001)

    def test_per_kg_and_per_day_return_none(self):
        """mg/kg and mg/day numerics aren't direct masses — skip the check."""
        self.assertIsNone(_unit_to_mg_factor("mg/kg"))
        self.assertIsNone(_unit_to_mg_factor("µg/kg"))
        self.assertIsNone(_unit_to_mg_factor("mg/day"))
        self.assertIsNone(_unit_to_mg_factor("mg/24h"))

    def test_non_mass_units_return_none(self):
        for u in ("seeds", "drops", "IU", "ml", "sprays", "%", "x", "units"):
            with self.subTest(unit=u):
                self.assertIsNone(_unit_to_mg_factor(u))


class TestClassDoseCeilingGate(unittest.TestCase):
    """End-to-end: `add_dose` drops a row when any tier value (converted to
    mg) exceeds the strictest applicable class ceiling."""

    def _fresh_build(self):
        db = sqlite3.connect(":memory:")
        db.executescript(_mod.SCHEMA_SQL)
        build = Builder(db)
        build.seed_sources()
        sid = build.upsert_substance("Testfentanyl", source_slug="piru-curated")
        return build, sid

    def test_fentanyl_class_50mg_oral_dropped(self):
        """Valerylfentanyl-style bare 50 mg oral row gets rejected."""
        build, sid = self._fresh_build()
        build.add_tag(sid, "piru-curated", "fentanyl-class-potency")
        before = build.stats.get("dose_ranges", 0)
        build.add_dose(sid, "piru-curated", "oral", "mg",
                       common={"lower": 50.0, "upper": None})
        self.assertEqual(build.stats.get("dose_ranges", 0), before,
                         "row should have been dropped, not inserted")
        self.assertEqual(build.stats.get("dropped_class_dose_ceiling"), 1)

    def test_fentanyl_class_under_ceiling_passes(self):
        """A 0.5 mg oral row sits well under the 2 mg ceiling — passes."""
        build, sid = self._fresh_build()
        build.add_tag(sid, "piru-curated", "fentanyl-class-potency")
        build.add_dose(sid, "piru-curated", "oral", "mg",
                       light={"lower": 0.1, "upper": 0.25},
                       common={"lower": 0.25, "upper": 0.5})
        self.assertEqual(build.stats.get("dose_ranges", 0), 1)
        self.assertNotIn("dropped_class_dose_ceiling", build.stats)

    def test_fentanyl_class_patch_units_pass(self):
        """100 µg/hr fentanyl transdermal patch: numeric in µg → 0.1 mg, under ceiling."""
        build, sid = self._fresh_build()
        build.add_tag(sid, "piru-curated", "fentanyl-class-potency")
        build.add_dose(sid, "piru-curated", "transdermal", "µg/hr",
                       light={"lower": 12.0, "upper": 25.0},
                       common={"lower": 25.0, "upper": 50.0},
                       strong={"lower": 50.0, "upper": 75.0},
                       heavy=100.0)
        self.assertEqual(build.stats.get("dose_ranges", 0), 1)

    def test_lysergamide_100mg_dropped(self):
        """A 100 mg LSD-class row is clearly unit-confused. Ceiling = 5 mg."""
        build, sid = self._fresh_build()
        build.add_tag(sid, "piru-curated", "class:lysergamides")
        build.add_dose(sid, "piru-curated", "oral", "mg",
                       light={"lower": 50.0, "upper": 100.0})
        self.assertEqual(build.stats.get("dose_ranges", 0), 0)
        self.assertEqual(build.stats.get("dropped_class_dose_ceiling"), 1)

    def test_lysergamide_microgram_passes(self):
        """A normal LSD row in µg passes."""
        build, sid = self._fresh_build()
        build.add_tag(sid, "piru-curated", "class:lysergamides")
        build.add_dose(sid, "piru-curated", "oral", "µg",
                       threshold=15.0,
                       light={"lower": 25.0, "upper": 75.0},
                       common={"lower": 75.0, "upper": 150.0},
                       strong={"lower": 150.0, "upper": 300.0},
                       heavy=300.0)
        self.assertEqual(build.stats.get("dose_ranges", 0), 1)

    def test_untagged_substance_passes(self):
        """Without a relevant class tag, the gate doesn't apply."""
        build, sid = self._fresh_build()
        build.add_dose(sid, "piru-curated", "oral", "mg",
                       common={"lower": 500.0, "upper": 1000.0})
        self.assertEqual(build.stats.get("dose_ranges", 0), 1)

    def test_unparseable_unit_skips_gate(self):
        """A row with an unrecognisable unit ('drops', 'seeds') passes the
        class-ceiling gate even when the magnitude looks suspicious — the
        numeric value isn't a mass we can validate."""
        build, sid = self._fresh_build()
        build.add_tag(sid, "piru-curated", "fentanyl-class-potency")
        build.add_dose(sid, "piru-curated", "oral", "drops",
                       common={"lower": 100.0, "upper": 100.0})
        self.assertEqual(build.stats.get("dose_ranges", 0), 1)

    def test_benzodiazepine_3600mg_dropped(self):
        """An obviously unit-confused 3600 mg benzo row (Halazepam-style)
        violates the 300 mg ceiling and gets dropped."""
        build, sid = self._fresh_build()
        build.add_tag(sid, "piru-curated", "benzodiazepine")
        build.add_dose(sid, "piru-curated", "oral", "mg",
                       threshold=5.0,
                       heavy=3600.0)
        self.assertEqual(build.stats.get("dose_ranges", 0), 0)
        self.assertEqual(build.stats.get("dropped_class_dose_ceiling"), 1)

    def test_benzodiazepine_legacy_200mg_passes(self):
        """Tetrazepam-style 50–200 mg dosing is legitimate and must survive."""
        build, sid = self._fresh_build()
        build.add_tag(sid, "piru-curated", "benzodiazepine")
        build.add_dose(sid, "piru-curated", "oral", "mg",
                       light={"lower": 25.0, "upper": 50.0},
                       common={"lower": 50.0, "upper": 100.0},
                       strong={"lower": 100.0, "upper": 200.0})
        self.assertEqual(build.stats.get("dose_ranges", 0), 1)


class TestNormalizeCategory(unittest.TestCase):
    """drug.community / enrichment supply long descriptive category strings
    that must collapse to one of the 25 SubstanceCategory enum values."""

    def test_canonical_passthrough(self):
        for cat in ["Stimulant", "Psychedelic", "Antidepressant", "Opioid", "Other"]:
            self.assertEqual(normalize_category(cat), cat)

    def test_long_descriptions_normalise(self):
        cases = [
            ("Antidepressant (NaSSA: noradrenergic and specific serotonergic)", "Antidepressant"),
            ("Antidepressant (irreversible, non-selective MAOI)", "Antidepressant"),
            ("µ-opioid receptor agonist (opioid analgesic)", "Opioid"),
            ("Atypical μ-opioid receptor agonist (G-protein-biased)", "Opioid"),
            ("Cannabinoid (full CB1/CB2 agonist)", "Cannabinoid"),
            ("Cannabinoid receptor agonist (synthetic cannabinoid)", "Cannabinoid"),
            ("Dissociative NMDA-receptor antagonist", "Dissociative"),
            ("Non-competitive NMDA receptor antagonist", "Dissociative"),
            ("Atypical psychedelic / sedative tryptamine", "Psychedelic"),
            ("5-HT2A psychedelic phenethylamine; mild stimulant", "Psychedelic"),
            ("Stimulant; serotonergic neurotoxin", "Stimulant"),
            ("Serotonergic entactogen / mild psychedelic", "Psychedelic"),  # psychedelic wins over entactogen
            ("Sedative-hypnotic depressant", "Depressant"),
            ("Anticholinergic deliriant incapacitant", "Antihistamine"),
            ("Hormone (Estrogen)", "Endocrine"),
            ("Mood stabiliser / anticonvulsant", "Anticonvulsant"),  # mood-stab + antiepileptic both → Anticonvulsant
            ("GLP-1 agonist (peptide)", "Peptide"),
            ("Antiepileptic / antiseizure agent", "Anticonvulsant"),
        ]
        for raw, expected in cases:
            with self.subTest(raw=raw):
                self.assertEqual(normalize_category(raw), expected)

    def test_priority_dissociative_beats_psychedelic(self):
        # PCP/ketamine class: dissociative is the canonical bucket even if "psychedelic" appears.
        self.assertEqual(normalize_category("NMDA-receptor antagonist; psychotomimetic"), "Dissociative")

    def test_priority_opioid_beats_stimulant(self):
        self.assertEqual(normalize_category("µ-opioid agonist with stimulant properties"), "Opioid")

    def test_priority_antipsychotic_beats_antidepressant(self):
        self.assertEqual(normalize_category("Atypical antipsychotic with antidepressant adjunct use"), "Antipsychotic")

    def test_unknown_falls_back_to_other(self):
        self.assertEqual(normalize_category("foobar"), "Other")
        self.assertEqual(normalize_category(""), "Other")
        self.assertEqual(normalize_category(None), "Other")


class TestBuiltDatabaseInvariants(unittest.TestCase):
    """End-to-end checks against the bundled `piru-substances.sqlite`. These
    verify that the build pipeline as a whole produces a database the iOS app
    can consume correctly: every category is a valid enum value, no chemistry
    noise survived, and key substances land in the categories users expect."""

    @classmethod
    def setUpClass(cls):
        sqlite_path = Path(__file__).resolve().parents[3] / "Piru/Data/piru-substances.sqlite"
        if not sqlite_path.exists():
            raise unittest.SkipTest("piru-substances.sqlite not built; run pipeline/build/sqlite.py first")
        cls.db = sqlite3.connect(sqlite_path)
        cls.db.row_factory = sqlite3.Row
        cls.sources = {r["slug"]: r["default_priority"] for r in cls.db.execute("select slug, default_priority from sources")}

    @classmethod
    def tearDownClass(cls):
        if hasattr(cls, "db"):
            cls.db.close()

    def _resolved_category(self, name: str) -> str | None:
        """Mirror the app's resolution: pick category from the highest-priority
        (lowest priority number) enabled source that has a row."""
        row = self.db.execute(
            "select id from substances where lower(canonical_name) = lower(?)", (name,)
        ).fetchone()
        if not row:
            return None
        sid = row["id"]
        cats = [
            (self.sources.get(r["slug"], 999), r["category"])
            for r in self.db.execute(
                "select src.slug, c.category from categories c "
                "join sources src on src.id=c.source_id where c.substance_id=?",
                (sid,),
            )
        ]
        if not cats:
            return None
        cats.sort()
        return cats[0][1]

    def test_every_category_row_is_canonical_enum(self):
        """No category in the table should be outside the 25-value enum."""
        canonical = _mod._CATEGORY_ENUM
        rows = self.db.execute("select distinct category from categories").fetchall()
        bad = [r["category"] for r in rows if r["category"] not in canonical]
        self.assertEqual(bad, [], f"non-canonical categories found in DB: {bad}")

    def test_no_chemistry_noise_substance_names(self):
        """The substances table should not contain IUPAC stereo-variants."""
        rows = self.db.execute("select canonical_name from substances").fetchall()
        noise = [r["canonical_name"] for r in rows if is_chemistry_noise(r["canonical_name"])]
        self.assertEqual(noise, [], f"chemistry-noise names slipped into DB: {noise[:10]}")

    def test_no_all_lowercase_substance_names(self):
        """smart_title_case should have upgraded all all-lowercase names."""
        rows = self.db.execute(
            "select canonical_name from substances "
            "where canonical_name = lower(canonical_name) "
            "and canonical_name not glob '[0-9]*' "  # exempt numeric-prefixed names like "5-meo-dmt" (becomes 5-MEO-DMT)
        ).fetchall()
        # Allow a tiny bleed; we mainly want to catch hundreds of un-cased names.
        self.assertLess(len(rows), 5, f"too many lowercase substance names: {[r['canonical_name'] for r in rows]}")

    def test_known_substance_categories(self):
        """Specific substances should land in the categories users expect after
        source-priority resolution. Catches regressions where category-mapping
        rules silently break."""
        expectations = {
            # Antipsychotics
            "Risperidone": "Antipsychotic",
            "Olanzapine": "Antipsychotic",
            "Quetiapine": "Antipsychotic",
            "Aripiprazole": "Antipsychotic",
            # Antidepressants
            "Fluoxetine": "Antidepressant",
            "Sertraline": "Antidepressant",
            "Venlafaxine": "Antidepressant",
            "Bupropion": "Antidepressant",  # piru-curated overrides tripsit's "Stimulant"
            # Antihistamines
            "Cetirizine": "Antihistamine",
            "Loratadine": "Antihistamine",
            "Diphenhydramine": "Antihistamine",
            # Cannabinoids
            "THC": "Cannabinoid",
            "CBD": "Cannabinoid",
            "Delta-8-THC": "Cannabinoid",
            # Cardiovascular
            "Propranolol": "Cardiovascular",
            # Stimulants
            "Caffeine": "Stimulant",
            # Psychedelics (reclassified from Other / Empathogen)
            "2C-B": "Psychedelic",
            # Opioids
            "Methadone": "Opioid",
            # Benzo
            "Diazepam": "Benzodiazepine",
            # Peptides (new category)
            "Semaglutide": "Peptide",
            "BPC-157": "Peptide",
            "Tirzepatide": "Peptide",
            # Anticonvulsants (new category)
            "Lithium Carbonate": "Anticonvulsant",
            "Valproate": "Anticonvulsant",
            "Lamotrigine": "Anticonvulsant",
            # Classical psychedelics that source data gets wrong or omits.
            # Psilocybin only had a wikidata category ("Other"); Psilocin and
            # Ayahuasca had wrong TripSit categories ("Empathogen").
            "Psilocybin": "Psychedelic",
            "Psilocin": "Psychedelic",
            "Ayahuasca": "Psychedelic",
        }
        actual: dict[str, str | None] = {n: self._resolved_category(n) for n in expectations}
        wrong = {n: (actual[n], expected) for n, expected in expectations.items() if actual[n] != expected}
        self.assertEqual(wrong, {}, f"categorisation mismatches (got, expected): {wrong}")

    def test_cannabis_does_not_alias_distinct_molecules(self):
        """Cannabis (the plant) should not have THC, CBD, Cannabidiol,
        Dronabinol, etc. as aliases — those are distinct substances with
        their own entries. Sources occasionally provide these as aliases
        and the ingester's blocklist should drop them on insert."""
        rows = self.db.execute("""
            SELECT a.alias FROM aliases a
            JOIN substances s ON s.id = a.substance_id
            WHERE s.canonical_name = 'Cannabis'
        """).fetchall()
        bad_aliases = {'thc', 'cbd', 'cannabidiol', 'dronabinol',
                       'tetrahydrocannabinol', 'delta-9-thc'}
        leaked = [r['alias'] for r in rows if r['alias'].lower() in bad_aliases]
        self.assertEqual(leaked, [],
                         f"distinct-molecule aliases leaked onto Cannabis: {leaked}")

    def test_cannabidiol_collapsed_to_cbd(self):
        """`Cannabidiol` as a separate substance entry should not exist —
        the name-remap collapses it into the canonical `CBD` row."""
        row = self.db.execute(
            "SELECT id FROM substances WHERE canonical_name = 'Cannabidiol'"
        ).fetchone()
        self.assertIsNone(row, "duplicate 'Cannabidiol' substance row exists; "
                               "name-remap should have merged it into CBD")
        # And CBD itself should still exist
        cbd = self.db.execute(
            "SELECT id FROM substances WHERE canonical_name = 'CBD'"
        ).fetchone()
        self.assertIsNotNone(cbd, "CBD canonical row missing after remap")

    def test_fentanyl_class_dose_ceiling_holds(self):
        """No substance tagged `fentanyl-class-potency` or `fentanyl-analog`
        should retain a dose row whose any-tier value, converted to mg, is
        above 2 mg. The ingest gate should have dropped them."""
        rows = self.db.execute("""
            select s.canonical_name, dr.unit, dr.route, dr.threshold,
                   dr.light_lower, dr.light_upper, dr.common_lower, dr.common_upper,
                   dr.strong_lower, dr.strong_upper, dr.heavy
            from dose_ranges dr
            join substances s on s.id = dr.substance_id
            where dr.substance_id in (
                select substance_id from tags
                where tag in ('fentanyl-class-potency', 'fentanyl-analog')
            )
        """).fetchall()
        violations = []
        for r in rows:
            factor = _unit_to_mg_factor(r["unit"])
            if factor is None:
                continue  # unparseable unit — gate doesn't apply
            tiers = [r[k] for k in ("threshold", "light_lower", "light_upper",
                                     "common_lower", "common_upper",
                                     "strong_lower", "strong_upper", "heavy")
                     if r[k] is not None]
            mx = max((t * factor for t in tiers), default=0.0)
            if mx > 2.0:
                violations.append((r["canonical_name"], r["route"], r["unit"], mx))
        self.assertEqual(violations, [], f"fentanyl-class dose-ceiling violations survived: {violations}")

    def test_dose_ladder_monotonicity_within_tolerance(self):
        """Most dose rows should be monotonic. Some legacy source-data noise
        is acceptable (overlapping ranges in drug.community/tripsit conventions)
        but the count should not balloon. Threshold: <120 violations across
        all sources."""
        rows = self.db.execute("""
            select count(*) c from dose_ranges
            where (threshold is not null and light_lower is not null and threshold > light_lower)
               or (light_upper is not null and common_lower is not null and light_upper > common_lower)
               or (common_upper is not null and strong_lower is not null and common_upper > strong_lower)
               or (strong_upper is not null and heavy is not null and strong_upper > heavy)
        """).fetchone()
        self.assertLess(rows["c"], 120, f"dose_ranges monotonicity regressions: {rows['c']} violations")


if __name__ == "__main__":
    unittest.main(verbosity=2)
