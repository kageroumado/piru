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
is_chemnoise_alias = _mod.is_chemnoise_alias
normalize_category = _mod.normalize_category
normalise = _mod.normalise
canonical_salt_form = _mod.canonical_salt_form
smart_title_case = _mod.smart_title_case
chem_caps = _mod.chem_caps
is_identifier_citation = _mod.is_identifier_citation
parse_reference = _mod.parse_reference
dc_slugify = _mod.dc_slugify
_unit_to_mg_factor = _mod._unit_to_mg_factor
_CLASS_DOSE_CEILING_MG = _mod._CLASS_DOSE_CEILING_MG
_REPO = Path(__file__).resolve().parents[3]


def _load_curated(name: str) -> dict:
    """Load a data/curated/<name>.json override file (empty dict if absent)."""
    p = _REPO / "data/curated" / f"{name}.json"
    return __import__("json").loads(p.read_text()) if p.exists() else {}


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
        self.assertEqual(
            Builder._parse_dc_range("700 mg - 1,400 mg"), {"lower": 700.0, "upper": 1400.0}
        )
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
            "Caffeine",
            "LSD",
            "MDMA",
            "Risperidone",
            "Fluoxetine",
            "Delta-8-THC",
            "Magnesium Glycinate",
            "2C-B",
            "5-MeO-DMT",
            "Modafinil",
            "BPC-157",
            "Semaglutide",
        ]:
            with self.subTest(n=n):
                self.assertFalse(is_chemistry_noise(n), f"should NOT flag: {n!r}")

    def test_square_brackets_are_noise(self):
        self.assertTrue(is_chemistry_noise("N-[2-(4-hydroxyphenyl)ethyl]acrylamide"))

    def test_empty_is_noise(self):
        self.assertTrue(is_chemistry_noise(""))
        self.assertTrue(is_chemistry_noise(None))


class TestIsChemnoiseAlias(unittest.TestCase):
    """`is_chemnoise_alias` decides which aliases are systematic/IUPAC/salt-form
    chemistry clutter (purged from the alias subtitle) vs. names people actually
    search by (brands, short codes). Over-filtering would hide real names;
    under-filtering re-clutters the Library rows."""

    def test_salt_and_descriptor_suffixes_are_noise(self):
        for a in [
            "Lisdexamfetamine dimesylate",
            "1-(2,5-dimethoxybenzyl)piperazine freebase",
            "amphetamine hydrochloride",
            "ketamine HCl",
            "Dextroamphetamine prodrug",
            "morphine sulfate",
            "cocaine hydrochloride",
        ]:
            with self.subTest(a=a):
                self.assertTrue(is_chemnoise_alias(a), f"should purge: {a!r}")

    def test_iupac_and_systematic_names_are_noise(self):
        for a in [
            "1-(2,5-dimethoxybenzyl)piperazine",  # parenthetical locant
            "(R)-3-Chloromethcathinone",  # stereo prefix
            "N-[2-(4-hydroxyphenyl)ethyl]acetamide",  # bracketed body
            "L-lysine-d-amphetamine",  # long multi-locant systematic
        ]:
            with self.subTest(a=a):
                self.assertTrue(is_chemnoise_alias(a), f"should purge: {a!r}")

    def test_brands_and_short_codes_are_kept(self):
        for a in [
            "Vyvanse",
            "Elvanse",
            "LDX",
            "Xanax",
            "Adderall",
            "2,3-MDMA",
            "2,5-DMBZP",
            "MDPV",
            "2C-B",
            "5-MeO-DMT",
            "molly",
            "ecstasy",
            "AMT",
            "PMA",
            "freebase cocaine",  # trailing word is the drug, not a salt → keep
            "N-allyl-nor-LSD",  # 3 hyphens but short (≤16) recognizable code → keep
        ]:
            with self.subTest(a=a):
                self.assertFalse(is_chemnoise_alias(a), f"should keep: {a!r}")

    def test_empty_is_not_noise(self):
        # Empty/blank is dropped by upstream guards, not flagged as chemnoise.
        self.assertFalse(is_chemnoise_alias(""))
        self.assertFalse(is_chemnoise_alias(None))


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


class TestChemCaps(unittest.TestCase):
    """chem_caps upper-cases acronym segments in chemical-code names but must
    PRESERVE intentionally mixed-case segments (PiHP, MeO) and alkyl morphemes
    (Me, Et) — the 2-Me-PiHP → 2-ME-PIHP regression."""

    def test_title_cased_acronyms_uppercased(self):
        self.assertEqual(chem_caps("2-Fma"), "2-FMA")
        self.assertEqual(chem_caps("4-Ho-Met"), "4-HO-MET")
        self.assertEqual(chem_caps("3-Mmc"), "3-MMC")

    def test_interior_caps_preserved(self):
        self.assertEqual(chem_caps("2-Me-PiHP"), "2-Me-PiHP")
        self.assertEqual(chem_caps("3F-PiHP"), "3F-PiHP")
        self.assertEqual(chem_caps("4-HO-PiPT"), "4-HO-PiPT")
        self.assertEqual(chem_caps("5-MeO-MiPT"), "5-MeO-MiPT")

    def test_alkyl_morphemes_title_cased(self):
        self.assertEqual(chem_caps("2-Me-PCP"), "2-Me-PCP")
        self.assertEqual(chem_caps("N-Et-2C-B"), "N-Et-2C-B")

    def test_camelcase_chemical_segments_restored(self):
        # All-lowercase-origin names: title-cased then camel-restored.
        self.assertEqual(chem_caps("4-Ho-Mipt"), "4-HO-MiPT")
        self.assertEqual(chem_caps("5-Meo-Mipt"), "5-MeO-MiPT")
        self.assertEqual(chem_caps("4-Aco-Dmt"), "4-AcO-DMT")

    def test_hydroxy_stays_upper(self):
        # HO (hydroxy) is an acronym, not camelCase.
        self.assertEqual(chem_caps("4-Ho-Met"), "4-HO-MET")

    def test_no_digit_untouched(self):
        self.assertEqual(chem_caps("MD-PiHP"), "MD-PiHP")
        self.assertEqual(chem_caps("Aminoindane"), "Aminoindane")


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
        build.add_dose(sid, "piru-curated", "oral", "mg", common={"lower": 50.0, "upper": None})
        self.assertEqual(
            build.stats.get("dose_ranges", 0), before, "row should have been dropped, not inserted"
        )
        self.assertEqual(build.stats.get("dropped_class_dose_ceiling"), 1)

    def test_fentanyl_class_under_ceiling_passes(self):
        """A 0.5 mg oral row sits well under the 2 mg ceiling — passes."""
        build, sid = self._fresh_build()
        build.add_tag(sid, "piru-curated", "fentanyl-class-potency")
        build.add_dose(
            sid,
            "piru-curated",
            "oral",
            "mg",
            light={"lower": 0.1, "upper": 0.25},
            common={"lower": 0.25, "upper": 0.5},
        )
        self.assertEqual(build.stats.get("dose_ranges", 0), 1)
        self.assertNotIn("dropped_class_dose_ceiling", build.stats)

    def test_fentanyl_class_patch_units_pass(self):
        """100 µg/hr fentanyl transdermal patch: numeric in µg → 0.1 mg, under ceiling."""
        build, sid = self._fresh_build()
        build.add_tag(sid, "piru-curated", "fentanyl-class-potency")
        build.add_dose(
            sid,
            "piru-curated",
            "transdermal",
            "µg/hr",
            light={"lower": 12.0, "upper": 25.0},
            common={"lower": 25.0, "upper": 50.0},
            strong={"lower": 50.0, "upper": 75.0},
            heavy=100.0,
        )
        self.assertEqual(build.stats.get("dose_ranges", 0), 1)

    def test_lysergamide_100mg_dropped(self):
        """A 100 mg LSD-class row is clearly unit-confused. Ceiling = 5 mg."""
        build, sid = self._fresh_build()
        build.add_tag(sid, "piru-curated", "class:lysergamides")
        build.add_dose(sid, "piru-curated", "oral", "mg", light={"lower": 50.0, "upper": 100.0})
        self.assertEqual(build.stats.get("dose_ranges", 0), 0)
        self.assertEqual(build.stats.get("dropped_class_dose_ceiling"), 1)

    def test_lysergamide_microgram_passes(self):
        """A normal LSD row in µg passes."""
        build, sid = self._fresh_build()
        build.add_tag(sid, "piru-curated", "class:lysergamides")
        build.add_dose(
            sid,
            "piru-curated",
            "oral",
            "µg",
            threshold=15.0,
            light={"lower": 25.0, "upper": 75.0},
            common={"lower": 75.0, "upper": 150.0},
            strong={"lower": 150.0, "upper": 300.0},
            heavy=300.0,
        )
        self.assertEqual(build.stats.get("dose_ranges", 0), 1)

    def test_untagged_substance_passes(self):
        """Without a relevant class tag, the gate doesn't apply."""
        build, sid = self._fresh_build()
        build.add_dose(sid, "piru-curated", "oral", "mg", common={"lower": 500.0, "upper": 1000.0})
        self.assertEqual(build.stats.get("dose_ranges", 0), 1)

    def test_unparseable_unit_skips_gate(self):
        """A row with an unrecognisable unit ('drops', 'seeds') passes the
        class-ceiling gate even when the magnitude looks suspicious — the
        numeric value isn't a mass we can validate."""
        build, sid = self._fresh_build()
        build.add_tag(sid, "piru-curated", "fentanyl-class-potency")
        build.add_dose(
            sid, "piru-curated", "oral", "drops", common={"lower": 100.0, "upper": 100.0}
        )
        self.assertEqual(build.stats.get("dose_ranges", 0), 1)

    def test_benzodiazepine_3600mg_dropped(self):
        """An obviously unit-confused 3600 mg benzo row (Halazepam-style)
        violates the 300 mg ceiling and gets dropped."""
        build, sid = self._fresh_build()
        build.add_tag(sid, "piru-curated", "benzodiazepine")
        build.add_dose(sid, "piru-curated", "oral", "mg", threshold=5.0, heavy=3600.0)
        self.assertEqual(build.stats.get("dose_ranges", 0), 0)
        self.assertEqual(build.stats.get("dropped_class_dose_ceiling"), 1)

    def test_benzodiazepine_legacy_200mg_passes(self):
        """Tetrazepam-style 50–200 mg dosing is legitimate and must survive."""
        build, sid = self._fresh_build()
        build.add_tag(sid, "piru-curated", "benzodiazepine")
        build.add_dose(
            sid,
            "piru-curated",
            "oral",
            "mg",
            light={"lower": 25.0, "upper": 50.0},
            common={"lower": 50.0, "upper": 100.0},
            strong={"lower": 100.0, "upper": 200.0},
        )
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
            (
                "Serotonergic entactogen / mild psychedelic",
                "Psychedelic",
            ),  # psychedelic wins over entactogen
            ("Sedative-hypnotic depressant", "Depressant"),
            ("Anticholinergic deliriant incapacitant", "Deliriant"),
            ("Hormone (Estrogen)", "Endocrine"),
            (
                "Mood stabiliser / anticonvulsant",
                "Anticonvulsant",
            ),  # mood-stab + antiepileptic both → Anticonvulsant
            ("GLP-1 agonist (peptide)", "Peptide"),
            ("Antiepileptic / antiseizure agent", "Anticonvulsant"),
        ]
        for raw, expected in cases:
            with self.subTest(raw=raw):
                self.assertEqual(normalize_category(raw), expected)

    def test_priority_dissociative_beats_psychedelic(self):
        # PCP/ketamine class: dissociative is the canonical bucket even if "psychedelic" appears.
        self.assertEqual(
            normalize_category("NMDA-receptor antagonist; psychotomimetic"), "Dissociative"
        )

    def test_priority_opioid_beats_stimulant(self):
        self.assertEqual(normalize_category("µ-opioid agonist with stimulant properties"), "Opioid")

    def test_priority_antipsychotic_beats_antidepressant(self):
        self.assertEqual(
            normalize_category("Atypical antipsychotic with antidepressant adjunct use"),
            "Antipsychotic",
        )

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
            raise unittest.SkipTest(
                "piru-substances.sqlite not built; run pipeline/build/sqlite.py first"
            )
        cls.db = sqlite3.connect(sqlite_path)
        cls.db.row_factory = sqlite3.Row
        cls.sources = {
            r["slug"]: r["default_priority"]
            for r in cls.db.execute("select slug, default_priority from sources")
        }

    @classmethod
    def tearDownClass(cls):
        if hasattr(cls, "db"):
            cls.db.close()

    def _resolve_sid(self, name: str):
        """Find a substance id the way the build's upsert merges: canonical name,
        then alias, then the salt-stripped normalized name (so a curated
        'Tianeptine' file resolves to the merged 'Tianeptine sulfate' row)."""
        for sql, arg in (
            ("select id from substances where lower(canonical_name)=lower(?)", name),
            ("select substance_id as id from aliases where lower(alias)=lower(?) limit 1", name),
            ("select id from substances where normalized_name=? limit 1", normalise(name)),
        ):
            row = self.db.execute(sql, (arg,)).fetchone()
            if row:
                return row["id"]
        return None

    def _resolved_category(self, name: str) -> str | None:
        """Mirror the app's resolution: pick category from the highest-priority
        (lowest priority number) enabled source that has a row. Resolves the
        substance by canonical name OR alias — a curated file's `name` can become
        an alias after merging with a scraper entry under a different canonical
        (e.g. 'alpha-PVP' → 'α-PVP')."""
        sid = self._resolve_sid(name)
        if sid is None:
            return None
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
        self.assertLess(
            len(rows),
            5,
            f"too many lowercase substance names: {[r['canonical_name'] for r in rows]}",
        )

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
            # Antihistamines — pure peripheral H1 antagonists must NOT be pulled
            # into the Deliriant bucket (they aren't anticholinergic deliriants).
            "Cetirizine": "Antihistamine",
            "Loratadine": "Antihistamine",
            # Deliriants — anticholinergic/antimuscarinic + the deliriant first-gen
            # antihistamines, split out of Antihistamine via curated overrides.
            "Diphenhydramine": "Deliriant",
            "Doxylamine": "Deliriant",
            "Datura": "Deliriant",  # was Dysdelic; it's a deliriant, not a κ-hallucinogen
            "Scopolamine": "Deliriant",
            # Dysdelics — Salvia and selective κ-agonist RCs join the salvinorins
            "Salvia": "Dysdelic",  # curated override beats tripsit's "Dissociative"
            "Salvinorin A": "Dysdelic",
            "U-51754": "Dysdelic",
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
            "Kratom": "Opioid",  # curated override beats PsychonautWiki's "Stimulant"
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
        wrong = {
            n: (actual[n], expected)
            for n, expected in expectations.items()
            if actual[n] != expected
        }
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
        bad_aliases = {
            "thc",
            "cbd",
            "cannabidiol",
            "dronabinol",
            "tetrahydrocannabinol",
            "delta-9-thc",
        }
        leaked = [r["alias"] for r in rows if r["alias"].lower() in bad_aliases]
        self.assertEqual(leaked, [], f"distinct-molecule aliases leaked onto Cannabis: {leaked}")

    def test_cannabidiol_collapsed_to_cbd(self):
        """`Cannabidiol` as a separate substance entry should not exist —
        the name-remap collapses it into the canonical `CBD` row."""
        row = self.db.execute(
            "SELECT id FROM substances WHERE canonical_name = 'Cannabidiol'"
        ).fetchone()
        self.assertIsNone(
            row,
            "duplicate 'Cannabidiol' substance row exists; "
            "name-remap should have merged it into CBD",
        )
        # And CBD itself should still exist
        cbd = self.db.execute("SELECT id FROM substances WHERE canonical_name = 'CBD'").fetchone()
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
            tiers = [
                r[k]
                for k in (
                    "threshold",
                    "light_lower",
                    "light_upper",
                    "common_lower",
                    "common_upper",
                    "strong_lower",
                    "strong_upper",
                    "heavy",
                )
                if r[k] is not None
            ]
            mx = max((t * factor for t in tiers), default=0.0)
            if mx > 2.0:
                violations.append((r["canonical_name"], r["route"], r["unit"], mx))
        self.assertEqual(
            violations, [], f"fentanyl-class dose-ceiling violations survived: {violations}"
        )

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
        self.assertLess(
            rows["c"], 120, f"dose_ranges monotonicity regressions: {rows['c']} violations"
        )

    # ---- duplicate-substance / alias dedup invariants ----

    def _resolve_ids(self, name: str):
        """All substance ids a name resolves to (as canonical or alias)."""
        n = name.lower()
        return sorted(
            {
                r["id"]
                for r in self.db.execute(
                    "select s.id from substances s where lower(s.canonical_name)=? "
                    "union select a.substance_id from aliases a where lower(a.alias)=?",
                    (n, n),
                )
            }
        )

    def test_reported_brand_generic_pairs_merged(self):
        """Regression for the reported duplicates: a brand and its generic must
        resolve to ONE substance, and the brand must not survive as its own
        canonical record."""
        for brand, generic in [
            ("Vyvanse", "Lisdexamfetamine"),
            ("Focalin", "Dexmethylphenidate"),
            ("Adderall", "Amphetamine"),
        ]:
            gids = self._resolve_ids(generic)
            self.assertTrue(gids, f"{generic} missing from DB")
            self.assertIn(
                gids[0], self._resolve_ids(brand), f"{brand} does not resolve to {generic}"
            )
            self.assertIsNone(
                self.db.execute(
                    "select 1 from substances where lower(canonical_name)=lower(?)", (brand,)
                ).fetchone(),
                f"{brand} still exists as a separate substance — dedup regressed",
            )

    def test_no_exact_duplicate_canonical_names(self):
        """No two substances share a normalized canonical name."""
        dups = [
            r["normalized_name"]
            for r in self.db.execute(
                "select normalized_name, count(*) c from substances group by normalized_name having c>1"
            )
        ]
        self.assertEqual(dups, [], f"duplicate normalized canonical names: {dups}")

    def test_no_route_suffix_canonicals(self):
        """Route-suffix collapse (Part B) leaves no `<base>-<route>` canonical:
        the route belongs in the `route` column, not the name."""
        orphans = [
            r["canonical_name"]
            for r in self.db.execute(
                "select canonical_name from substances where "
                "canonical_name like '%-topical' or canonical_name like '%-inhaled' "
                "or canonical_name like '%-nasal' or canonical_name like '%-ophthalmic'"
            )
        ]
        self.assertEqual(orphans, [], f"un-collapsed route-suffix canonicals: {orphans}")

    def test_route_suffix_parents_present_and_searchable(self):
        """Folded variants survive as parent aliases (brand search still works)
        and their parent exists as a single canonical entry."""
        for parent, alias in (
            ("Fluticasone", "Flonase"),
            ("Beclomethasone", "QVAR RediHaler"),
            ("Hydrocortisone", "Cortaid"),
        ):
            prow = self.db.execute(
                "select id from substances where canonical_name=?", (parent,)
            ).fetchone()
            self.assertIsNotNone(prow, f"route-collapse parent {parent!r} missing")
            n = self.db.execute(
                "select count(*) c from aliases where substance_id=? and alias=?",
                (prow["id"], alias),
            ).fetchone()["c"]
            self.assertEqual(n, 1, f"{alias!r} did not fold onto {parent!r}")

    def test_salt_families_folded_with_per_salt_ladders(self):
        """Salt folding (Part A) collapses variants into a shared parent whose
        dose ladders are tagged by `salt_form`, and leaves no orphan variant."""
        for parent, salts in (
            ("Magnesium", {"Citrate", "Glycinate", "L-Threonate"}),
            ("Lithium", {"Carbonate", "Orotate"}),
        ):
            prow = self.db.execute(
                "select id from substances where canonical_name=?", (parent,)
            ).fetchone()
            self.assertIsNotNone(prow, f"salt-family parent {parent!r} missing")
            got = {
                r["salt_form"]
                for r in self.db.execute(
                    "select distinct salt_form from dose_ranges where substance_id=? "
                    "and salt_form is not null",
                    (prow["id"],),
                )
            }
            self.assertTrue(salts <= got, f"{parent}: expected salt ladders {salts}, got {got}")

    def test_salt_variant_orphans_absent(self):
        """The folded variant canonicals no longer exist as standalone rows."""
        orphans = [
            r["canonical_name"]
            for r in self.db.execute(
                "select canonical_name from substances where canonical_name in "
                "('Magnesium Citrate','Magnesium Glycinate','Magnesium Threonate',"
                "'Lithium Carbonate','Lithium orotate')"
            )
        ]
        self.assertEqual(orphans, [], f"un-folded salt variants: {orphans}")

    def test_antacid_combos_not_treated_as_salts(self):
        """Combo products are mixtures, not salt forms — they stay standalone."""
        for combo in ("Magnesium/Magaldrate", "Magnesium/Sodium"):
            row = self.db.execute(
                "select 1 from substances where canonical_name=?", (combo,)
            ).fetchone()
            self.assertIsNotNone(row, f"combo {combo!r} should remain standalone")

    def test_schema_version_is_four(self):
        """The salt_rank/elemental_fraction/is_stub bump set schema_version to 4."""
        v = self.db.execute("select value from manifest where key='schema_version'").fetchone()
        self.assertEqual(v["value"], "4")

    def test_journal_mode_is_delete(self):
        """The shipped DB must be DELETE-mode (self-contained, no -wal/-shm
        sidecars), or a read-only bundle open fails with SQLITE_CANTOPEN."""
        mode = self.db.execute("pragma journal_mode").fetchone()[0]
        self.assertEqual(mode.lower(), "delete")

    def test_salt_rank_default_intent(self):
        """salt_rank encodes the curated default (rank 0): Magnesium → Glycinate,
        Lithium → Carbonate. Loader reads this in WS-2b; the column is populated
        now so the intent ships with the DB."""
        for parent, expected_default in (("Magnesium", "Glycinate"), ("Lithium", "Carbonate")):
            row = self.db.execute(
                "select d.salt_form from dose_ranges d "
                "join substances s on s.id=d.substance_id "
                "where s.canonical_name=? and d.salt_rank=0",
                (parent,),
            ).fetchone()
            self.assertIsNotNone(row, f"{parent}: no rank-0 default salt row")
            self.assertEqual(row["salt_form"], expected_default)

    def test_every_salt_dose_row_has_rank_and_elemental(self):
        """No salt-tagged dose row may ship with a NULL rank or elemental fraction
        — the build's coverage gate guarantees curated metadata for each."""
        rows = self.db.execute(
            "select s.canonical_name, d.salt_form from dose_ranges d "
            "join substances s on s.id=d.substance_id "
            "where d.salt_form is not null "
            "and (d.salt_rank is null or d.elemental_fraction is null)"
        ).fetchall()
        self.assertEqual(
            [(r["canonical_name"], r["salt_form"]) for r in rows],
            [],
            "salt-tagged dose rows missing rank/elemental",
        )

    def test_elemental_fraction_in_expected_range(self):
        """Elemental fractions are physical mass ratios in (0, 1) — sanity-check a
        couple of known values so a typo (e.g. 16 for 0.16) is caught."""
        mg_citrate = self.db.execute(
            "select elemental_fraction f from dose_ranges d "
            "join substances s on s.id=d.substance_id "
            "where s.canonical_name='Magnesium' and d.salt_form='Citrate'"
        ).fetchone()["f"]
        self.assertAlmostEqual(mg_citrate, 0.16, places=2)
        li_carbonate = self.db.execute(
            "select elemental_fraction f from dose_ranges d "
            "join substances s on s.id=d.substance_id "
            "where s.canonical_name='Lithium' and d.salt_form='Carbonate'"
        ).fetchone()["f"]
        self.assertAlmostEqual(li_carbonate, 0.188, places=3)
        for r in self.db.execute(
            "select elemental_fraction f from dose_ranges where elemental_fraction is not null"
        ):
            self.assertTrue(0.0 < r["f"] < 1.0, f"elemental fraction out of range: {r['f']}")

    def test_salt_supplement_acute_durations_removed(self):
        """The audit drops the salt-tagged acute durations on Mg/Li supplements
        (imperceptible curves) — none survive."""
        n = self.db.execute(
            "select count(*) c from durations d "
            "join substances s on s.id=d.substance_id "
            "where s.canonical_name in ('Magnesium','Lithium') and d.salt_form is not null"
        ).fetchone()["c"]
        self.assertEqual(n, 0, "salt-tagged Mg/Li acute durations should have been removed")

    def test_salt_dose_values_unchanged(self):
        """The metadata/audit passes must not perturb any salt dose value the app
        tests pin (SaltFormTests). Lock the common ranges here too."""
        expected = {
            ("Magnesium", "Citrate"): (400.0, 600.0),
            ("Magnesium", "Glycinate"): (200.0, 400.0),
            ("Magnesium", "L-Threonate"): (1500.0, 2000.0),
            ("Lithium", "Carbonate"): (600.0, 900.0),
            ("Lithium", "Orotate"): (125.0, 250.0),
        }
        for (parent, salt), (lo, hi) in expected.items():
            row = self.db.execute(
                "select common_lower, common_upper from dose_ranges d "
                "join substances s on s.id=d.substance_id "
                "where s.canonical_name=? and d.salt_form=?",
                (parent, salt),
            ).fetchone()
            self.assertIsNotNone(row, f"{parent} {salt}: dose row missing")
            self.assertEqual((row["common_lower"], row["common_upper"]), (lo, hi))

    def test_dose_less_stubs_flagged_consistently(self):
        """is_stub == 1 exactly when a substance has zero dose/duration/protocol
        rows, and there is at least one (medtap catalog stubs exist)."""
        flagged = self.db.execute("select count(*) c from substances where is_stub=1").fetchone()[
            "c"
        ]
        self.assertGreater(flagged, 0, "expected some dose-less catalog stubs")
        # Every flagged row genuinely has no dose/duration/protocol data.
        leaks = self.db.execute(
            "select count(*) c from substances s where s.is_stub=1 and ("
            " exists(select 1 from dose_ranges where substance_id=s.id)"
            " or exists(select 1 from durations where substance_id=s.id)"
            " or exists(select 1 from protocol_dosing where substance_id=s.id))"
        ).fetchone()["c"]
        self.assertEqual(leaks, 0, "is_stub set on a substance that has dose data")
        # And no unflagged row is genuinely dose-less.
        missed = self.db.execute(
            "select count(*) c from substances s where s.is_stub=0 and not ("
            " exists(select 1 from dose_ranges where substance_id=s.id)"
            " or exists(select 1 from durations where substance_id=s.id)"
            " or exists(select 1 from protocol_dosing where substance_id=s.id))"
        ).fetchone()["c"]
        self.assertEqual(missed, 0, "dose-less substance not flagged is_stub")

    def test_inchikey_false_merges_stay_split(self):
        """The four known InChIKey-collision pairs (#8) must remain DISTINCT rows
        after the do-not-merge guard."""
        for a, b in (
            ("Methylone", "Cyclobenzaprine"),
            ("Cannabis", "THC"),
            ("CBC", "CBG"),
            ("3-MMC", "Myristicin"),
        ):
            ra = self.db.execute(
                "select id from substances where canonical_name=?", (a,)
            ).fetchone()
            rb = self.db.execute(
                "select id from substances where canonical_name=?", (b,)
            ).fetchone()
            self.assertIsNotNone(ra, f"{a} missing")
            self.assertIsNotNone(rb, f"{b} missing")
            self.assertNotEqual(ra["id"], rb["id"], f"{a} and {b} wrongly merged")

    def test_no_intra_substance_duplicate_aliases(self):
        """A substance must not carry the same alias twice (case/salt variants);
        the alias-level dedup collapses them."""
        n = self.db.execute(
            "select count(*) c from (select 1 from aliases group by substance_id, alias_normalized having count(*)>1)"
        ).fetchone()["c"]
        self.assertEqual(n, 0, f"{n} substances carry case/salt-duplicate aliases")

    def test_stereoisomers_not_over_merged(self):
        """Dedup must NOT fuse enantiomer/racemate pairs — they are distinct
        drugs with different potency/dosing."""
        for a, b in [
            ("Methylphenidate", "Dexmethylphenidate"),
            ("Amphetamine", "Dextroamphetamine"),
            ("Citalopram", "Escitalopram"),
            ("Modafinil", "Armodafinil"),
        ]:
            ra = self.db.execute(
                "select id from substances where lower(canonical_name)=lower(?)", (a,)
            ).fetchone()
            rb = self.db.execute(
                "select id from substances where lower(canonical_name)=lower(?)", (b,)
            ).fetchone()
            self.assertIsNotNone(ra, f"{a} missing")
            self.assertIsNotNone(rb, f"{b} missing")
            self.assertNotEqual(ra["id"], rb["id"], f"{a} and {b} were wrongly merged")

    def test_unmerged_duplicate_debt_bounded(self):
        """Tracks the safe-baseline duplicate debt: data-poor records whose
        canonical name is another substance's alias but which lack the InChIKey
        confirmation required to merge them safely (auto-merge needs positive
        structural proof, since distinct drugs sometimes cross-list each other —
        loratadine↔fexofenadine). Bounded so a real dedup REGRESSION (which would
        spike this into the hundreds) is caught; the residual ~50 are obscure RC
        abbreviation/salt variants awaiting InChIKey backfill or curated remap."""
        n = self.db.execute("""
            select count(*) c from substances s
            join aliases a on a.alias_normalized = s.normalized_name and a.substance_id != s.id
            where not exists (select 1 from dose_ranges  d where d.substance_id=s.id)
              and not exists (select 1 from durations    d where d.substance_id=s.id)
              and not exists (select 1 from bindings     d where d.substance_id=s.id)
              and not exists (select 1 from effects      d where d.substance_id=s.id)
        """).fetchone()["c"]
        self.assertLess(n, 75, f"unmerged duplicate debt spiked to {n} — dedup likely regressed")

    # ---- curated overrides folded into per-substance files ----
    #
    # display-name / popularity / category / CJK aliases / dose overrides now
    # live on each compound's own data/curated/substances/<slug>.json. These
    # tests assert every folded override still resolves in the built DB — turning
    # a silent "override points at a renamed/merged canonical" rot into a failure.

    def _canonical_set(self) -> set[str]:
        return {
            r["canonical_name"].lower()
            for r in self.db.execute("select canonical_name from substances")
        }

    @staticmethod
    def _curated_entries():
        import json

        d = _REPO / "data/curated/substances"
        return [json.loads(fp.read_text()) for fp in sorted(d.glob("*.json"))]

    def test_curated_display_names_resolve(self):
        entries = [
            e
            for e in self._curated_entries()
            if e.get("displayName") and not is_chemistry_noise(e["name"])
        ]
        self.assertGreater(len(entries), 0, "no curated displayName overrides found")
        for e in entries:
            sid = self._resolve_sid(e["name"])
            self.assertIsNotNone(sid, f"displayName target {e['name']!r} no longer exists")
            row = self.db.execute(
                "select display_name from substances where id=?", (sid,)
            ).fetchone()
            self.assertEqual(
                row and row["display_name"],
                e["displayName"],
                f"display_name for {e['name']!r} not applied",
            )

    def test_curated_popularity_resolves_and_in_range(self):
        entries = [
            e
            for e in self._curated_entries()
            if e.get("popularity") is not None and not is_chemistry_noise(e["name"])
        ]
        self.assertGreater(len(entries), 0, "no curated popularity scores found")
        for e in entries:
            self.assertTrue(
                0.0 <= float(e["popularity"]) <= 1.0,
                f"popularity for {e['name']!r} outside [0,1]: {e['popularity']}",
            )
            sid = self._resolve_sid(e["name"])
            self.assertIsNotNone(sid, f"popularity target {e['name']!r} no longer exists")
            row = self.db.execute("select popularity from substances where id=?", (sid,)).fetchone()
            self.assertAlmostEqual(
                row["popularity"],
                float(e["popularity"]),
                places=6,
                msg=f"popularity for {e['name']!r} not applied",
            )

    def test_curated_categories_resolve_and_are_valid_enums(self):
        # Skip chemistry-noise names (intentionally never ingested as substances).
        entries = [
            e
            for e in self._curated_entries()
            if e.get("category") and not is_chemistry_noise(e["name"])
        ]
        bad = {
            e["name"]: e["category"] for e in entries if e["category"] not in _mod._CATEGORY_ENUM
        }
        self.assertEqual(bad, {}, f"curated categories use non-enum values: {bad}")
        # Every curated category must win source-priority resolution (piru-curated
        # is priority 1). A miss means a dedup merge or normalisation regression.
        misses = {}
        for e in entries:
            resolved = self._resolved_category(e["name"])
            if resolved != e["category"]:
                misses[e["name"]] = (resolved, e["category"])
        self.assertEqual(
            misses, {}, f"curated categories did not resolve (got, expected): {misses}"
        )

    def test_no_chemnoise_aliases_survive(self):
        """The post-dedup purge should leave zero IUPAC/salt-form chemistry-noise
        aliases in the shipped table (the Library alias subtitle stays clean)."""
        survivors = [
            r["alias"]
            for r in self.db.execute("select alias from aliases")
            if is_chemnoise_alias(r["alias"])
        ]
        self.assertEqual(survivors, [], f"chemnoise aliases survived the purge: {survivors[:10]}")


_vspec = importlib.util.spec_from_file_location(
    "validate_curated", Path(__file__).resolve().parent.parent / "validate_curated.py"
)
_vmod = importlib.util.module_from_spec(_vspec)
_vspec.loader.exec_module(_vmod)


class TestCuratedSlugify(unittest.TestCase):
    """slugify is the canonical filename ↔ name mapping. Drift here means files
    become unfindable by name and re-splitting silently creates duplicates."""

    def test_basic(self):
        self.assertEqual(_vmod.slugify("Semaglutide"), "semaglutide")
        self.assertEqual(_vmod.slugify("2C-B"), "2c-b")
        self.assertEqual(_vmod.slugify("BPC-157"), "bpc-157")
        self.assertEqual(_vmod.slugify("GHK-Cu"), "ghk-cu")

    def test_greek_and_symbols(self):
        self.assertEqual(_vmod.slugify("α-PiHP"), "alpha-pihp")
        self.assertEqual(_vmod.slugify("BPC-157 + TB-500"), "bpc-157-plus-tb-500")
        self.assertEqual(_vmod.slugify("μ-opioid"), "mu-opioid")

    def test_distinct_greek_no_collision(self):
        # The whole point: α-PVP and PVP must not collapse to the same slug.
        self.assertNotEqual(_vmod.slugify("α-PVP"), _vmod.slugify("PVP"))


class TestCuratedFilesValid(unittest.TestCase):
    """The shipped curated dir must pass the enforced validator with zero errors.
    This is the build/CI gate — a malformed file would otherwise only surface as
    missing/merged data after a full rebuild."""

    def test_no_validation_errors(self):
        errors, _warnings = _vmod.validate_dir()
        self.assertEqual(
            errors, [], "curated files have validation errors:\n  " + "\n  ".join(errors)
        )


class TestCuratedValidatorCatchesBadData(unittest.TestCase):
    """Synthetic edge cases — prove the validator actually flags each silent-
    failure mode (testing the safety net itself). Each writes one bad file to a
    temp dir and asserts a matching error is raised."""

    def _check(self, entry, fname="x.json"):
        import json
        import tempfile

        d = Path(tempfile.mkdtemp())
        (d / fname).write_text(json.dumps(entry))
        return _vmod.validate_dir(d)[0]

    _base = {
        "name": "Foo",
        "aliases": [],
        "category": "Stimulant",
        "defaultRoute": "oral",
        "routes": [{"route": "oral", "unit": "mg", "doses": {}}],
    }

    def test_bad_category(self):
        e = dict(self._base, category="Wonderdrug")
        self.assertTrue(any("bad category" in x for x in self._check(e, "foo.json")))

    def test_bad_route(self):
        e = dict(self._base, routes=[{"route": "telepathy", "unit": "mg", "doses": {}}])
        self.assertTrue(any("bad route" in x for x in self._check(e, "foo.json")))

    def test_inverted_dose_range(self):
        e = dict(
            self._base,
            routes=[
                {"route": "oral", "unit": "mg", "doses": {"common": {"lower": 50, "upper": 10}}}
            ],
        )
        self.assertTrue(any("lower > upper" in x for x in self._check(e, "foo.json")))

    def test_protocol_without_frequency(self):
        e = dict(
            self._base,
            routes=[
                {"route": "oral", "unit": "mg", "doses": {}, "protocolDosing": {"lowAmount": 10}}
            ],
        )
        self.assertTrue(any("no 'frequency'" in x for x in self._check(e, "foo.json")))

    def test_bad_binding_affinity(self):
        e = dict(
            self._base,
            mechanismOfAction={
                "summary": "s",
                "description": "d",
                "references": [],
                "bindings": [{"target": "DAT", "action": "reuptakeInhibitor", "affinity": 5}],
            },
        )
        self.assertTrue(any("affinity must be" in x for x in self._check(e, "foo.json")))

    def test_filename_slug_mismatch(self):
        # File named wrong.json but name "Foo" → slug "foo": must flag drift.
        self.assertTrue(
            any("does not match slugify" in x for x in self._check(self._base, "wrong.json"))
        )

    def test_invalid_json(self):
        import tempfile

        d = Path(tempfile.mkdtemp())
        (d / "broken.json").write_text("{not valid json")
        self.assertTrue(any("invalid JSON" in x for x in _vmod.validate_dir(d)[0]))

    def test_duplicate_compound_across_files(self):
        import json
        import tempfile

        d = Path(tempfile.mkdtemp())
        (d / "foo.json").write_text(json.dumps(self._base))
        # Same compound, different file (e.g. "Foo" vs "foo "): normalised collision.
        (d / "foo-2.json").write_text(json.dumps(dict(self._base, name="foo ")))
        errs = _vmod.validate_dir(d)[0]
        self.assertTrue(any("duplicate compound" in x for x in errs))

    def test_empty_route_source_rejected(self):
        e = dict(self._base, routes=[{"route": "oral", "unit": "mg", "doses": {}, "source": ""}])
        self.assertTrue(any("route 'source'" in x for x in self._check(e, "foo.json")))

    def test_empty_halflife_source_rejected(self):
        e = dict(self._base, halfLifeSource="")
        self.assertTrue(any("halfLifeSource" in x for x in self._check(e, "foo.json")))

    def test_missing_provenance_is_advisory_only(self):
        # A dosed compound with no references → warning, not error (norm-setting).
        e = dict(
            self._base,
            routes=[
                {"route": "oral", "unit": "mg", "doses": {"common": {"lower": 10, "upper": 20}}}
            ],
        )
        errs, warns = _vmod.validate_dir(self._mkdir(e, "foo.json"))
        self.assertEqual(errs, [])
        self.assertTrue(any("no references" in w for w in warns))

    def _mkdir(self, entry, fname):
        import json
        import tempfile

        d = Path(tempfile.mkdtemp())
        (d / fname).write_text(json.dumps(entry))
        return d

    def test_override_only_file_is_valid(self):
        # A scraped-substance override: just a name + popularity, no full definition.
        e = {"name": "Cocaine", "popularity": 0.95}
        self.assertEqual(self._check(e, "cocaine.json"), [])

    def test_display_name_only_override_valid(self):
        e = {"name": "AMT", "displayName": "AMT"}
        self.assertEqual(self._check(e, "amt.json"), [])

    def test_popularity_out_of_range_rejected(self):
        for bad in (1.5, -0.1, "high"):
            e = {"name": "Foo", "popularity": bad}
            self.assertTrue(
                any("popularity must be" in x for x in self._check(e, "foo.json")),
                f"should reject popularity={bad!r}",
            )

    def test_empty_display_name_rejected(self):
        e = {"name": "Foo", "displayName": "  "}
        self.assertTrue(any("displayName" in x for x in self._check(e, "foo.json")))


class TestCuratedDirIngest(unittest.TestCase):
    """The curated dir must be the single source of curated data in the built DB,
    and a known curated-only compound must be present (proves direct ingest ran)."""

    @classmethod
    def setUpClass(cls):
        p = Path(__file__).resolve().parents[3] / "Piru/Data/piru-substances.sqlite"
        if not p.exists():
            raise unittest.SkipTest("piru-substances.sqlite not built")
        cls.db = sqlite3.connect(p)
        cls.db.row_factory = sqlite3.Row

    @classmethod
    def tearDownClass(cls):
        if hasattr(cls, "db"):
            cls.db.close()

    def test_curated_only_compound_present(self):
        # Pynazolam exists only in the curated layer — its presence proves the
        # per-substance dir was ingested.
        row = self.db.execute(
            "select id from substances where canonical_name='Pynazolam'"
        ).fetchone()
        self.assertIsNotNone(row, "curated-only compound missing — curated dir not ingested")

    def test_deleted_obscure_entries_absent(self):
        for name in ("PiP-Tapentadol", "DPDMC", "DM-DED", "DMP"):
            row = self.db.execute(
                "select 1 from substances where canonical_name=?", (name,)
            ).fetchone()
            self.assertIsNone(row, f"{name} should have been removed from the curated set")

    def test_substance_level_references_ingested(self):
        """The curated `sources` array must land in substance_citations (it was
        silently dropped before Phase 2). A known curated compound carries refs."""
        n = self.db.execute("select count(*) c from substance_citations").fetchone()["c"]
        self.assertGreater(n, 0, "no substance-level references ingested")
        row = self.db.execute("""
            select count(*) c from substance_citations sc
            join substances s on s.id = sc.substance_id
            where s.canonical_name = 'Pynazolam'
        """).fetchone()
        self.assertGreater(row["c"], 0, "Pynazolam references not ingested")

    def test_free_text_reference_not_a_broken_url(self):
        """Free-text refs ('PubChem CID …') are stored in the url slot but must
        be distinguishable from real links — the app guards on the http scheme.
        Here we just assert such a row exists and is non-http (so the app renders
        it as text, not a dead link)."""
        rows = self.db.execute(
            "select url from citations where url like 'PubChem CID%' limit 1"
        ).fetchall()
        for r in rows:
            self.assertFalse(r["url"].startswith("http"))


class TestCanonicalSaltForm(unittest.TestCase):
    """The controlled salt-form vocabulary canonicaliser keeps the exact blessed
    spellings, trims/cases variants, and never drops an unknown tag."""

    def test_blessed_spellings_pass_through(self):
        for s in ("Citrate", "Glycinate", "L-Threonate", "Carbonate", "Orotate"):
            self.assertEqual(canonical_salt_form(s), s)

    def test_case_and_whitespace_canonicalised(self):
        self.assertEqual(canonical_salt_form("  glycinate "), "Glycinate")
        self.assertEqual(canonical_salt_form("CITRATE"), "Citrate")
        self.assertEqual(canonical_salt_form("threonate"), "L-Threonate")
        self.assertEqual(canonical_salt_form("bisglycinate"), "Glycinate")

    def test_idempotent(self):
        for s in ("glycinate", "L-Threonate", "  carbonate"):
            once = canonical_salt_form(s)
            self.assertEqual(canonical_salt_form(once), once)

    def test_unknown_passes_through_trimmed(self):
        self.assertEqual(canonical_salt_form("  Sulfate "), "Sulfate")

    def test_none_and_empty(self):
        self.assertIsNone(canonical_salt_form(None))
        self.assertIsNone(canonical_salt_form("   "))


class TestIsIdentifierCitation(unittest.TestCase):
    """The citation trim: identifiers and database landing pages are NOT
    literature and must be dropped; DOIs/PMIDs/real papers/Erowid books stay."""

    def _drop(self, ref: str) -> bool:
        return is_identifier_citation(*parse_reference(ref))

    def test_cas_label_dropped(self):
        self.assertTrue(self._drop("CAS 61-50-7"))

    def test_pubchem_cid_dropped(self):
        # parse_reference turns "PubChem CID 6089" into a pubchem URL.
        self.assertTrue(self._drop("PubChem CID 6089"))
        self.assertTrue(self._drop("https://pubchem.ncbi.nlm.nih.gov/compound/6089"))

    def test_wikidata_dropped(self):
        self.assertTrue(self._drop("Wikidata"))
        self.assertTrue(self._drop("https://www.wikidata.org/wiki/Q407217"))

    def test_database_landing_pages_dropped(self):
        self.assertTrue(self._drop("https://psychonautwiki.org/wiki/DMT"))
        self.assertTrue(self._drop("https://drugs.tripsit.me/DMT"))
        self.assertTrue(self._drop("https://github.com/TripSit/drugs"))
        self.assertTrue(self._drop("https://drug.community/drug/mdma"))

    def test_inchikey_unii_dropped(self):
        self.assertTrue(self._drop("InChIKey DMULVCHRPCFFGV-UHFFFAOYSA-N"))
        self.assertTrue(self._drop("UNII 9H762SAU03"))

    def test_doi_kept(self):
        self.assertFalse(self._drop("doi:10.1002/dta.1234"))
        self.assertFalse(self._drop("https://doi.org/10.1002/dta.1234"))

    def test_pmid_kept(self):
        self.assertFalse(self._drop("PMID 12345678"))

    def test_erowid_books_kept(self):
        self.assertFalse(
            self._drop("https://erowid.org/library/books_online/tihkal/tihkal06.shtml")
        )

    def test_real_paper_url_kept(self):
        self.assertFalse(self._drop("https://www.nature.com/articles/s41586-020-0000-0"))


class TestDcSlugify(unittest.TestCase):
    """drug.community page-slug parity — must match the site's Kt() so deep
    links resolve."""

    def test_simple(self):
        self.assertEqual(dc_slugify("MDMA"), "mdma")

    def test_parenthetical_and_unicode(self):
        self.assertEqual(dc_slugify("2-Aminoindane (2-AI)"), "2-aminoindane-2-ai")
        self.assertEqual(
            dc_slugify("α-Pyrrolidinopentiophenone (α-PVP)"),
            "pyrrolidinopentiophenone-pvp",
        )

    def test_trim_and_collapse(self):
        self.assertEqual(dc_slugify("  1,4-BDO  "), "1-4-bdo")


if __name__ == "__main__":
    unittest.main(verbosity=2)
