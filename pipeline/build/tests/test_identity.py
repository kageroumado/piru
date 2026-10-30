"""Identity guards: a record lands on the molecule it describes, and nothing else.

Each class here shipped wrong data before it had a test:

  1. **Erowid chapters on the wrong drug.** Shulgin's book codes are street names
     of other drugs, so name matching filed mescaline's chapter (M) on Morphine and
     tryptamine's (T) on Methamphetamine. Chapters resolve only through
     ``data/curated/erowid-ids.json``; these tests hold every erowid row and every
     chapter citation to it, and keep short codes out of cross-source matching.
  2. **Single-isomer labels on the racemate.** MedTAP files Lunesta under
     Zopiclone; the label measured eszopiclone.
  3. **Wrong-kind rows.** A salt stored as the substance, an enzyme stored as a
     substance.
  4. **Chinese-only canonical names.** A FreeOD page with no Latin name minted a
     row an English reader cannot read.
  5. **Sources without a stated origin.** Every source row says where it comes
     from and, where known, under what license.

Run from the repo root (needs the built DB):
    python3 pipeline/build/tests/test_identity.py
"""

import importlib.util
import json
import re
import sqlite3
import unittest
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    "bsd_identity", Path(__file__).resolve().parent.parent / "sqlite.py"
)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)

_REPO = Path(__file__).resolve().parents[3]
_DB = _REPO / "Piru/Data/piru-substances.sqlite"
_EROWID_IDS = _REPO / "data/curated/erowid-ids.json"
_MEDTAP_PK = _REPO / "data/sources/medtap-pk.json"


def _db() -> sqlite3.Connection:
    if not _DB.exists():
        raise unittest.SkipTest(f"{_DB} not built")
    return sqlite3.connect(_DB)


def _fresh_build():
    db = sqlite3.connect(":memory:")
    db.executescript(_mod.SCHEMA_SQL)
    build = _mod.Build(db)
    build.seed_sources()
    return build


class TestShortCodes(unittest.TestCase):
    def test_short_codes(self) -> None:
        for name in ("M", "T", "E", "AL", "IP", "Ma", "G", "2C"):
            self.assertTrue(_mod.is_short_code(name), name)
        for name in ("MAL", "MDA", "PEA", "DESOXY", "4-MA", "Morphine"):
            self.assertFalse(_mod.is_short_code(name), name)

    def test_short_alias_never_resolves_a_record(self) -> None:
        """A record named "M" must not reach Morphine through Morphine's street
        name, and a longer alias still resolves."""
        build = _fresh_build()
        sid = build.upsert_substance(
            "Morphine", aliases=["M", "Morf"], source_slug="drug.community"
        )
        index = build._alias_index()
        self.assertIsNone(build._resolve_by_name_alias("M", index))
        self.assertEqual(build._resolve_by_name_alias("Morf", index), sid)

    def test_short_alias_never_links_dedup(self) -> None:
        """Dedup's alias→canonical link skips short codes: a row named "T" and
        Methamphetamine's street name "T" are not evidence of one molecule."""
        build = _fresh_build()
        build.upsert_substance(
            "Methamphetamine",
            aliases=["T"],
            inchikey="MYWUZJCMWCOHBA-VIFPVBQESA-N",
            source_slug="psychonautwiki",
        )
        build.upsert_substance("T", inchikey="MYWUZJCMWCOHBA-VIFPVBQESA-N", source_slug="tripsit")
        self.assertEqual(build.dedup_substances().get("groups", 0), 0)


class TestErowidChapterMap(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.entries = _mod.load_erowid_ids()

    def test_every_entry_names_a_substance(self) -> None:
        bad = [k for k, e in self.entries.items() if not (e.get("substance") or "").strip()]
        self.assertEqual(bad, [])
        for key in self.entries:
            self.assertRegex(key, r"^(pi|ti)hkal\d+$")

    def test_chapter_key_reads_the_url(self) -> None:
        url = "https://erowid.org/library/books_online/pihkal/pihkal096.shtml"
        self.assertEqual(_mod.erowid_chapter_key(["PIHKAL text", url]), "pihkal096")
        self.assertIsNone(_mod.erowid_chapter_key(["https://erowid.org/x.shtml"]))

    def test_codes_are_never_the_wrong_drug(self) -> None:
        """The four chapters that shipped on the wrong molecule."""
        want = {
            "pihkal096": "Mescaline",
            "tihkal53": "Tryptamine",
            "pihkal052": "DESOXY",
            "pihkal116": "MDPH",
        }
        for key, substance in want.items():
            self.assertEqual(self.entries[key]["substance"], substance, key)

    def test_unmapped_chapter_is_skipped_and_reported(self) -> None:
        build = _fresh_build()
        record = {
            "name": "M",
            "sources": ["https://erowid.org/library/books_online/pihkal/pihkal999.shtml"],
        }
        self.assertIsNone(build._resolve_erowid_chapter(record, "erowid-pihkal"))
        self.assertEqual(build.erowid_unmapped, [("erowid-pihkal", "M", "pihkal999")])

    def test_mapped_chapter_takes_the_map_name_and_never_a_short_alias(self) -> None:
        build = _fresh_build()
        url = "https://erowid.org/library/books_online/pihkal/pihkal096.shtml"
        out = build._resolve_erowid_chapter({"name": "M", "sources": [url]}, "erowid-pihkal")
        self.assertEqual(out["name"], "Mescaline")
        self.assertNotIn("M", out["aliases"])
        self.assertEqual(out["_record_name"], "M")

    def test_every_erowid_dose_row_and_citation_sits_on_its_chapter(self) -> None:
        db = _db()
        by_url = {
            f"/{key[:6]}/{key}.shtml": _mod.normalise(entry["substance"])
            for key, entry in self.entries.items()
        }
        wrong = []
        cited: dict[str, set[str]] = {}
        for name, url in db.execute(
            "SELECT s.canonical_name, c.url FROM substance_citations sc "
            "JOIN citations c ON c.id = sc.citation_id "
            "JOIN substances s ON s.id = sc.substance_id "
            "WHERE c.url LIKE '%erowid.org/library/books_online/%hkal/%hkal%.shtml'"
        ):
            m = re.search(r"/(pi|ti)hkal/((?:pi|ti)hkal\d+)\.shtml", url)
            key = f"/{m.group(1)}hkal/{m.group(2)}.shtml"
            want = by_url.get(key)
            if want is None:
                wrong.append(f"{name}: {url} is in no erowid-ids.json entry")
            elif _mod.normalise(name) != want:
                wrong.append(f"{name}: cites {url}, which erowid-ids.json files under {want}")
            cited.setdefault(_mod.normalise(name), set()).add(m.group(1))
        self.assertEqual(wrong, [], "chapter citations on the wrong substance")
        mapped = {(key[:2], _mod.normalise(e["substance"])) for key, e in self.entries.items()}
        strays = []
        for name, slug, route in db.execute(
            "SELECT s.canonical_name, so.slug, d.route FROM dose_ranges d "
            "JOIN substances s ON s.id = d.substance_id "
            "JOIN sources so ON so.id = d.source_id WHERE so.slug LIKE 'erowid-%'"
        ):
            book = "pi" if slug == "erowid-pihkal" else "ti"
            if (book, _mod.normalise(name)) not in mapped:
                strays.append(f"{name} {slug} {route}")
        self.assertEqual(strays, [], "erowid dose rows on a substance no chapter names")

    def test_map_structures_agree_with_the_rows(self) -> None:
        """Where both the entry and its row carry a structure, they are one
        molecule (connectivity block; stereo may be unspecified on either side)."""
        db = _db()
        keys = {
            _mod.normalise(name): ik
            for name, ik in db.execute("SELECT canonical_name, inchikey FROM substances")
        }
        bad = []
        for key, entry in self.entries.items():
            row_key = keys.get(_mod.normalise(entry["substance"]))
            if entry.get("inchikey") and row_key and row_key[:14] != entry["inchikey"][:14]:
                bad.append(f"{key}: map {entry['inchikey']} vs row {row_key}")
        self.assertEqual(bad, [])


class TestMedtapIsomerLabels(unittest.TestCase):
    def test_isomer_labels_are_recognized(self) -> None:
        tokens = _mod.isomer_label_tokens()
        cases = {
            ("Zopiclone", "Lunesta"): "Eszopiclone",
            ("Amphetamine", "Zenzedi"): "Dextroamphetamine",
            ("Citalopram", "Escitalopram Oxalate"): "Escitalopram",
            (
                "Methylphenidate",
                "Dexmethylphenidate Hydrochloride Extended-release",
            ): "Dexmethylphenidate",
        }
        for (substance, brand), isomer in cases.items():
            entry = {"substance": substance, "brand": brand}
            self.assertEqual(_mod.medtap_isomer_label(entry, tokens), isomer, brand)
        for substance, brand in [
            ("Zopiclone", "Zopiclone Tablets"),
            ("Amphetamine", "Adderall"),
            ("Modafinil", "Modafinil"),
            ("Diazepam", "Valium"),
        ]:
            entry = {"substance": substance, "brand": brand}
            self.assertIsNone(_mod.medtap_isomer_label(entry, tokens), brand)

    def test_no_isomer_label_value_on_a_parent(self) -> None:
        """No medtap half-life or pk_routes row on a family parent comes from a
        label for one of its isomers (the citation carries the label's NDC)."""
        if not _MEDTAP_PK.exists():
            raise unittest.SkipTest("medtap-pk.json absent")
        db = _db()
        tokens = _mod.isomer_label_tokens()
        offenders = []
        for entry in json.loads(_MEDTAP_PK.read_text()).get("entries", []):
            if not entry.get("ndc") or _mod.medtap_isomer_label(entry, tokens) is None:
                continue
            for table in ("half_lives", "pk_routes"):
                n = db.execute(
                    f"SELECT COUNT(*) FROM {table} t "
                    "JOIN substances s ON s.id = t.substance_id "
                    "JOIN sources so ON so.id = t.source_id "
                    "JOIN citations c ON c.id = t.citation_id "
                    "WHERE so.slug = 'medtap' AND s.canonical_name = ? AND c.url LIKE ?",
                    (entry["substance"], f"%query={entry['ndc']}"),
                ).fetchone()[0]
                if n:
                    offenders.append(f"{entry['substance']} {table} <- {entry['brand']}")
        self.assertEqual(offenders, [])


#: Rows whose stored SMILES is several components on purpose: a mixture, a
#: permanently charged ion, or a salt a mineral is dosed as.
_MULTI_COMPONENT_OK = {
    "Lithium": "lithium citrate: lithium is dosed as a salt",
    "Methylene blue": "a permanent thiazinium cation; the chloride is the compound",
    "Cisatracurium": "a bis-quaternary ammonium dication with its besylate counter-ions",
    "Tuinal": "a mixture: secobarbital and amobarbital sodium",
    "Nabiximols": "a mixture: THC and CBD",
}
#: Rows that still store a salt as the substance. Each one is a defect to fix
#: (the free base, with the salt in its alias), never a row to add: the list
#: only shrinks.
_SALT_STORED_PENDING = {
    "2-MAPB",
    "4-Fluoroethamphetamine",
    "4-Fluorophenylpiperazine",
    "5-EAPB",
    "BZP",
    "Bemethyl",
    "Cyputylone",
    "D2pm",
    "Dimethocaine",
    "MBDB",
    "MBZP",
    "MDPHP",
    "MK-677",
    "Mephtetramine",
    "Methiodone",
    "N-Pyrrolidino-etonitazene",
    "N-Pyrrolidino-metonitazene",
    "PMMA",
    "PRL-8-53",
    "PV-8",
    "RTI-111",
    "Tetracycline",
    "α-Pyrrolidinopropiophenone",
}


class TestWrongKindRows(unittest.TestCase):
    def test_no_new_salt_stored_as_the_substance(self) -> None:
        db = _db()
        multi = {
            name
            for name, smiles in db.execute(
                "SELECT canonical_name, smiles FROM substances WHERE smiles IS NOT NULL"
            )
            if "." in smiles or "[H+]" in smiles
        }
        unexpected = sorted(multi - set(_MULTI_COMPONENT_OK) - _SALT_STORED_PENDING)
        self.assertEqual(unexpected, [], "new multi-component SMILES (a salt stored as the drug?)")
        fixed = sorted(_SALT_STORED_PENDING - multi)
        self.assertEqual(fixed, [], "fixed: delete these from _SALT_STORED_PENDING")

    def test_2_aminoindane_is_the_free_base(self) -> None:
        row = (
            _db()
            .execute(
                "SELECT inchikey, smiles, formula FROM substances WHERE canonical_name = '2-Aminoindane'"
            )
            .fetchone()
        )
        self.assertEqual(row, ("LMHHFZAXSANGGM-UHFFFAOYSA-N", "NC1Cc2ccccc2C1", "C9H11N"))

    def test_no_enzyme_or_target_named_row(self) -> None:
        """A protein-target name is a label filed under its target (terbinafine's
        as "Squalene monooxygenase"), never a substance someone doses."""
        names = [
            name
            for (name,) in _db().execute("SELECT canonical_name FROM substances")
            if _mod.Build._MEDTAP_JUNK_RE.search(name)
        ]
        self.assertEqual(names, [])
        for name in ("Asparaginase", "Pancrelipase", "Hyaluronidase", "Rasburicase"):
            self.assertIsNone(_mod.Build._MEDTAP_JUNK_RE.search(name), name)

    def test_charge_state_names(self) -> None:
        for name in ("Serotonin(1+)", "D-synephrine(1+)", "Phenylethanolaminium"):
            self.assertTrue(_mod.is_charge_state_name(name), name)
        for name in ("Lithium", "Sodium", "Potassium", "Serotonin"):
            self.assertFalse(_mod.is_charge_state_name(name), name)


#: FreeOD-only rows that keep a Chinese canonical name, and why no English one
#: can be given.
_CJK_CANONICAL_OK = {
    "苏摩": "Soma, the Vedic ritual drink: its plant is unidentified, and the English "
    "name Soma is a carisoprodol brand already on another row",
}


class TestCanonicalScript(unittest.TestCase):
    def test_no_cjk_only_canonical_name(self) -> None:
        names = sorted(
            name
            for (name,) in _db().execute("SELECT canonical_name FROM substances")
            if not re.search(r"[A-Za-z]", name) and name not in _CJK_CANONICAL_OK
        )
        self.assertEqual(names, [], "give these an English canonical or list them with a reason")

    def test_allowlist_is_live(self) -> None:
        names = {n for (n,) in _db().execute("SELECT canonical_name FROM substances")}
        self.assertEqual(sorted(set(_CJK_CANONICAL_OK) - names), [], "stale allowlist entry")


#: Descriptions that say nothing about where the data comes from.
_PLACEHOLDERS = {
    "community database.",
    "community table.",
    "community wiki.",
    "chemistry catalogue.",
    "chemistry catalog.",
    "u.s. product labels.",
    "maintained by piru's editors.",
}
#: substance.wiki states no terms for its data; describing them is its call.
_DESCRIPTION_AS_PUBLISHED = {"drug.community"}


class TestSourceDescriptions(unittest.TestCase):
    def test_every_source_says_where_it_comes_from(self) -> None:
        bad = []
        for slug, _name, desc in _mod.SOURCES:
            if slug in _DESCRIPTION_AS_PUBLISHED:
                continue
            text = (desc or "").strip()
            if text.lower() in _PLACEHOLDERS or len(text) < 30:
                bad.append(f"{slug}: {text!r}")
        self.assertEqual(bad, [])

    def test_descriptions_name_no_private_location(self) -> None:
        leaks = [
            f"{slug}: {desc}"
            for slug, _n, desc in _mod.SOURCES
            if re.search(r"/Users/|~/|piru-data|Volumes|\b\d{1,3}(?:\.\d{1,3}){3}\b", desc)
        ]
        self.assertEqual(leaks, [])

    def test_built_db_carries_them(self) -> None:
        db = _db()
        shipped = dict(db.execute("SELECT slug, description FROM sources"))
        for slug, _name, desc in _mod.SOURCES:
            self.assertEqual(shipped.get(slug), desc, slug)


if __name__ == "__main__":
    unittest.main(verbosity=2)
