"""Regression tests for drug.community dose-string parser in pipeline/build/sqlite.py.

Covers the three bug classes fixed in the same file:
  1. Comma thousand-separators ("1,000 mg" → 1000.0, not 1.0)
  2. Space / non-breaking-space thousand-separators ("1 200 µg" → 1200.0)
  3. Inline unit mismatch in a range ("1.0–1.5 mg" with row_unit="µg" → 1000–1500)

Run from the repo root:
    python3 pipeline/build/tests/test_sqlite.py
"""

import importlib.util
import json
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
psid = _mod.psid
smart_title_case = _mod.smart_title_case
chem_caps = _mod.chem_caps
is_identifier_citation = _mod.is_identifier_citation
parse_reference = _mod.parse_reference
build_misconceptions_json = _mod.build_misconceptions_json
dc_slugify = _mod.dc_slugify
parse_formula = _mod.parse_formula
is_clean_desalt = _mod.is_clean_desalt
apply_pubchem_freebase = _mod.apply_pubchem_freebase
apply_pubchem_computed = _mod.apply_pubchem_computed
_parse_bioavailability = _mod._parse_bioavailability
apply_identifier_corrections = _mod.apply_identifier_corrections
apply_wikipedia_popularity = _mod.apply_wikipedia_popularity
_unit_to_mg_factor = _mod._unit_to_mg_factor
_CLASS_DOSE_CEILING_MG = _mod._CLASS_DOSE_CEILING_MG
is_dosage_form_tag = _mod.is_dosage_form_tag
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


class TestParseBioavailability(unittest.TestCase):
    """benzos-cited `x_bioavailability` strings → (route, pct, note) for pk_routes
    (Stage 1). Pct is a single value or a range midpoint; pipe-joined multi-route
    strings split; segments without a % yield no row (no fabricated number)."""

    def test_single_value(self):
        self.assertEqual(_parse_bioavailability("Oral: 84%."), [("Oral", 84.0, "Oral: 84%")])

    def test_range_midpoint(self):
        self.assertEqual(_parse_bioavailability("Oral 80-90%"), [("Oral", 85.0, "Oral 80-90%")])

    def test_pipe_joined_multi_route(self):
        out = _parse_bioavailability("Oral 85-90% | Insufflated 76-80%")
        self.assertEqual(
            out, [("Oral", 87.5, "Oral 85-90%"), ("Insufflated", 78.0, "Insufflated 76-80%")]
        )

    def test_segment_without_percent_skipped(self):
        # "Oral [variable …]" carries no number — only the % segments produce rows.
        out = _parse_bioavailability("Oral [variable - first-pass] | Intramuscular 90%")
        self.assertEqual(out, [("Intramuscular", 90.0, "Intramuscular 90%")])

    def test_first_value_when_plus_minus(self):
        self.assertEqual(
            _parse_bioavailability("Oral 70% +/- 24%."), [("Oral", 70.0, "Oral 70% +/- 24%")]
        )

    def test_empty(self):
        self.assertEqual(_parse_bioavailability(None), [])
        self.assertEqual(_parse_bioavailability(""), [])


class TestApplyPubchemComputed(unittest.TestCase):
    """`apply_pubchem_computed` sets logP/TPSA/HBA/HBD from PubChem on the trusted
    paths only: a CID that is also InChIKey-verified, or a CID-less row matched by
    InChIKey. An unverified CID (no InChIKey) is left to NPS's own value."""

    def _db(self):
        con = sqlite3.connect(":memory:")
        con.execute(
            "CREATE TABLE substances (id INTEGER PRIMARY KEY, pubchem_cid INTEGER, "
            "inchikey TEXT, logp REAL, tpsa REAL, hba INTEGER, hbd INTEGER)"
        )
        return con

    def test_verified_cid_applied(self):
        con = self._db()
        con.execute("INSERT INTO substances VALUES (1, 100, 'KEY-A', NULL, NULL, NULL, NULL)")
        apply_pubchem_computed(con, {"100": {"xlogp": 2.5, "tpsa": 30.0, "hba": 3, "hbd": 1}})
        row = con.execute("SELECT logp, tpsa, hba, hbd FROM substances WHERE id=1").fetchone()
        self.assertEqual(row, (2.5, 30.0, 3, 1))

    def test_unverified_cid_skipped(self):
        con = self._db()
        con.execute("INSERT INTO substances VALUES (1, 100, NULL, 9.9, NULL, NULL, NULL)")
        apply_pubchem_computed(con, {"100": {"xlogp": 2.5, "tpsa": 30.0}})
        self.assertEqual(
            con.execute("SELECT logp, tpsa FROM substances WHERE id=1").fetchone(), (9.9, None)
        )

    def test_inchikey_fallback_for_cidless(self):
        con = self._db()
        con.execute("INSERT INTO substances VALUES (1, NULL, 'KEY-B', NULL, NULL, NULL, NULL)")
        apply_pubchem_computed(con, {}, {"KEY-B": {"xlogp": 1.1, "tpsa": 41.9, "hba": 4, "hbd": 1}})
        self.assertEqual(
            con.execute("SELECT logp, tpsa, hba, hbd FROM substances WHERE id=1").fetchone(),
            (1.1, 41.9, 4, 1),
        )


class TestEffectVocabModule(unittest.TestCase):
    """Unit tests for the controlled effect vocabulary resolver (no DB)."""

    def test_vocab_id_for_is_deterministic_and_normalized(self):
        # Case / whitespace / trailing-period insensitive (PW whitelist already
        # normalizes, but the resolver must agree).
        self.assertEqual(_mod.vocab_id_for("Anxiety"), "anxiety")
        self.assertEqual(_mod.vocab_id_for("  anxiety. "), "anxiety")

    def test_orthography_variants_collapse_to_one_vocab(self):
        # American/British + singular/plural spellings the corpus mixes must
        # resolve to the SAME vocab_id (one translated label, unified grouping).
        self.assertEqual(
            _mod.vocab_id_for("Color enhancement"),
            _mod.vocab_id_for("Colour enhancement"),
        )
        self.assertEqual(_mod.vocab_id_for("Headache"), _mod.vocab_id_for("Headaches"))

    def test_unmatched_returns_none_for_raw_fallback(self):
        # A non-PW string resolves to None — caller keeps raw text (no fabricated
        # merge into an unrelated effect).
        self.assertIsNone(_mod.vocab_id_for("not a real effect xyzzy"))
        self.assertIsNone(_mod.vocab_id_for(""))

    def test_every_label_row_points_at_a_real_vocab_id(self):
        ids = set(_mod.EFFECT_VOCAB)
        for vid, _lang, _label, _mt in _mod.vocab_labels():
            self.assertIn(vid, ids)


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

    def test_no_cjk_iupac_names(self):
        """iupac_name is Latin-only — FreeOD's Chinese 系统名称 must be gated and
        the English systematic name supplied by PubChem (Stage-4 data audit)."""
        rows = self.db.execute(
            "select canonical_name, iupac_name from substances where iupac_name glob '*[一-鿿]*'"
        ).fetchall()
        self.assertEqual(
            rows,
            [],
            f"Chinese IUPAC names leaked into DB: {[r['canonical_name'] for r in rows][:10]}",
        )

    def test_formula_matches_molecular_weight(self):
        """A stored molecular_weight must match the mass computed from its formula
        (no salt mass on a free-base formula — amphetamine, MDMA). Tolerance 2%."""
        bad = []
        for r in self.db.execute(
            "select canonical_name, formula, molecular_weight from substances "
            "where formula is not null and molecular_weight is not null"
        ).fetchall():
            computed = _mod.formula_mass(r["formula"])
            if computed and abs(r["molecular_weight"] - computed) / computed > 0.02:
                bad.append(
                    f"{r['canonical_name']}: {r['molecular_weight']} vs {computed} ({r['formula']})"
                )
        self.assertEqual(bad, [], f"formula↔mass mismatches: {bad[:10]}")

    def test_boiling_point_above_melting_point(self):
        """A boiling point below the melting point is impossible (sublimation
        mislabelled as a BP — caffeine)."""
        rows = self.db.execute(
            "select canonical_name from substances "
            "where melting_point_c is not null and boiling_point_c is not null "
            "and boiling_point_c < melting_point_c"
        ).fetchall()
        self.assertEqual(
            rows, [], f"boiling<melting point: {[r['canonical_name'] for r in rows][:10]}"
        )

    def test_no_all_lowercase_substance_names(self):
        """smart_title_case should have upgraded all all-lowercase names."""
        rows = self.db.execute(
            "select canonical_name from substances "
            "where canonical_name = lower(canonical_name) "
            "and canonical_name glob '*[a-z]*' "  # only Latin names have case; CJK-named FreeOD entries can't be title-cased
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
        # Lithium is deliberately absent: it folds like any salt family, but as a
        # prescription drug it ships no dose ladder at all, so there are no
        # salt-tagged dose rows to find. Its folding is covered by
        # ``test_salt_variant_orphans_absent``.
        for parent, salts in (("Magnesium", {"Citrate", "Glycinate", "L-Threonate"}),):
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

    def test_schema_version_is_six(self):
        """Stage A adds the isomer facet columns, the substance_forms enumeration,
        and the facet-annotated aliases, bumping the schema version to 6."""
        v = self.db.execute("select value from manifest where key='schema_version'").fetchone()
        self.assertEqual(v["value"], "6")

    def test_physicochemical_columns_present(self):
        """Stage 0 adds the forensic chem columns (NULL until Stage 1 fills them)."""
        cols = {c["name"] for c in self.db.execute("PRAGMA table_info(substances)")}
        for col in (
            "logp",
            "logd",
            "pka",
            "tpsa",
            "hba",
            "hbd",
            "ld50_oral_mg_per_kg",
            "ld50_dermal_mg_per_kg",
            "melting_point_c",
            "boiling_point_c",
        ):
            self.assertIn(col, cols, f"substances.{col} should exist")

    def test_physicochemical_columns_populated(self):
        """Stage 1 fills the forensic chem columns from NPS-DataHub + PubChem.
        logP/TPSA/HBA/HBD come (mostly) from PubChem's computed descriptors;
        LD50/melting/boiling point come from NPS. logD/pKa have no source yet
        and stay NULL — an honest gap, not a failure."""
        counts = self.db.execute(
            "SELECT count(logp), count(tpsa), count(hba), count(hbd), "
            "count(ld50_oral_mg_per_kg), count(melting_point_c), count(boiling_point_c) "
            "FROM substances"
        ).fetchone()
        logp, tpsa, hba, hbd, ld50, mp, bp = counts
        self.assertGreater(logp, 500, "logP should be broadly populated")
        self.assertGreater(tpsa, 500, "TPSA should be broadly populated")
        self.assertGreater(hba, 500)
        self.assertGreater(hbd, 500)
        self.assertGreater(ld50, 0, "at least some rodent LD50 from NPS")
        self.assertGreater(mp, 0, "at least some melting points from NPS")
        self.assertGreater(bp, 0, "at least some boiling points from NPS")

    def test_ceiling_spec_seeds_carry_chemistry(self):
        """The spec's spot-check: codeine + lisdexamfetamine (and a few common
        recreational seeds) carry logP/TPSA — verifying the InChIKey fallback
        reaches CID-less substances like codeine, not just CID-bearing ones."""
        for name in ("Codeine", "Lisdexamfetamine", "MDMA", "Alprazolam"):
            row = self.db.execute(
                "SELECT logp, tpsa FROM substances WHERE canonical_name=?", (name,)
            ).fetchone()
            self.assertIsNotNone(row, f"{name} missing from catalog")
            self.assertIsNotNone(row["logp"], f"{name} should carry logP")
            self.assertIsNotNone(row["tpsa"], f"{name} should carry TPSA")

    def test_effect_vocab_shape_present(self):
        """Stage 0 adds the controlled-vocabulary tables; Stage 2 seeds them."""
        tables = {
            r["name"] for r in self.db.execute("select name from sqlite_master where type='table'")
        }
        self.assertIn("effect_vocab", tables)
        self.assertIn("effect_vocab_labels", tables)
        effect_cols = {c["name"] for c in self.db.execute("PRAGMA table_info(effects)")}
        self.assertIn("vocab_id", effect_cols)

    def test_effect_vocab_seeded(self):
        """Stage 2 seeds the controlled vocabulary from the PW SEI whitelist."""
        n = self.db.execute("select count(*) from effect_vocab").fetchone()[0]
        self.assertGreater(n, 200, "effect_vocab not seeded")
        # Every vocab entry carries a category from the PW grouping.
        uncategorized = self.db.execute(
            "select count(*) from effect_vocab where category is null or category=''"
        ).fetchone()[0]
        self.assertEqual(uncategorized, 0)

    def test_effect_vocab_labels_trilingual(self):
        """Each vocab_id has an en label and curated zh-Hans/zh-Hant labels;
        zh-Hant is OpenCC-derived (machine_translated=1), zh-Hans curated (0)."""
        vocab_ids = {r[0] for r in self.db.execute("select vocab_id from effect_vocab")}
        for lang in ("en", "zh-Hans", "zh-Hant"):
            covered = {
                r[0]
                for r in self.db.execute(
                    "select vocab_id from effect_vocab_labels where language=?", (lang,)
                )
            }
            self.assertEqual(vocab_ids - covered, set(), f"{lang}: vocab_ids missing a label")
        # Honesty labeling: zh-Hant flagged machine, en/zh-Hans not.
        hant_mt = self.db.execute(
            "select min(machine_translated), max(machine_translated) "
            "from effect_vocab_labels where language='zh-Hant'"
        ).fetchone()
        self.assertEqual(tuple(hant_mt), (1, 1))
        hans_mt = self.db.execute(
            "select max(machine_translated) from effect_vocab_labels where language='zh-Hans'"
        ).fetchone()[0]
        self.assertEqual(hans_mt, 0)

    def test_effects_linked_to_vocab(self):
        """The build-time matcher stamps vocab_id on (almost) every whitelisted
        effect row; the few unmatched keep raw text as the fallback (not blank)."""
        linked, total = self.db.execute("select count(vocab_id), count(*) from effects").fetchone()
        # effects.text is already PW-whitelisted, so coverage is near-total.
        self.assertGreater(linked / total, 0.98)
        # FK integrity: every non-NULL vocab_id resolves to a real vocab entry.
        orphans = self.db.execute(
            "select count(*) from effects e "
            "left join effect_vocab v on v.vocab_id=e.vocab_id "
            "where e.vocab_id is not null and v.vocab_id is null"
        ).fetchone()[0]
        self.assertEqual(orphans, 0)

    def test_english_only_substance_gets_localized_effects(self):
        """The Stage 2 payoff: a substance whose effects came from English-only
        sources still resolves a zh-Hans label for each, via vocab_id — even
        though no zh effect row was ever ingested for it."""
        row = self.db.execute(
            "select id from substances where canonical_name='Caffeine'"
        ).fetchone()
        self.assertIsNotNone(row)
        sid = row["id"]
        effects = self.db.execute(
            "select e.text, l.label zh from effects e "
            "join effect_vocab_labels l on l.vocab_id=e.vocab_id and l.language='zh-Hans' "
            "where e.substance_id=?",
            (sid,),
        ).fetchall()
        self.assertGreater(len(effects), 0, "Caffeine has no vocab-linked effects")
        for r in effects:
            self.assertTrue(r["zh"], f"no zh-Hans label for {r['text']!r}")

    def test_journal_mode_is_delete(self):
        """The shipped DB must be DELETE-mode (self-contained, no -wal/-shm
        sidecars), or a read-only bundle open fails with SQLITE_CANTOPEN."""
        mode = self.db.execute("pragma journal_mode").fetchone()[0]
        self.assertEqual(mode.lower(), "delete")

    def test_salt_rank_default_intent(self):
        """salt_rank encodes the curated default (rank 0): Magnesium → Glycinate,
        Lithium → Carbonate. Loader reads this in WS-2b; the column is populated
        now so the intent ships with the DB."""
        # Lithium dropped: no dose rows survive for it to rank (see
        # ``suppress_therapeutic_doses``).
        for parent, expected_default in (("Magnesium", "Glycinate"),):
            row = self.db.execute(
                "select d.salt_form from dose_ranges d "
                "join substances s on s.id=d.substance_id "
                "where s.canonical_name=? and d.salt_rank=0",
                (parent,),
            ).fetchone()
            self.assertIsNotNone(row, f"{parent}: no rank-0 default salt row")
            self.assertEqual(row["salt_form"], expected_default)

    def test_every_salt_dose_row_has_rank(self):
        """Every salt-tagged dose row carries a non-null salt_rank — the universal
        default-form intent that applies to any salt (mineral or drug). The
        build's coverage gate guarantees it. `elemental_fraction` is a
        mineral-only enrichment, decoupled from the salt concept: it is
        legitimately NULL for drug salts (Tianeptine sulfate, future benzofuran
        HCl/fumarate variants) and is range-checked separately where present."""
        rows = self.db.execute(
            "select s.canonical_name, d.salt_form from dose_ranges d "
            "join substances s on s.id=d.substance_id "
            "where d.salt_form is not null and d.salt_rank is null"
        ).fetchall()
        self.assertEqual(
            [(r["canonical_name"], r["salt_form"]) for r in rows],
            [],
            "salt-tagged dose rows missing rank",
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
        # Lithium carbonate used to be the second pinned value; it ships no dose
        # row now (prescription-only), so the range invariant below carries the
        # rest of the check.
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

    def test_lithium_ships_no_dose_ladder(self):
        """Lithium is prescription-only with a narrow therapeutic index; it must
        carry no dose ladder, salt-tagged or otherwise. It is the one substance
        the salt exemption used to protect, so this is the regression guard."""
        n = self.db.execute(
            "select count(*) from dose_ranges d join substances s on s.id=d.substance_id "
            "where s.canonical_name='Lithium'"
        ).fetchone()[0]
        self.assertEqual(n, 0, "Lithium must ship no dose ladder")

    def test_salt_dose_values_unchanged(self):
        """The metadata/audit passes must not perturb any salt dose value the app
        tests pin (SaltFormTests). Lock the common ranges here too."""
        expected = {
            ("Magnesium", "Citrate"): (400.0, 600.0),
            ("Magnesium", "Glycinate"): (200.0, 400.0),
            ("Magnesium", "L-Threonate"): (1500.0, 2000.0),
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

    def test_stereoisomers_folded_into_parent(self):
        """Stage A folds curated enantiomers INTO their racemic parent as the
        isomer form (inverting the old don't-merge invariant). The variant is no
        longer a standalone row; it survives as a searchable alias of the parent,
        and where it carried its own dose ladder the parent now has isomer-tagged
        dose rows (so per-enantiomer dosing is preserved, never flattened)."""
        for parent, variant, code, has_dose in [
            ("Methylphenidate", "Dexmethylphenidate", "D", True),
            ("Amphetamine", "Dextroamphetamine", "D", True),
            ("Modafinil", "Armodafinil", "R", True),
            ("Citalopram", "Escitalopram", "S", False),  # no per-enantiomer ladder
        ]:
            pr = self.db.execute(
                "select id from substances where lower(canonical_name)=lower(?)", (parent,)
            ).fetchone()
            self.assertIsNotNone(pr, f"{parent} missing")
            vr = self.db.execute(
                "select id from substances where lower(canonical_name)=lower(?)", (variant,)
            ).fetchone()
            self.assertIsNone(vr, f"{variant} should be folded into {parent}, not standalone")
            al = self.db.execute(
                "select 1 from aliases where substance_id=? and lower(alias)=lower(?)",
                (pr["id"], variant),
            ).fetchone()
            self.assertIsNotNone(al, f"{variant} should survive as an alias of {parent}")
            if has_dose:
                n = self.db.execute(
                    "select count(*) c from dose_ranges where substance_id=? and isomer=?",
                    (pr["id"], code),
                ).fetchone()["c"]
                self.assertGreater(
                    n, 0, f"{parent} should carry isomer={code} dose rows from {variant}"
                )

    def test_substance_forms_enumerate_isomers(self):
        """substance_forms enumerates one row per known (uid, stereo, salt, release)
        with a composed PSID + display title. Methylphenidate → base + Focalin's
        D-form; Ketamine → base + Esketamine (S) + Arketamine (R). The base form is
        marked default. Even dose-less folded enantiomers (Dextromethamphetamine)
        get an identity + title row so a logged form can be displayed."""
        # Keyed by the table's full PK — (stereo, salt, release) — since Stage B
        # populates release, so Methylphenidate has both a base and an XR form.
        forms = {
            (r["stereo"], r["salt"], r["release"]): dict(r)
            for r in self.db.execute(
                "SELECT f.stereo, f.salt, f.release, f.display_name, f.is_default, f.psid "
                "FROM substance_forms f JOIN substances s ON s.id=f.substance_id "
                "WHERE s.canonical_name='Methylphenidate'"
            )
        }
        self.assertEqual(forms[("0", "0", "0")]["display_name"], "Methylphenidate")
        self.assertEqual(forms[("0", "0", "0")]["is_default"], 1)
        self.assertEqual(forms[("D", "0", "0")]["display_name"], "Dexmethylphenidate")

        ket = {
            r["display_name"]
            for r in self.db.execute(
                "SELECT f.display_name FROM substance_forms f JOIN substances s "
                "ON s.id=f.substance_id WHERE s.canonical_name='Ketamine'"
            )
        }
        self.assertSetEqual(ket, {"Ketamine", "Esketamine", "Arketamine"})

        # Dose-less enantiomer still gets an identity + title (from annotated alias).
        meth = {
            r["display_name"]
            for r in self.db.execute(
                "SELECT f.display_name FROM substance_forms f JOIN substances s "
                "ON s.id=f.substance_id WHERE s.canonical_name='Methamphetamine'"
            )
        }
        self.assertIn("Dextromethamphetamine", meth)

    def test_every_substance_form_psid_is_check_valid(self):
        """Every substance_forms.psid round-trips: it parses, its check char
        verifies, and the parsed facets equal the stored codes — the guarantee that
        a facet-bearing PSID (deep link / export) fails fast if mistyped rather than
        resolving to a different valid form (closes spec Deferred #1)."""
        bad = []
        for r in self.db.execute("SELECT psid, stereo, salt, release FROM substance_forms"):
            parsed = psid.parse(r["psid"])
            if not parsed or (parsed["stereo"], parsed["salt"], parsed["release"]) != (
                r["stereo"],
                r["salt"],
                r["release"],
            ):
                bad.append(r["psid"])
        self.assertEqual(bad, [], f"{len(bad)} substance_forms PSIDs failed round-trip: {bad[:5]}")

    def test_isomer_brand_aliases_carry_facet(self):
        """The migration's name→form resolver: an enantiomer brand/name alias is
        annotated with its isomer facet on the parent, so a logged "Focalin" or
        "Spravato" recovers isomer='D'/'S' rather than resolving form-blind."""
        for alias, parent, code in [
            ("Focalin", "Methylphenidate", "D"),
            ("Spravato", "Ketamine", "S"),
            ("Armodafinil", "Modafinil", "R"),
            ("Dexmethylphenidate", "Methylphenidate", "D"),
        ]:
            r = self.db.execute(
                "SELECT s.canonical_name, a.isomer FROM aliases a "
                "JOIN substances s ON s.id=a.substance_id WHERE lower(a.alias)=lower(?)",
                (alias,),
            ).fetchone()
            self.assertIsNotNone(r, f"{alias} alias missing")
            self.assertEqual(r["canonical_name"], parent, f"{alias} resolves to wrong parent")
            self.assertEqual(r["isomer"], code, f"{alias} missing isomer facet {code}")

    def test_release_brand_aliases_carry_facet(self):
        """Stage B's name→form resolver: a release-form brand is annotated with its
        release facet on the parent, so a logged "Concerta" recovers 'XR'. Covers
        both detection routes — the token-bearing names the regex reads
        ("Adderall XR") and the tokenless brands only curation knows ("Concerta")."""
        for alias, parent, code in [
            ("Concerta", "Methylphenidate", "XR"),  # curated: no token in the name
            ("Ritalin LA", "Methylphenidate", "XR"),  # detected: trailing token
            ("Adderall XR", "Amphetamine", "XR"),
            ("Adderall IR", "Amphetamine", "IR"),
            ("Morphine Sulfate Extended-release", "Morphine", "XR"),  # detected: phrase
            ("Kapvay", "Clonidine", "XR"),
            ("Vivitrol", "Naltrexone", "DEP"),
            ("Invega Sustenna", "Paliperidone", "DEP"),
            ("Invega", "Paliperidone", "XR"),  # oral ER, NOT the depot sibling
        ]:
            r = self.db.execute(
                "SELECT s.canonical_name, a.release_form FROM aliases a "
                "JOIN substances s ON s.id=a.substance_id WHERE lower(a.alias)=lower(?)",
                (alias,),
            ).fetchone()
            self.assertIsNotNone(r, f"{alias} alias missing")
            self.assertEqual(r["canonical_name"], parent, f"{alias} resolves to wrong parent")
            self.assertEqual(r["release_form"], code, f"{alias} missing release facet {code}")

    def test_release_facet_not_claimed_for_non_release_forms(self):
        """The negative half — asserting a form the name never claimed is the way
        this feature does damage. A bare base brand is the unspecified form (not
        "IR"); a prodrug's long duration comes from metabolism, not a formulation;
        and a patch is the *route* axis, so tagging it here would conflate two
        orthogonal axes."""
        for alias in [
            "Adderall",  # base brand — the unspecified form, sibling of Adderall XR/IR
            "Ritalin",
            "Vyvanse",  # prodrug, not a release form
            "Daytrana",  # transdermal patch — route axis, not release
            "Suboxone",  # combination product
        ]:
            rows = self.db.execute(
                "SELECT a.release_form FROM aliases a WHERE lower(a.alias)=lower(?)", (alias,)
            ).fetchall()
            self.assertTrue(rows, f"{alias} alias missing")
            for r in rows:
                self.assertIsNone(r["release_form"], f"{alias} wrongly tagged {r['release_form']}")

    def test_cross_axis_alias_carries_both_facets(self):
        """Focalin XR is the D-enantiomer *and* extended-release. The isomer pass
        matches "focalin" exactly, so it never sees "focalin xr" — without the
        release-stripped fallback this alias would be tagged XR-but-racemic, which
        asserts the wrong drug. Both axes must land, and compose into one title."""
        for alias in ("Focalin XR", "Dexmethylphenidate Hydrochloride Extended-release"):
            r = self.db.execute(
                "SELECT s.canonical_name, a.isomer, a.release_form FROM aliases a "
                "JOIN substances s ON s.id=a.substance_id WHERE lower(a.alias)=lower(?)",
                (alias,),
            ).fetchone()
            self.assertIsNotNone(r, f"{alias} alias missing")
            self.assertEqual(r["canonical_name"], "Methylphenidate")
            self.assertEqual(r["isomer"], "D", f"{alias} lost its isomer facet")
            self.assertEqual(r["release_form"], "XR")

        title = self.db.execute(
            "SELECT f.display_name FROM substance_forms f JOIN substances s "
            "ON s.id=f.substance_id WHERE s.canonical_name='Methylphenidate' "
            "AND f.stereo='D' AND f.salt='0' AND f.release='XR'"
        ).fetchone()
        self.assertIsNotNone(title, "no (D, XR) form enumerated for Methylphenidate")
        self.assertEqual(title["display_name"], "Dexmethylphenidate XR")

    def test_substance_forms_enumerate_release_forms(self):
        """A release-bearing alias spawns its own identity + title row, so a logged
        brand can be titled from its resolved form. Release rows are never default —
        the unspecified form is."""
        forms = {
            (r["stereo"], r["release"]): dict(r)
            for r in self.db.execute(
                "SELECT f.stereo, f.release, f.display_name, f.is_default "
                "FROM substance_forms f JOIN substances s ON s.id=f.substance_id "
                "WHERE s.canonical_name='Methylphenidate' AND f.salt='0'"
            )
        }
        self.assertEqual(forms[("0", "XR")]["display_name"], "Methylphenidate XR")
        self.assertEqual(forms[("0", "XR")]["is_default"], 0)
        self.assertEqual(forms[("0", "0")]["is_default"], 1)
        # `titleSuffix` exists so a code that doesn't read as a suffix gets prose.
        depot = self.db.execute(
            "SELECT f.display_name FROM substance_forms f JOIN substances s "
            "ON s.id=f.substance_id WHERE s.canonical_name='Naltrexone' AND f.release='DEP'"
        ).fetchone()
        self.assertEqual(depot["display_name"], "Naltrexone Depot")

    def test_release_codes_are_psid_encodable(self):
        """Every stored release code must ride the PSID <release> field (radix-36,
        never the '0' unspecified sentinel) — otherwise a facet-bearing PSID can't
        be composed at all. Guards a new curated code from shipping un-encodable."""
        codes = {
            r["release_form"]
            for r in self.db.execute(
                "SELECT DISTINCT release_form FROM aliases WHERE release_form IS NOT NULL"
            )
        }
        self.assertTrue(codes, "no release facets annotated at all")
        for code in codes:
            self.assertRegex(code, r"^[0-9A-Z]+$", f"release code {code!r} is not radix-36")
            self.assertNotEqual(code, "0", "release code collides with the unspecified sentinel")

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

    def test_popularity_from_wikipedia_snapshot(self):
        # Popularity now comes from the reproducible Wikipedia-pageviews snapshot
        # (apply_wikipedia_popularity), superseding hand-set curated values.
        snap_path = _REPO / "data/sources/wikipedia-popularity.json"
        if not snap_path.exists():
            self.skipTest("no wikipedia-popularity snapshot")
        snap = __import__("json").loads(snap_path.read_text())
        # every popularity is in range
        for row in self.db.execute("select popularity from substances"):
            self.assertTrue(
                0.0 <= row["popularity"] <= 1.0, f"popularity out of [0,1]: {row['popularity']}"
            )
        # a mapped substance carries its snapshot score
        sid = self._resolve_sid("MDMA")
        self.assertIsNotNone(sid)
        pop = self.db.execute("select popularity from substances where id=?", (sid,)).fetchone()[
            "popularity"
        ]
        self.assertAlmostEqual(pop, float(snap["MDMA"]["score"]), places=4)

    def test_recognizable_outranks_obscure_rc(self):
        # The regression that motivated the reproducible signal: a recognizable
        # benzofuran must sort above an obscure RC, not below it alphabetically.
        def pop(name):
            sid = self._resolve_sid(name)
            if sid is None:
                return None
            return self.db.execute(
                "select popularity from substances where id=?", (sid,)
            ).fetchone()["popularity"]

        apb, obscure = pop("6-APB"), pop("2-Bromo-4,5-MDMA")
        if apb is None or obscure is None:
            self.skipTest("benchmark substances absent")
        self.assertGreater(apb, obscure, "6-APB should outrank 2-Bromo-4,5-MDMA by popularity")

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
        aliases in the shipped table (the Library alias subtitle stays clean).

        Exception: a salt-form variant name like "Tianeptine sulfate" is a real,
        searchable name when the substance genuinely ships that salt — those are
        deliberately protected, not noise. Salt and mineral are decoupled, so a
        substance carrying a `sulfate`/`hydrobromide` form keeps its qualified
        alias even though the bare suffix reads as chemnoise in isolation."""
        salt_forms: dict[str, set[str]] = {}
        for r in self.db.execute(
            "select s.canonical_name c, lower(d.salt_form) sf from dose_ranges d "
            "join substances s on s.id=d.substance_id where d.salt_form is not null"
        ):
            salt_forms.setdefault(r["c"], set()).add(r["sf"])
        survivors = []
        for r in self.db.execute(
            "select s.canonical_name c, a.alias al from aliases a "
            "join substances s on s.id=a.substance_id"
        ):
            al = r["al"]
            if not is_chemnoise_alias(al):
                continue
            if any(al.lower().rstrip().endswith(sf) for sf in salt_forms.get(r["c"], ())):
                continue  # legitimate "<substance> <salt-form>" variant name
            survivors.append(al)
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


class TestParseReferenceDOIExtraction(unittest.TestCase):
    """parse_reference must extract only the DOI token, never leak a trailing
    "(Author Year Journal)" label into the doi column — the bug that produced
    citations 1275/1289/1291 in the shipped DB (doi field containing a space
    and a parenthetical label)."""

    def test_doi_prefix_with_trailing_label_splits_doi_and_title(self):
        ref = (
            "doi:10.1016/j.phrs.2009.05.008 (Jo SH et al. — Promethazine "
            "directly blocks hERG K+ channel; Pharmacol Res 2009)"
        )
        doi, pmid, url, title = parse_reference(ref)
        self.assertEqual(doi, "10.1016/j.phrs.2009.05.008")
        self.assertIsNone(pmid)
        self.assertIsNone(url)
        self.assertEqual(
            title,
            "Jo SH et al. — Promethazine directly blocks hERG K+ channel; Pharmacol Res 2009",
        )
        self.assertNotIn(" ", doi)

    def test_bare_doi_with_trailing_label_splits_doi_and_title(self):
        ref = "10.1023/A:1015916423156 (Putcha L et al. — Pharm Res 1989)"
        doi, pmid, url, title = parse_reference(ref)
        self.assertEqual(doi, "10.1023/a:1015916423156")
        self.assertEqual(title, "Putcha L et al. — Pharm Res 1989")
        self.assertNotIn(" ", doi)
        self.assertNotIn("(", doi)

    def test_bare_doi_no_label(self):
        self.assertEqual(
            parse_reference("doi:10.1002/dta.1234"),
            ("10.1002/dta.1234", None, None, None),
        )

    def test_bare_doi_without_prefix_no_label(self):
        self.assertEqual(
            parse_reference("10.1016/s0014-2999(97)01116-3"),
            ("10.1016/s0014-2999(97)01116-3", None, None, None),
        )

    def test_doi_with_internal_parens_not_mistaken_for_a_label(self):
        # Elsevier/Wiley DOIs often contain balanced parens with no
        # whitespace before them — these must stay whole, not be truncated.
        ref = "10.1002/(sici)1099-081x(1998110)19:8<541::aid-bdd138>3.0.co;2-8"
        self.assertEqual(parse_reference(ref), (ref.lower(), None, None, None))

    def test_pmid_still_parses(self):
        self.assertEqual(parse_reference("PMID 12345678"), (None, 12345678, None, None))
        self.assertEqual(parse_reference("pmid:12345678"), (None, 12345678, None, None))


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


class TestParseFormula(unittest.TestCase):
    def test_basic(self):
        self.assertEqual(parse_formula("C12H16N2"), {"C": 12, "H": 16, "N": 2})

    def test_two_letter_and_implicit_one(self):
        self.assertEqual(parse_formula("C10H14BrNO2"), {"C": 10, "H": 14, "Br": 1, "N": 1, "O": 2})

    def test_empty(self):
        self.assertIsNone(parse_formula(None))
        self.assertIsNone(parse_formula(""))


class TestIsCleanDesalt(unittest.TestCase):
    """The free base must be the salt minus a nitrogen-free counter-ion."""

    def test_hydrochloride(self):  # DMT·HCl → DMT
        self.assertTrue(is_clean_desalt("C12H16N2", "C12H17ClN2"))

    def test_sulfate_2to1(self):  # amphetamine sulfate (2 base : 1 H2SO4)
        self.assertTrue(is_clean_desalt("C9H13N", "C18H28N2O4S"))

    def test_tartrate(self):  # LSD tartrate → LSD
        self.assertTrue(is_clean_desalt("C20H25N3O", "C24H31N3O7"))

    def test_structural_halogen_preserved(self):  # 2C-B·HCl → keeps Br, drops Cl
        self.assertTrue(is_clean_desalt("C10H14BrNO2", "C10H15BrClNO2"))

    def test_dual_chlorine(self):  # 2C-C: one ring Cl kept, salt Cl removed
        self.assertTrue(is_clean_desalt("C10H14ClNO2", "C10H15Cl2NO2"))

    def test_wrong_cid_nitrogen_loss(self):  # VIP CID → C32H44O7 (no N)
        self.assertFalse(is_clean_desalt("C32H44O7", "C147H237N43O43S"))

    def test_wrong_cid_foreign_element(self):  # methoxphenidine CID gains S, N
        self.assertFalse(is_clean_desalt("C13H11N5O4S", "C20H26ClNO"))

    def test_cation_not_desalt(self):  # synephrine(1+) gains an H, is a cation
        self.assertFalse(is_clean_desalt("C9H14NO2", "C9H13NO2"))

    def test_identical_is_not_a_change(self):
        self.assertFalse(is_clean_desalt("C10H15N", "C10H15N"))


class TestApplyPubchemFreebase(unittest.TestCase):
    def _db(self):
        con = sqlite3.connect(":memory:")
        con.execute(
            "CREATE TABLE substances(id INTEGER PRIMARY KEY, canonical_name TEXT, "
            "pubchem_cid INTEGER, formula TEXT, molecular_weight REAL, inchikey TEXT)"
        )
        con.executemany(
            "INSERT INTO substances(canonical_name, pubchem_cid, formula, molecular_weight, inchikey) VALUES (?,?,?,?,?)",
            [
                # InChIKey present → CID verified → PubChem authoritative:
                (
                    "DMT",
                    6089,
                    "C12H17ClN2",
                    224.73,
                    "DMULVCHRPCFFGV-UHFFFAOYSA-N",
                ),  # salt → free base
                (
                    "Ketamine",
                    3821,
                    "C13H16ClNO",
                    237.73,
                    "YQEZLKZALYSWHR-UHFFFAOYSA-N",
                ),  # same → untouched
                (
                    "Stale",
                    44349798,
                    "C14H21NO2S",
                    0.0,
                    "AAAAAAAAAAAAAA-UHFFFAOYSA-N",
                ),  # wrong stored → fixed
                ("Empty", 1614, None, None, "NGBBVGZWCFBOGO-UHFFFAOYSA-N"),  # null → filled
                # No InChIKey → unverifiable CID → conservative:
                ("SaltNoIK", 6090, "C12H17ClN2", 224.73, None),  # clean desalt → applied
                ("WrongNoIK", 6918155, "C147H237N43O43S", 3326.8, None),  # non-desalt → flagged
                ("EmptyNoIK", 999, None, None, None),  # null + no IK → left null
            ],
        )
        con.commit()
        return con

    def test_trusts_pubchem_when_inchikey_present(self):
        con = self._db()
        props = {
            "6089": {"formula": "C12H16N2", "molecular_weight": 188.27},
            "3821": {"formula": "C13H16ClNO", "molecular_weight": 237.73},
            "44349798": {"formula": "C14H23NO2S", "molecular_weight": 255.4},
            "1614": {"formula": "C10H13NO2", "molecular_weight": 179.22},
            "6090": {"formula": "C12H16N2", "molecular_weight": 188.27},
            "6918155": {"formula": "C32H44O7", "molecular_weight": 540.7},
            "999": {"formula": "C9H11NO2", "molecular_weight": 165.19},
        }
        stats = apply_pubchem_freebase(con, props)
        self.assertEqual(stats["trusted"], 3)  # DMT desalt, Stale fix, Empty fill
        self.assertEqual(stats["desalted"], 1)  # SaltNoIK
        self.assertEqual(len(stats["flagged"]), 1)  # WrongNoIK
        self.assertEqual(stats["unverified_no_formula"], 1)  # EmptyNoIK
        got = dict(con.execute("SELECT canonical_name, formula FROM substances").fetchall())
        self.assertEqual(got["DMT"], "C12H16N2")  # desalted (verified)
        self.assertEqual(got["Stale"], "C14H23NO2S")  # stale formula fixed (verified)
        self.assertEqual(got["Empty"], "C10H13NO2")  # filled (verified)
        self.assertEqual(got["SaltNoIK"], "C12H16N2")  # clean desalt (unverified path)
        self.assertEqual(got["WrongNoIK"], "C147H237N43O43S")  # kept (unverified non-desalt)
        self.assertIsNone(got["EmptyNoIK"])  # not filled (unverifiable)


class TestApplyWikipediaPopularity(unittest.TestCase):
    def test_sets_scores_and_leaves_unmapped(self):
        con = sqlite3.connect(":memory:")
        con.execute(
            "CREATE TABLE substances(id INTEGER PRIMARY KEY, canonical_name TEXT, popularity REAL DEFAULT 0)"
        )
        con.executemany(
            "INSERT INTO substances(canonical_name, popularity) VALUES (?,?)",
            [("MDMA", 0.5), ("6-APB", 0.0), ("ObscureRC", 0.0)],
        )
        con.commit()
        data = {"MDMA": {"score": 0.99}, "6-APB": {"score": 0.69}}  # ObscureRC absent
        n = apply_wikipedia_popularity(con, data)
        self.assertEqual(n, 2)
        got = dict(con.execute("SELECT canonical_name, popularity FROM substances").fetchall())
        self.assertAlmostEqual(got["MDMA"], 0.99)  # supersedes the old hand value
        self.assertAlmostEqual(got["6-APB"], 0.69)  # benzofuran now outranks the RC
        self.assertAlmostEqual(got["ObscureRC"], 0.0)  # unmapped stays 0


class TestDosageFormTag(unittest.TestCase):
    """is_dosage_form_tag drops FDA dosageForm strings dumped into tags while
    keeping real drug-class labels that happen to be comma-lists."""

    def test_drops_pure_form_lists(self):
        for tag in [
            "tablet",
            "capsule, tablet, solution",
            "tablet, chewable tablet, extended release tablet, capsule, solution, syrup",
            "cream, lotion, ointment",
            "injection pen, pre-filled syringe, cartridge for infusor",
            "dry powder inhaler (diskus, inhub, respiclick), metered dose inhaler (hfa)",
            "tablet, chewable tablet, orally disintegrating, capsule, solution, elixir",
        ]:
            self.assertTrue(is_dosage_form_tag(tag), tag)

    def test_keeps_drug_class_labels(self):
        for tag in [
            "calcium channel blocker, dihydropyridine",
            "stimulant",
            "ssri",
            "class:Pyrrolidinophenone cathinone stimulant",
            "FDA-black-box-pediatric-respiratory-depression",
        ]:
            self.assertFalse(is_dosage_form_tag(tag), tag)


class TestAliasCasingDeterminism(unittest.TestCase):
    """Two spellings that normalise identically but differ only in case must
    resolve to the same stored spelling regardless of insertion order. Set/dict
    iteration is hash-randomized per process, so a first-write-wins rule shipped
    nondeterministic casing ("Alpha-O" vs "alpha-O") across builds. The tiebreak
    keeps the lexicographically smaller (capitalised) form."""

    def _stored_aliases(self, order):
        db = sqlite3.connect(":memory:")
        db.executescript(_mod.SCHEMA_SQL)
        build = Builder(db)
        build.seed_sources()
        sid = build.upsert_substance("Mephedrone", source_slug="piru-curated")
        for a in order:
            build._add_alias(sid, a, "piru-curated")
        return [
            r[0]
            for r in db.execute("SELECT alias FROM aliases WHERE substance_id=?", (sid,)).fetchall()
        ]

    def test_winner_independent_of_insertion_order(self):
        forward = self._stored_aliases(["alpha-O", "Alpha-O"])
        reverse = self._stored_aliases(["Alpha-O", "alpha-O"])
        self.assertEqual(forward, reverse)
        self.assertEqual(forward, ["Alpha-O"])  # ASCII upper < lower

    def test_capitalised_form_preferred(self):
        self.assertEqual(self._stored_aliases(["indian pipe", "Indian Pipe"]), ["Indian Pipe"])
        self.assertEqual(self._stored_aliases(["Indian Pipe", "indian pipe"]), ["Indian Pipe"])


class TestBuildMisconceptionsJSON(unittest.TestCase):
    """build_misconceptions_json transforms author-shape misconceptions into the
    iOS [MythBust] Codable JSON, parsing citation ref-strings via parse_reference."""

    def _one(self, raw):
        out = build_misconceptions_json(raw)
        return __import__("json").loads(out) if out else out

    def test_none_and_empty(self):
        self.assertIsNone(build_misconceptions_json(None))
        self.assertIsNone(build_misconceptions_json([]))
        self.assertIsNone(build_misconceptions_json("not a list"))

    def test_parses_citation_identifiers(self):
        raw = [
            {
                "claim": "C",
                "correction": "K",
                "citations": [
                    {"ref": "pmid:26073279", "role": "refutes", "note": "n"},
                    {"ref": "doi:10.1126/science.1074501", "role": "retractedSource"},
                    {"ref": "A free-text label"},
                ],
            }
        ]
        out = self._one(raw)
        cites = out[0]["citations"]
        self.assertEqual(cites[0]["citation"], {"pmid": 26073279})
        self.assertEqual(cites[0]["role"], "refutes")
        self.assertEqual(cites[0]["note"], "n")
        self.assertEqual(cites[1]["citation"], {"doi": "10.1126/science.1074501"})
        self.assertEqual(cites[1]["role"], "retractedSource")
        # A bare label with no id is kept in `url` (renders as non-tappable text).
        self.assertEqual(cites[2]["citation"], {"url": "A free-text label"})
        # Absent role defaults to refutes.
        self.assertEqual(cites[2]["role"], "refutes")

    def test_bad_role_falls_back_to_refutes(self):
        raw = [{"claim": "C", "correction": "K", "citations": [{"ref": "pmid:1", "role": "bogus"}]}]
        self.assertEqual(self._one(raw)[0]["citations"][0]["role"], "refutes")

    def test_uncited_myth_is_dropped(self):
        raw = [
            {"claim": "kept", "correction": "K", "citations": [{"ref": "pmid:1"}]},
            {"claim": "dropped", "correction": "K", "citations": []},
            {"claim": "also dropped", "correction": "K"},
        ]
        claims = [m["claim"] for m in self._one(raw)]
        self.assertEqual(claims, ["kept"])

    def test_myth_without_claim_or_correction_dropped(self):
        raw = [
            {"claim": "", "correction": "K", "citations": [{"ref": "pmid:1"}]},
            {"claim": "C", "correction": "  ", "citations": [{"ref": "pmid:1"}]},
        ]
        self.assertIsNone(build_misconceptions_json(raw))

    def test_pullquote_requires_text_and_attribution(self):
        good = [
            {
                "claim": "C",
                "correction": "K",
                "citations": [{"ref": "pmid:1"}],
                "pullQuote": {"text": "t", "attribution": "a"},
            }
        ]
        self.assertIn("pullQuote", self._one(good)[0])
        partial = [
            {
                "claim": "C",
                "correction": "K",
                "citations": [{"ref": "pmid:1"}],
                "pullQuote": {"text": "t", "attribution": ""},
            }
        ]
        self.assertNotIn("pullQuote", self._one(partial)[0])


class TestMisconceptionValidator(unittest.TestCase):
    """The curated validator enforces the authoring contract: every myth cites
    at least one source, roles are valid, and popularAliases are well-formed."""

    def _check(self, entry, fname="foo.json"):
        import json
        import tempfile

        d = Path(tempfile.mkdtemp())
        (d / fname).write_text(json.dumps(entry))
        return _vmod.validate_dir(d)[0]

    _base = {"name": "Foo", "aliases": [], "category": "Stimulant"}

    def test_uncited_myth_errors(self):
        e = dict(self._base, misconceptions=[{"claim": "c", "correction": "k", "citations": []}])
        self.assertTrue(any("at least one citation" in x for x in self._check(e)))

    def test_missing_citations_key_errors(self):
        e = dict(self._base, misconceptions=[{"claim": "c", "correction": "k"}])
        self.assertTrue(any("at least one citation" in x for x in self._check(e)))

    def test_bad_role_errors(self):
        e = dict(
            self._base,
            misconceptions=[
                {"claim": "c", "correction": "k", "citations": [{"ref": "pmid:1", "role": "nope"}]}
            ],
        )
        self.assertTrue(any("bad role" in x for x in self._check(e)))

    def test_empty_ref_errors(self):
        e = dict(
            self._base,
            misconceptions=[{"claim": "c", "correction": "k", "citations": [{"ref": "  "}]}],
        )
        self.assertTrue(any("non-empty 'ref'" in x for x in self._check(e)))

    def test_missing_claim_errors(self):
        e = dict(
            self._base,
            misconceptions=[{"correction": "k", "citations": [{"ref": "pmid:1"}]}],
        )
        self.assertTrue(any("non-empty 'claim'" in x for x in self._check(e)))

    def test_pullquote_needs_both_fields(self):
        e = dict(
            self._base,
            misconceptions=[
                {
                    "claim": "c",
                    "correction": "k",
                    "citations": [{"ref": "pmid:1"}],
                    "pullQuote": {"text": "t"},
                }
            ],
        )
        self.assertTrue(any("pullQuote needs" in x for x in self._check(e)))

    def test_popular_aliases_must_be_strings(self):
        e = dict(self._base, popularAliases=["ok", 42])
        self.assertTrue(any("popularAliases entries must be" in x for x in self._check(e)))

    def test_valid_misconception_passes(self):
        e = dict(
            self._base,
            popularAliases=["Ecstasy", "Molly"],
            misconceptions=[
                {
                    "claim": "c",
                    "correction": "k",
                    "citations": [{"ref": "pmid:1", "role": "refutes", "note": "n"}],
                    "pullQuote": {"text": "t", "attribution": "a"},
                }
            ],
        )
        self.assertEqual(self._check(e), [])


class TestMDMACuratedContent(unittest.TestCase):
    """The shipped mdma.json is the reference author — guard its curated content."""

    def test_mdma_has_valid_popular_aliases_and_cited_myths(self):
        import json

        mdma = json.loads((_REPO / "data/curated/substances/mdma.json").read_text())
        self.assertEqual(mdma.get("popularAliases"), ["Ecstasy", "Molly", "E"])
        myths = mdma.get("misconceptions") or []
        self.assertGreaterEqual(len(myths), 3)
        for m in myths:
            self.assertTrue(m.get("claim") and m.get("correction"))
            self.assertTrue(m.get("citations"), "every myth must cite")
        # Exactly one retracted-source citation (the Ricaurte retraction story).
        roles = [c.get("role") for m in myths for c in m["citations"]]
        self.assertEqual(roles.count("retractedSource"), 1)
        # It round-trips through the pipeline transform into a decodable blob.
        out = build_misconceptions_json(myths)
        self.assertIsNotNone(out)
        decoded = json.loads(out)
        self.assertEqual(len(decoded), len(myths))


class TestAliasBlocklistIntegrity(unittest.TestCase):
    """The blocklist is a dict *literal*, so a repeated key is silently dropped —
    Python keeps the last one and says nothing.

    That is exactly what happened to the `tenamfetamine` entry when it was added:
    it was written, it parsed, it ran, and it did nothing, because an
    `"mdma": {"ma"}` key fifty lines below overrode it. The rebuilt DB still
    shipped the wrong-molecule alias and the only symptom was its absence.
    Parse the source and refuse duplicates.
    """

    def test_no_duplicate_keys(self):
        import ast

        src = (Path(__file__).resolve().parent.parent / "sqlite.py").read_text()
        literals = [
            node.value
            for node in ast.walk(ast.parse(src))
            if isinstance(node, ast.AnnAssign)
            and isinstance(node.target, ast.Name)
            and node.target.id == "_ALIAS_BLOCKLIST"
        ]
        self.assertEqual(len(literals), 1, "expected exactly one _ALIAS_BLOCKLIST assignment")
        keys = [k.value for k in literals[0].keys if isinstance(k, ast.Constant)]
        dupes = sorted({k for k in keys if keys.count(k) > 1})
        self.assertEqual(dupes, [], f"duplicate _ALIAS_BLOCKLIST keys silently override: {dupes}")

    def test_confirmed_wrong_molecule_aliases_stay_blocked(self):
        """GBL/1,4-BD are GHB's prodrugs — separate substances, dosed in mL where
        GHB is dosed in grams. Tenamfetamine is MDA's INN, not MDMA's."""
        blocklist = _mod._ALIAS_BLOCKLIST
        self.assertIn("tenamfetamine", blocklist["mdma"])
        self.assertIn("gbl", blocklist["ghb"])
        self.assertIn("1,4-bd", blocklist["ghb"])
        # 内酯 = lactone: every 内酯 name is GBL, not GHB.
        self.assertIn("γ-丁内酯", blocklist["ghb"])


class TestIsomerSynonymCoverage(unittest.TestCase):
    """Every `synonyms`/`brands` entry in isomer-families.json must land on an
    alias of its parent in the built DB.

    These names exist for one reason: to lift an enantiomer spelling out of the
    wrong-molecule sweep's `kept_unresolvable` bucket by giving it the isomer
    facet. A typo, or an upstream rename of the alias, silently un-lifts it —
    the entry parses, the build runs, and Levmetamfetamine quietly goes back to
    claiming it is racemic methamphetamine. Unlike the brand registry there is no
    build-time report for synonyms, so the gate lives here.
    """

    @classmethod
    def setUpClass(cls):
        p = Path(__file__).resolve().parents[3] / "Piru/Data/piru-substances.sqlite"
        if not p.exists():
            raise unittest.SkipTest("piru-substances.sqlite not built")
        cls.db = sqlite3.connect(p)

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    def test_every_synonym_and_brand_annotates_its_parent(self):
        families = json.loads(
            (Path(__file__).resolve().parents[3] / "data/curated/isomer-families.json").read_text()
        )["families"]
        unmatched, unfaceted = [], []
        for fam in families:
            # A family in the fold-skip list is never merged (Levetiracetam stays a
            # substance of its own rather than being buried under racemic
            # Etiracetam), so its brands stay on the *variant* and there is no fold
            # to hang an isomer facet from. Check coverage against the variant.
            skipped = fam["parent"] in _mod.Build._ISOMER_FOLD_SKIP
            for variant in fam["variants"]:
                holder = variant["name"] if skipped else fam["parent"]
                names = [*(variant.get("synonyms") or []), *(variant.get("brands") or [])]
                for name in names:
                    row = self.db.execute(
                        "SELECT a.isomer FROM aliases a JOIN substances s ON s.id = a.substance_id"
                        " WHERE a.alias_normalized = ? AND s.canonical_name = ?",
                        (_mod.normalise(name), holder),
                    ).fetchone()
                    if row is None:
                        unmatched.append(f"{name} ({holder})")
                    elif not skipped and row[0] != variant["isomer"].strip().upper():
                        unfaceted.append(f"{name} ({holder}): isomer={row[0]!r}")
        self.assertEqual(unmatched, [], f"isomer synonym/brand matched no alias: {unmatched}")
        self.assertEqual(unfaceted, [], f"alias carries the wrong isomer: {unfaceted}")

    def test_levmetamfetamine_is_the_l_enantiomer(self):
        """PubChem resolves Levmetamfetamine and l-desoxyephedrine to one CID
        (36604, the 2R/levo isomer) — the Vicks inhaler decongestant, not the
        stimulant. Without the facet a search for either lands on racemic
        Methamphetamine and inherits its dose ladder."""
        for alias in ("levmetamfetamine", "l-desoxyephedrine", "l-metamphetamine"):
            row = self.db.execute(
                "SELECT a.isomer FROM aliases a JOIN substances s ON s.id = a.substance_id"
                " WHERE a.alias_normalized = ? AND s.canonical_name = 'Methamphetamine'",
                (alias,),
            ).fetchone()
            self.assertIsNotNone(row, f"{alias} is not an alias of Methamphetamine")
            self.assertEqual(row[0], "L", f"{alias} should be the L enantiomer")


class TestLocusPrefixNormalisation(unittest.TestCase):
    """One molecule, one spelling, one card."""

    def test_spelled_prefixes_fold_onto_the_letter(self):
        for spelled, expected in (
            ("alpha-hydroxyalprazolam", "α-hydroxyalprazolam"),
            ("alpha-hydroxyetizolam", "α-hydroxyetizolam"),
            ("beta-OH-THC", "β-OH-THC"),
            ("omega-OH-JWH-018", "ω-OH-JWH-018"),
            (
                "1-hydroxymidazolam (alpha-hydroxymidazolam)",
                "1-hydroxymidazolam (α-hydroxymidazolam)",
            ),
        ):
            self.assertEqual(_mod.normalise_locus_prefix(spelled), expected)

    def test_alphaprodine_is_not_a_locus_prefix(self):
        """The hyphen is the whole guard: alphaprodine is an opioid, not an
        alpha-substituted anything, and mangling it to 'αprodine' would make the
        name unfindable."""
        for untouched in ("alphaprodine", "Alphaprodine", "betaine", "gammabutyrolactone"):
            self.assertEqual(_mod.normalise_locus_prefix(untouched), untouched)

    def test_none_and_empty_pass_through(self):
        self.assertIsNone(_mod.normalise_locus_prefix(None))
        self.assertEqual(_mod.normalise_locus_prefix(""), "")


class TestMetaboliteNameCollisions(unittest.TestCase):
    """The app groups metabolite rows by `metaboliteName.lowercased()`, so two
    spellings of one name are two metabolites to it — alprazolam, etizolam and
    triazolam each rendered two cards for one molecule."""

    @classmethod
    def setUpClass(cls):
        p = Path(__file__).resolve().parents[3] / "Piru/Data/piru-substances.sqlite"
        if not p.exists():
            raise unittest.SkipTest("piru-substances.sqlite not built")
        cls.db = sqlite3.connect(p)

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    def test_no_substance_names_one_metabolite_two_ways(self):
        rows = self.db.execute(
            "SELECT s.canonical_name, m.metabolite_name FROM metabolism m"
            "  JOIN substances s ON s.id = m.substance_id"
            " WHERE m.metabolite_name IS NOT NULL"
        ).fetchall()
        seen: dict[tuple[str, str], set[str]] = {}
        for substance, metabolite in rows:
            key = (substance, _mod.normalise_locus_prefix(metabolite).lower())
            seen.setdefault(key, set()).add(metabolite.lower())
        clashes = {k: sorted(v) for k, v in seen.items() if len(v) > 1}
        self.assertEqual(clashes, {}, f"one metabolite spelled two ways: {clashes}")


class TestComparableSetIntegrity(unittest.TestCase):
    """A pharmacology number means nothing without the basis it was measured on.

    The failure this guards is not hypothetical: MDMA once mixed a binding Ki
    (DAT 22000) with a release EC50 (NET 77.4) and rendered 95% noradrenergic
    off a 284x ratio that was an artifact of comparing two different
    measurements. `comparable_set` is the fix — rows may be ranked only against
    rows sharing one — so the set has to actually mean one experiment.
    """

    @classmethod
    def setUpClass(cls):
        p = Path(__file__).resolve().parents[3] / "Piru/Data/piru-substances.sqlite"
        if not p.exists():
            raise unittest.SkipTest("piru-substances.sqlite not built")
        cls.db = sqlite3.connect(p)

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    def test_tau_rows_carry_a_reference_agonist_and_a_set(self):
        """Operational tau is a RATIO to a reference agonist measured in the same
        experiment. Without naming that agonist the number is unanchored, and
        without a comparable_set it will eventually be ranked against one from a
        different assay system."""
        orphans = self.db.execute(
            "SELECT s.canonical_name, b.target, b.relative_tau, b.reference_agonist,"
            "       b.comparable_set"
            "  FROM bindings b JOIN substances s ON s.id = b.substance_id"
            " WHERE b.relative_tau IS NOT NULL"
            "   AND (b.reference_agonist IS NULL OR b.comparable_set IS NULL)"
        ).fetchall()
        self.assertEqual(orphans, [], f"tau rows with no basis: {orphans}")

    def test_a_comparable_set_is_one_species(self):
        """One experiment is run in one system. A set spanning rat and human is
        two experiments wearing one label, and ranking across it reintroduces
        exactly the error the field exists to prevent."""
        mixed = self.db.execute(
            "SELECT comparable_set, COUNT(DISTINCT species)"
            "  FROM bindings WHERE comparable_set IS NOT NULL AND species IS NOT NULL"
            " GROUP BY comparable_set HAVING COUNT(DISTINCT species) > 1"
        ).fetchall()
        # The review meta-summary is the deliberate exception: it is explicitly
        # labeled not-comparable precisely because it pools systems.
        mixed = [row for row in mixed if "not-comparable" not in row[0]]
        self.assertEqual(mixed, [], f"comparable_set spans multiple species: {mixed}")

    def test_a_binding_only_panel_reports_no_efficacy(self):
        """Volpe 2011 is a uniform radioligand BINDING panel — it measures what
        sticks, not what it does. An Emax attached to one of its rows is a value
        no one measured, and morphine carried exactly that (100% of DAMGO), which
        contradicts both functional panels (93%, 94%) and its own tau of 0.18."""
        rows = self.db.execute(
            "SELECT s.canonical_name, b.intrinsic_activity_pct, b.emax_pct"
            "  FROM bindings b JOIN substances s ON s.id = b.substance_id"
            " WHERE b.comparable_set = 'volpe-2011-human-mor-ki'"
            "   AND (b.intrinsic_activity_pct IS NOT NULL OR b.emax_pct IS NOT NULL)"
        ).fetchall()
        self.assertEqual(rows, [], f"efficacy attributed to a binding-only panel: {rows}")

    def test_dihydromorphine_did_not_land_on_hydromorphone(self):
        """The single likeliest silent corruption in this class. Dihydromorphine
        (Emax 109% of DAMGO, Ki 1.7 nM) and hydromorphone sit one letter apart in
        adjacent rows of Toll 1998's table, and they are different molecules —
        hydromorphone is the 6-ketone. Dihydromorphine is not in the catalog, so
        no Toll row may appear on hydromorphone at all."""
        rows = self.db.execute(
            "SELECT b.ki_nm, b.intrinsic_activity_pct"
            "  FROM bindings b JOIN substances s ON s.id = b.substance_id"
            " WHERE s.canonical_name = 'Hydromorphone'"
            "   AND b.comparable_set = 'toll-1998-human-mor'"
        ).fetchall()
        self.assertEqual(rows, [], f"Toll's dihydromorphine row landed on Hydromorphone: {rows}")

    def test_buprenorphine_is_high_affinity_low_efficacy(self):
        """The profile that explains the drug: it binds tighter than morphine and
        does less once bound. If a future ingest ever flips either half, the
        ceiling effect stops being derivable from the data."""
        tau = self.db.execute(
            "SELECT MAX(b.relative_tau) FROM bindings b JOIN substances s ON s.id = b.substance_id"
            " WHERE s.canonical_name = 'Buprenorphine' AND b.relative_tau IS NOT NULL"
        ).fetchone()[0]
        self.assertIsNotNone(tau, "buprenorphine has no operational efficacy")
        self.assertLess(tau, 0.1, "buprenorphine should be a low-efficacy partial agonist")
        bup, morph = (
            self.db.execute(
                "SELECT b.ki_nm FROM bindings b JOIN substances s ON s.id = b.substance_id"
                " WHERE s.canonical_name = ? AND b.comparable_set = 'volpe-2011-human-mor-ki'",
                (name,),
            ).fetchone()[0]
            for name in ("Buprenorphine", "Morphine")
        )
        self.assertLess(bup, morph, "buprenorphine should bind tighter than morphine")


if __name__ == "__main__":
    unittest.main(verbosity=2)
