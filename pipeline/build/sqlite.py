#!/usr/bin/env python3
"""Build Piru/Data/piru-substances.sqlite from every JSON source we ship.

Inputs (all already in the repo):
  data/intermediate/sourced-substances.json — SubstanceCollector per-record output
                                               (already contains the piru-curated
                                               overlay baked in via Swift)
  data/intermediate/substances-bundled.json — SubstanceCollector merge output
                                               (fallback when sourced is absent)
  data/sources/drug-community.json          — drug.community snapshot
  data/sources/psychonautwiki.json          — PsychonautWiki GraphQL dump
  data/enrichment/raw/*.json                — deep-pharma enrichment swarm output

Outputs:
  Piru/Data/piru-substances.sqlite          — bundled read-only database (what the app ships)
  Piru/Data/manifest.json                   — version + sha256 + release notes
  docs/audit/sqlite-build-report.md         — build statistics

Run from the repo root:
    python3 pipeline/build/sqlite.py
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import sqlite3
import sys
import unicodedata
from collections import Counter, defaultdict
from datetime import UTC, datetime
from pathlib import Path

# Sibling module import that works both as a script (`python3 pipeline/build/
# sqlite.py`, where the script dir is already on sys.path) and when the test
# suite loads this file via importlib spec (where it is not).
sys.path.insert(0, str(Path(__file__).resolve().parent))

from effect_vocab import EFFECT_VOCAB, vocab_id_for, vocab_labels  # noqa: E402
from pw_effect_categories import PW_EFFECT_CATEGORY, normalize_effect  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
OUT_SQLITE = REPO / "Piru/Data/piru-substances.sqlite"
OUT_MANIFEST = REPO / "Piru/Data/manifest.json"
OUT_REPORT = REPO / "docs/audit/sqlite-build-report.md"

SOURCED = REPO / "data/intermediate/sourced-substances.json"
# Curated substances, one JSON file per compound (authoritative hand-curated
# layer). Ingested directly as the `piru-curated` source — sqlite.py is the
# single consumer, so there is no overlay→sourced bake step to drift out of sync.
CURATED_DIR = REPO / "data/curated/substances"
BUNDLED = REPO / "data/intermediate/substances-bundled.json"
DRUG_COMMUNITY = REPO / "data/sources/drug-community.json"
FREEODWIKI = REPO / "data/sources/freeodwiki.json"
# Citation link-health cache produced by pipeline/audit/validate_links.py.
# The build drops citations this proved dead (HTTP 404/410) so no broken link ships.
LINK_CACHE = REPO / "data/sources/link-cache.json"
PSYCHONAUTWIKI = REPO / "data/sources/psychonautwiki.json"
ENRICHMENT_DIR = REPO / "data/enrichment/raw"

# External datasource extractions (Substance-shaped JSON with x_* extension
# fields). Produced out-of-repo by pipeline/fetch/brushers/extract.py from the
# raw files in ~/Developer/piru-datasources. Kept out of the repo by design —
# the built SQLite is the committed artifact, the raw extractions are not.
# Override with PIRU_EXTERNAL_DIR if regenerated elsewhere.
EXTERNAL_DIR = Path(os.environ.get("PIRU_EXTERNAL_DIR", "/tmp/piru-extract"))
PYRLS_EXT = EXTERNAL_DIR / "pyrls.substances.json"
MEDTAP_EXT = EXTERNAL_DIR / "medtap.substances.json"
BENZOS_EXT = EXTERNAL_DIR / "benzos_cited.substances.json"
NPS_EXT = EXTERNAL_DIR / "nps_datahub.substances.json"

# Note: data/curated/overlay.json used to be referenced here, but the Python
# build pipeline reads data/intermediate/sourced-substances.json — which
# already has the curated overlay merged in by the Swift SubstanceCollector
# (Curation/CuratedOverlay.swift, step 5/5 of the build). Keeping a separate
# `CURATED` constant here was dead code and a second files-of-truth that
# misled anyone reading the script. New curated overrides go into
# data/curated/overlay.json and are baked into sourced-substances.json by
# the next SubstanceCollector run.

# Default source priority. Lower number = higher priority. User can override.
SOURCES = [
    (
        "piru-curated",
        "Piru hand-curated overlay",
        "Curated by the Piru maintainers, prioritised for accuracy on harm-reduction-critical compounds.",
    ),
    (
        "peer-review-primary",
        "Primary peer-reviewed literature",
        "Cited DOI/PMID from primary journal articles. Deep-pharma enrichment swarm output.",
    ),
    ("psychonautwiki", "PsychonautWiki", "Community harm-reduction wiki."),
    ("tripsit", "TripSit factsheets", "Community harm-reduction factsheets and combo matrix."),
    ("drug.community", "drug.community", "Curated long-tail research-chemical dataset."),
    ("dailymed", "FDA DailyMed", "FDA-approved prescribing labels."),
    (
        "erowid-pihkal",
        "Erowid PIHKAL Part 2",
        "Shulgin phenethylamine compendium, Erowid Part 2 only (non-commercial redistribution permitted).",
    ),
    ("erowid-tihkal", "Erowid TIHKAL Part 2", "Shulgin tryptamine compendium, Erowid Part 2 only."),
    ("pdsp", "UNC PDSP Ki database", "Canonical receptor affinity database (Roth lab)."),
    ("pubchem", "PubChem", "NIH chemical compound identifiers."),
    ("wikidata", "Wikidata", "CC0 structured data; identifier-only for long-tail compounds."),
    ("dea-orange-book", "DEA Orange Book", "US controlled-substance scheduling."),
    # Appended at lowest priority so they only FILL GAPS (existing recreational
    # sources win on conflict). pyrls/medtap supply regulatory status,
    # indications, contraindications, and per-compound mechanism for the
    # medication side; benzos-cited supplies diazepam-equivalency; nps-datahub
    # supplies chemical identifiers (identifier-only, never new substances).
    (
        "pyrls",
        "Pyrls clinical reference",
        "Prescription-drug clinical reference: mechanism, indications, contraindications, regulatory status.",
    ),
    (
        "medtap",
        "MedTAP FDA labels",
        "FDA structured product labels: indications, contraindications, OTC/Rx status.",
    ),
    (
        "benzos-cited",
        "TripSit benzo equivalency",
        "TripSit-format benzodiazepine data; source of cross-benzo diazepam-equivalency.",
    ),
    (
        "nps-datahub",
        "NPS Data Hub",
        "Forensic NPS chemistry catalogue; chemical identifiers (CAS/InChIKey/SMILES/formula/MW) only.",
    ),
    # Lowest priority: a Chinese-language source whose text only WINS when the
    # app runs in Chinese (the resolver floats matching-language text above
    # source priority). In English it fills gaps via machine translation.
    (
        "freeodwiki",
        "FreeOD Wiki",
        "Chinese harm-reduction wiki (CC BY-SA 4.0): native zh descriptions, pharmacology, effects, dose/duration.",
    ),
]

# --- FreeOD Wiki ingest helpers ---------------------------------------------

_CJK_RE = re.compile(r"[㐀-䶿一-鿿]")

# FreeOD 精神活性分类 (psychoactive class) -> SubstanceCategory rawValue. Mapped
# to English here so add_category's normalize_category resolves cleanly and the
# iOS SubstanceCategory(rawValue:) decode succeeds. Unmapped classes are simply
# skipped (the substance falls back to "Other" / a higher-priority source).
FREEOD_CATEGORY_MAP = {
    "兴奋剂": "Stimulant",
    "抑制剂": "Depressant",
    "镇静剂": "Depressant",
    "迷幻剂": "Psychedelic",
    "致幻剂": "Psychedelic",
    "共情剂": "Empathogen",
    "解离剂": "Dissociative",
    "阿片类药物": "Opioid",
    "阿片类": "Opioid",
    "谵妄剂": "Deliriant",
    "大麻类": "Cannabinoid",
    "大麻素": "Cannabinoid",
    "益智药": "Nootropic",
    "促醒剂": "Eugeroic",
    "苯二氮卓类物质": "Benzodiazepine",
    "苯二氮卓类": "Benzodiazepine",
    "加巴喷丁类": "GABAergic",
    "抗抑郁药": "Antidepressant",
    "抗精神病药": "Antipsychotic",
    "镇痛药": "Analgesic",
    "止痛药": "Analgesic",
    "抗组胺药": "Antihistamine",
    "抗惊厥药": "Anticonvulsant",
    "抗癫痫药": "Anticonvulsant",
    "补充剂": "Supplement",
    "膳食补充剂": "Supplement",
    "肽": "Peptide",
    "多肽": "Peptide",
}


# Curated zh→English canonical map for FreeOD pages written with a fully
# Chinese intro (no English name anywhere on the page) where the auto-miner
# can't recover one. Targets are verified to exist in the bundled DB by an
# ingest-time check; an unrecognised target is still a valid English canonical
# (the page just becomes an English-named new substance rather than a Chinese
# one). Uncertain botanicals/RCs are intentionally omitted — they stay as
# genuine FreeOD-only entries under their Chinese title.
FREEOD_NAME_OVERRIDE = {
    "1,4-丁二醇": "1,4-Butanediol",
    "尼古丁": "Nicotine",
    "美沙酮": "Methadone",
    "芬太尼": "Fentanyl",
    "舒芬太尼": "Sufentanil",
    "乙酰芬太尼": "Acetylfentanyl",
    "曲马多": "Tramadol",
    "哌替啶": "Pethidine",
    "氢吗啡酮": "Hydromorphone",
    "羟考酮": "Oxycodone",
    "右美沙芬": "DXM",
    "右丙氧芬": "Dextropropoxyphene",
    "二氢可待因": "Dihydrocodeine",
    "二氢去氧吗啡": "Desomorphine",
    "替利定": "Tilidine",
    "洛哌丁胺": "Loperamide",
    "吡拉西坦": "Piracetam",
    "普拉西坦": "Pramiracetam",
    "普罗林坦": "Prolintane",
    "肌酸": "Creatine",
    "茶氨酸": "Theanine",
    "酪氨酸": "Tyrosine",
    "育亨宾": "Yohimbine",
    "胍丁胺": "Agmatine",
    "胞磷胆碱": "Citicoline",
    "酒石酸氢胆碱": "Choline Bitartrate",
    "颠茄": "Belladonna",
    "曼陀罗属": "Datura",
    "毒蝇伞": "Amanita Muscaria",
    "豹斑鹅膏": "Amanita Pantherina",
    "肉豆蔻醚": "Myristicin",
    "异丙嗪": "Promethazine",
    "羟嗪": "Hydroxyzine",
    "茶苯海明": "Dimenhydrinate",
    "苯海索": "Trihexyphenidyl",
    "氟哌啶醇": "Haloperidol",
    "氯氮平": "Clozapine",
    "奥氮平": "Olanzapine",
    "氟马西尼": "Flumazenil",
    "氯氮䓬": "Chlordiazepoxide",
    "溴西泮": "Bromazepam",
    "吡溴唑仑": "Pyrazolam",
    "氟溴西泮": "Flubromazepam",
    "氟阿普唑仑": "Flualprazolam",
    "氟氯替唑仑": "Fluclotizolam",
    "芬纳西泮": "Phenazepam",
    "去氯依替唑仑": "Deschloroetizolam",
    "甲丙氨酯": "Meprobamate",
    "戊巴比妥": "Pentobarbital",
    "司可巴比妥": "Secobarbital",
    "金刚烷胺": "Amantadine",
    "加兰他敏": "Galantamine",
    "加波沙多": "Gaboxadol",
    "阿莫达菲尼": "Armodafinil",
    "苄达明": "Benzydamine",
    "卡瓦": "Kava",
    "环己丙甲胺": "Propylhexedrine",
    "侧柏酮": "Thujone",
    "依非韦仑": "Efavirenz",
    "鹅膏蕈氨酸": "Ibotenic Acid",
    "蓝莲花": "Blue Lotus",
    "夏威夷小木玫瑰": "Hawaiian Baby Woodrose",
    "墨西哥鼠尾草": "Salvia Divinorum",
    "骆驼蓬": "Syrian Rue",
    "细花含羞草": "Mimosa Hostilis",
    "绿九节": "Psychotria Viridis",
    "古巴裸盖菇": "Psilocybe Cubensis",
    "墨西哥裸盖菇": "Psilocybe Mexicana",
    "蓝柄裸盖菇": "Psilocybe Cyanescens",
    "普罗斯卡林": "Proscaline",
    "硝基甲喹酮": "Nitromethaqualone",
    "烟草_ODW": "Tobacco",
    "三色牵牛": "Ipomoea Tricolor",
    "牵牛花": "Morning Glory",
    "死藤": "Banisteriopsis Caapi",
    "秘鲁火炬仙人掌": "Peruvian Torch",
    "乌羽玉": "Lophophora Williamsii",
    "二氟莫达菲尼": "Flmodafinil",
    "氯苄雷司": "Clobenzorex",
    "水虉草": "Phalaris",
    "亚硝酸酯": "Poppers",
    # Chinese-titled pages whose English/street name mined to a junk fragment
    # (a single letter or a number split out of a systematic name), which then
    # became a bogus canonical and, for Heroin, a duplicate substance.
    "海洛因": "Heroin",
    "替扎尼定": "Tizanidine",
    "甲基己胺": "DMAA",
    "艾斯卡林": "Escaline",
    "可可": "Cocoa",
}

# FreeOD index/category/genus pages that aren't individual substances — skipped
# so they don't pollute the substances table.
FREEOD_SKIP_PAGES = {
    "吸入剂",  # Inhalants — category page
    "致幻仙人掌",  # Hallucinogenic cacti — category page
    "裸盖菇属",  # Psilocybe — genus index
    "精神活性相思树属植物",  # Psychoactive Acacia spp — category page
}


def _freeod_canonical_name(title: str, names: list[str]) -> str | None:
    """Pick a Latin canonical name for a FreeOD page so it matches an existing
    English substance; fall back to the zh title for FreeOD-only compounds.

    Candidates that are clearly fragments — a lone letter or a number split out
    of a systematic name like "3,4-dimethoxy…" by comma-splitting — are rejected
    so they can never become a bogus canonical (which previously created junk
    substances named "1"/"2"/"H" and a Heroin duplicate)."""

    def is_fragment(c: str) -> bool:
        # No alpha at all ("1", "3-"), or a single bare letter ("H", "E").
        alpha = [ch for ch in c if ch.isalpha()]
        return not alpha or (len(alpha) < 2 and len(c) <= 2)

    cands = [
        c.strip() for c in ([title] + list(names)) if c and c.strip() and not _CJK_RE.search(c)
    ]
    for c in cands:
        if len(c) >= 3 and any(ch.isalpha() for ch in c) and not is_fragment(c):
            return c
    for c in cands:
        if not is_fragment(c):
            return c
    # Every Latin candidate was a fragment — keep the zh title rather than junk.
    return (title or "").strip() or None


def _freeod_range(r) -> dict | None:
    """Convert the extractor's dose value into add_dose's {lower,upper}. A
    {min,max} range maps directly; a bare scalar (a single-value tier) becomes a
    degenerate range so it still classifies."""
    if r is None:
        return None
    if isinstance(r, dict):
        return {"lower": r.get("min"), "upper": r.get("max")}
    return {"lower": r, "upper": r}


# ---------------------------------------------------------------------------
# Schema
# ---------------------------------------------------------------------------

SCHEMA_SQL = r"""
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;

CREATE TABLE sources (
    id                INTEGER PRIMARY KEY,
    slug              TEXT NOT NULL UNIQUE,
    display_name      TEXT NOT NULL,
    description       TEXT,
    default_priority  INTEGER NOT NULL,
    default_enabled   INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE citations (
    id        INTEGER PRIMARY KEY,
    doi       TEXT,
    pmid      INTEGER,
    url       TEXT,
    title     TEXT,
    year      INTEGER,
    authors   TEXT,
    is_review INTEGER DEFAULT 0,
    UNIQUE (doi, pmid, url)
);
CREATE INDEX idx_citations_doi  ON citations(doi)  WHERE doi  IS NOT NULL;
CREATE INDEX idx_citations_pmid ON citations(pmid) WHERE pmid IS NOT NULL;

CREATE TABLE substances (
    id              INTEGER PRIMARY KEY,
    canonical_name  TEXT NOT NULL UNIQUE,
    -- Optional human-facing title override. When set, the app shows this as the
    -- primary name and demotes canonical_name to the subtitle (e.g. show
    -- "2,3-MDMA" with "2,3-Methylenedioxymethamphetamine" beneath). canonical_name
    -- stays the UNIQUE dedup/merge key; only presentation changes. NULL = use canonical.
    display_name    TEXT,
    normalized_name TEXT NOT NULL,
    inchikey        TEXT,
    pubchem_cid     INTEGER,
    cas             TEXT,
    iupac_name      TEXT,
    smiles          TEXT,
    formula         TEXT,
    molecular_weight REAL,
    -- Physicochemical / forensic properties (Workstream 1). NULL = unknown.
    -- Predicted/computed or rodent-assay values, NOT clinical — every populated
    -- value carries its source/citation elsewhere and the app badges them as
    -- forensic (logP/pKa often computed, e.g. PubChem XLogP; LD50 is rodent and
    -- shown order-of-magnitude with species/route, never as a "safe dose").
    -- Columns are added here (Stage 0); the extractors that fill them land in
    -- Stage 1 (extend extract_nps() + widen fetch_pubchem_properties.py).
    logp                  REAL,    -- octanol/water partition coefficient (lipophilicity)
    logd                  REAL,    -- distribution coefficient at physiological pH
    pka                   REAL,    -- acid dissociation constant (primary/most relevant)
    tpsa                  REAL,    -- topological polar surface area (Å²)
    hba                   INTEGER, -- hydrogen-bond acceptor count
    hbd                   INTEGER, -- hydrogen-bond donor count
    ld50_oral_mg_per_kg   REAL,    -- rodent oral LD50 (mg/kg) — order-of-magnitude only
    ld50_dermal_mg_per_kg REAL,    -- rodent dermal LD50 (mg/kg) — order-of-magnitude only
    melting_point_c       REAL,    -- melting point (°C)
    boiling_point_c       REAL,    -- boiling point (°C)
    -- Display-policy classification, baked at build by classify_compounds().
    -- One of: recreational | dual_use | otc | medical_rx | non_recreational.
    -- Gates dose/duration visibility and recreational-browse surfacing in the app.
    display_class       TEXT,
    -- rx | otc | rx_otc_dependent | controlled_schedule_N (parsed from pyrls/medtap).
    regulatory_status   TEXT,
    -- 1 when total duration > 24h (the vitamin problem); OTC durations are
    -- suppressed when set. Recreational/dual-use are exempt (long psychedelics).
    duration_implausible INTEGER NOT NULL DEFAULT 0,
    -- Reproducible popularity score [0,1] from English-Wikipedia pageviews
    -- (data/sources/wikipedia-popularity.json, chemical-verified; applied by
    -- apply_wikipedia_popularity). Drives the "Popularity" sort — recognizable
    -- substances on top, the unmapped long tail at 0. 0 = no chemical article.
    popularity REAL NOT NULL DEFAULT 0,
    -- 1 when this substance carries NO dose_ranges, NO durations, and NO
    -- protocol_dosing rows from any source — a bare catalog stub (mostly medtap
    -- regulatory entries). The app can demote/badge these (cf. Substance.has
    -- NoDoseData). Baked by flag_dose_less_stubs(); 0 = has at least one ladder.
    is_stub INTEGER NOT NULL DEFAULT 0,
    -- Canonical drug.community page slug (slugify of that source's drug_name),
    -- captured during ingest. drug.community's /drug/<slug> page resolves ONLY
    -- the canonical slug (no alias fallback), so the app can't derive a working
    -- link from its own name — it must use this. NULL when the substance has no
    -- drug.community entry. Carried across merges via _merge_into's COALESCE.
    drug_community_slug TEXT,
    -- FreeOD Wiki (freeodwiki.org/药物/<slug>) page slug, captured during
    -- ingest so the app can deep-link the source page (titles are Chinese).
    freeodwiki_slug TEXT
);
CREATE INDEX idx_substances_normalized  ON substances(normalized_name);
CREATE INDEX idx_substances_inchikey    ON substances(inchikey)    WHERE inchikey    IS NOT NULL;
CREATE INDEX idx_substances_pubchem_cid ON substances(pubchem_cid) WHERE pubchem_cid IS NOT NULL;
CREATE INDEX idx_substances_cas         ON substances(cas)         WHERE cas         IS NOT NULL;

CREATE TABLE aliases (
    substance_id     INTEGER NOT NULL REFERENCES substances(id),
    alias            TEXT NOT NULL,
    alias_normalized TEXT NOT NULL,
    source_id        INTEGER REFERENCES sources(id),
    PRIMARY KEY (substance_id, alias)
);
CREATE INDEX idx_aliases_normalized ON aliases(alias_normalized);

CREATE TABLE categories (
    substance_id INTEGER NOT NULL REFERENCES substances(id),
    source_id    INTEGER NOT NULL REFERENCES sources(id),
    category     TEXT NOT NULL,
    confidence   TEXT,
    PRIMARY KEY (substance_id, source_id)
);
CREATE INDEX idx_categories_category ON categories(category);

-- Additional browse homes for a substance, beyond its single resolved primary
-- category. Lets an intentionally cross-class compound surface under more than
-- one family (e.g. Tianeptine under both Antidepressant and Opioid). Curated-
-- only, written from a file's `extraCategories`. The PRIMARY category (card
-- colour/icon, default home) stays the resolved `categories` winner; these are
-- purely additive browse membership. Auto-reassigned on merge via substance_id.
CREATE TABLE browse_extra_categories (
    substance_id INTEGER NOT NULL REFERENCES substances(id),
    category     TEXT NOT NULL,
    PRIMARY KEY (substance_id, category)
);
CREATE INDEX idx_browse_extra_category ON browse_extra_categories(category);

CREATE TABLE tags (
    substance_id INTEGER NOT NULL REFERENCES substances(id),
    tag          TEXT NOT NULL,
    source_id    INTEGER NOT NULL REFERENCES sources(id),
    confidence   TEXT,
    PRIMARY KEY (substance_id, tag, source_id)
);
CREATE INDEX idx_tags_tag       ON tags(tag);
CREATE INDEX idx_tags_substance ON tags(substance_id);

CREATE TABLE dose_ranges (
    id            INTEGER PRIMARY KEY,
    substance_id  INTEGER NOT NULL REFERENCES substances(id),
    route         TEXT NOT NULL,
    source_id     INTEGER NOT NULL REFERENCES sources(id),
    unit          TEXT NOT NULL,
    threshold     REAL,
    light_lower   REAL,
    light_upper   REAL,
    common_lower  REAL,
    common_upper  REAL,
    strong_lower  REAL,
    strong_upper  REAL,
    heavy         REAL,
    notes         TEXT,
    salt_form     TEXT,
    -- Curated default-salt ordering for multi-salt families (0 = the default the
    -- app should pre-select; 1, 2, … = the rest). NULL for single-form / non-salt
    -- rows. Data-driven intent replacing the loader's alphabetical accident; the
    -- loader consumes it in a later workstream (WS-2b) — until then the app still
    -- defaults alphabetically, so this column is forward-looking metadata.
    salt_rank     INTEGER,
    -- Mass fraction of the elemental metal in this salt (e.g. Magnesium Citrate
    -- ≈ 0.16 means 1000 mg of the citrate salt ≈ 160 mg elemental Mg). NULL for
    -- everything that isn't an elemental-mineral salt row. Lets the app surface
    -- "= ⟨elemental⟩ mg elemental Mg" alongside the salt dose.
    elemental_fraction REAL,
    citation_id   INTEGER REFERENCES citations(id),
    UNIQUE (substance_id, route, source_id, salt_form)
);
CREATE INDEX idx_dose_substance_route ON dose_ranges(substance_id, route);

CREATE TABLE durations (
    id            INTEGER PRIMARY KEY,
    substance_id  INTEGER NOT NULL REFERENCES substances(id),
    route         TEXT NOT NULL,
    source_id     INTEGER NOT NULL REFERENCES sources(id),
    phase         TEXT NOT NULL,
    min_minutes   REAL NOT NULL,
    max_minutes   REAL NOT NULL,
    salt_form     TEXT,
    citation_id   INTEGER REFERENCES citations(id),
    UNIQUE (substance_id, route, source_id, phase, salt_form)
);
CREATE INDEX idx_durations_substance_route ON durations(substance_id, route);

-- Release / duration-of-action window for long-acting formulations (depot
-- injections, esters, weekly peptides). Distinct from `durations` (the acute
-- dose-effect curve): days-to-weeks, shown in the drug card, never drawn as an
-- acute timeline curve. Stored normalized to minutes like `durations`.
CREATE TABLE durations_of_action (
    id            INTEGER PRIMARY KEY,
    substance_id  INTEGER NOT NULL REFERENCES substances(id),
    route         TEXT NOT NULL,
    source_id     INTEGER NOT NULL REFERENCES sources(id),
    min_minutes   REAL NOT NULL,
    max_minutes   REAL NOT NULL,
    salt_form     TEXT,
    citation_id   INTEGER REFERENCES citations(id),
    UNIQUE (substance_id, route, source_id, salt_form)
);
CREATE INDEX idx_doa_substance_route ON durations_of_action(substance_id, route);

CREATE TABLE half_lives (
    substance_id      INTEGER NOT NULL REFERENCES substances(id),
    source_id         INTEGER NOT NULL REFERENCES sources(id),
    half_life_minutes REAL NOT NULL,
    notes             TEXT,
    citation_id       INTEGER REFERENCES citations(id),
    PRIMARY KEY (substance_id, source_id)
);

-- Text-bearing tables carry a BCP-47 `language` tag ('en' | 'zh-Hans' |
-- 'zh-Hant' | 'und') and a `machine_translated` flag so the app can resolve
-- text locale-first (a Chinese source wins when the app runs in Chinese) and
-- mark machine-translated prose. All pre-existing sources are English, so the
-- columns default to ('en', 0). `language` is part of mechanisms_summary's PK
-- so one source can hold both a zh original and an en translation.
CREATE TABLE mechanisms_summary (
    substance_id INTEGER NOT NULL REFERENCES substances(id),
    source_id    INTEGER NOT NULL REFERENCES sources(id),
    summary      TEXT NOT NULL,
    description  TEXT,
    language     TEXT NOT NULL DEFAULT 'en',
    machine_translated INTEGER NOT NULL DEFAULT 0,
    citation_id  INTEGER REFERENCES citations(id),
    PRIMARY KEY (substance_id, source_id, language)
);

-- Controlled effect vocabulary (Track 1 of the localization workstream). The
-- high-leverage localization win: instead of translating "Anxiety" once per
-- occurrence across hundreds of substances, there is ONE canonical effect with
-- one translated label set, and every raw effects.text points at it via
-- effects.vocab_id (populated by the Stage 2 fuzzy matcher). Kept as DATA (not a
-- closed Swift enum) so adding an effect ships in the DB with no app rebuild.
-- The canonical set seeds from PsychonautWiki's SEI (English labels + the
-- existing PW effect→category map); FreeODwiki 药效 supplies zh-Hans ~1:1;
-- zh-Hant derives from zh-Hans. Tables added Stage 0 (empty); seeded Stage 2.
CREATE TABLE effect_vocab (
    vocab_id  TEXT PRIMARY KEY,   -- stable slug, e.g. 'anxiety', 'visual_geometry'
    category  TEXT                 -- PsychonautWiki/SEI grouping (joins the PW category map)
);

-- Per-language label for a vocab_id. Row-per-language (mirroring descriptions /
-- effects / mechanisms_summary) so each language carries its own
-- machine_translated flag — zh-Hans from native 药效 is curated (0), zh-Hant
-- OpenCC-converted from zh-Hans is machine (1). The app resolves the label for
-- the current contentLanguage (exact → broader zh → en → und).
CREATE TABLE effect_vocab_labels (
    vocab_id           TEXT NOT NULL REFERENCES effect_vocab(vocab_id),
    language           TEXT NOT NULL,   -- 'en' | 'zh-Hans' | 'zh-Hant' | 'und'
    label              TEXT NOT NULL,
    machine_translated INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (vocab_id, language)
);

CREATE TABLE effects (
    id              INTEGER PRIMARY KEY,
    substance_id    INTEGER NOT NULL REFERENCES substances(id),
    source_id       INTEGER NOT NULL REFERENCES sources(id),
    text            TEXT NOT NULL,
    kind            TEXT,
    effect_category TEXT,
    language        TEXT NOT NULL DEFAULT 'en',
    machine_translated INTEGER NOT NULL DEFAULT 0,
    -- Controlled-vocabulary reference (Track 1). When the build-time fuzzy
    -- matcher (Stage 2) maps this raw `text` to a canonical effect_vocab entry,
    -- it records the slug here; the app then renders the localized vocab label
    -- for the current UI language for EVERY substance, even English-only-source
    -- ones. NULL when no match clears the threshold — `text` stays the raw
    -- fallback (no-silent-caps). Column added Stage 0; matcher populates Stage 2.
    vocab_id        TEXT REFERENCES effect_vocab(vocab_id),
    citation_id     INTEGER REFERENCES citations(id)
);
CREATE INDEX idx_effects_substance ON effects(substance_id);
CREATE INDEX idx_effects_vocab     ON effects(vocab_id) WHERE vocab_id IS NOT NULL;

CREATE TABLE subjective_effects (
    id           INTEGER PRIMARY KEY,
    substance_id INTEGER NOT NULL REFERENCES substances(id),
    source_id    INTEGER NOT NULL REFERENCES sources(id),
    name         TEXT NOT NULL,
    description  TEXT,
    language     TEXT NOT NULL DEFAULT 'en',
    machine_translated INTEGER NOT NULL DEFAULT 0,
    citation_id  INTEGER REFERENCES citations(id)
);
CREATE INDEX idx_subjective_substance ON subjective_effects(substance_id);

-- Long-form substance overview prose ("what it is / history / risk profile"),
-- distinct from mechanisms_summary (pharmacology). Currently fed only by
-- FreeOD Wiki; the app shows it in an "Overview" section, locale-first.
CREATE TABLE descriptions (
    id           INTEGER PRIMARY KEY,
    substance_id INTEGER NOT NULL REFERENCES substances(id),
    source_id    INTEGER NOT NULL REFERENCES sources(id),
    text         TEXT NOT NULL,
    language     TEXT NOT NULL DEFAULT 'en',
    machine_translated INTEGER NOT NULL DEFAULT 0,
    citation_id  INTEGER REFERENCES citations(id),
    UNIQUE (substance_id, source_id, language)
);
CREATE INDEX idx_descriptions_substance ON descriptions(substance_id);

CREATE TABLE tolerance (
    substance_id    INTEGER NOT NULL REFERENCES substances(id),
    source_id       INTEGER NOT NULL REFERENCES sources(id),
    half_life_days  REAL,
    full_reset_days REAL,
    build_rate      TEXT,
    notes           TEXT,
    citation_id     INTEGER REFERENCES citations(id),
    PRIMARY KEY (substance_id, source_id)
);

CREATE TABLE bindings (
    id                     INTEGER PRIMARY KEY,
    substance_id           INTEGER NOT NULL REFERENCES substances(id),
    target                 TEXT NOT NULL,
    action                 TEXT NOT NULL,
    ki_nm                  REAL,
    ki_ci_lower_nm         REAL,
    ki_ci_upper_nm         REAL,
    kd_nm                  REAL,
    ec50_nm                REAL,
    ic50_nm                REAL,
    emax_pct               REAL,
    intrinsic_activity_pct REAL,
    reference_agonist      TEXT,
    species                TEXT,
    tissue_or_cell         TEXT,
    radioligand            TEXT,
    assay_notes            TEXT,
    source_id              INTEGER NOT NULL REFERENCES sources(id),
    citation_id            INTEGER REFERENCES citations(id),
    is_review              INTEGER DEFAULT 0,
    notes                  TEXT
);
CREATE INDEX idx_bindings_target           ON bindings(target);
CREATE INDEX idx_bindings_target_ki        ON bindings(target, ki_nm);
CREATE INDEX idx_bindings_substance_target ON bindings(substance_id, target);
CREATE INDEX idx_bindings_substance        ON bindings(substance_id);

CREATE TABLE functional_assays (
    id                INTEGER PRIMARY KEY,
    substance_id      INTEGER NOT NULL REFERENCES substances(id),
    target            TEXT NOT NULL,
    readout           TEXT NOT NULL,
    ec50_nm           REAL,
    ic50_nm           REAL,
    emax_pct          REAL,
    reference_agonist TEXT,
    species           TEXT,
    cell_system       TEXT,
    source_id         INTEGER NOT NULL REFERENCES sources(id),
    citation_id       INTEGER REFERENCES citations(id),
    notes             TEXT
);
CREATE INDEX idx_functional_target    ON functional_assays(target);
CREATE INDEX idx_functional_substance ON functional_assays(substance_id);

CREATE TABLE biased_agonism (
    id                       INTEGER PRIMARY KEY,
    substance_id             INTEGER NOT NULL REFERENCES substances(id),
    target                   TEXT NOT NULL,
    pathways_compared        TEXT NOT NULL,
    bias_factor_log          REAL,
    bias_reference_compound  TEXT,
    interpretation           TEXT,
    source_id                INTEGER NOT NULL REFERENCES sources(id),
    citation_id              INTEGER REFERENCES citations(id)
);
CREATE INDEX idx_biased_target    ON biased_agonism(target);
CREATE INDEX idx_biased_substance ON biased_agonism(substance_id);

CREATE TABLE receptor_oligomers (
    id                      INTEGER PRIMARY KEY,
    substance_id            INTEGER NOT NULL REFERENCES substances(id),
    complex_description     TEXT NOT NULL,
    evidence_type           TEXT,
    functional_consequence  TEXT,
    source_id               INTEGER NOT NULL REFERENCES sources(id),
    citation_id             INTEGER REFERENCES citations(id)
);

CREATE TABLE downstream_signalling (
    substance_id INTEGER NOT NULL REFERENCES substances(id),
    source_id    INTEGER NOT NULL REFERENCES sources(id),
    summary      TEXT NOT NULL,
    citation_id  INTEGER REFERENCES citations(id),
    PRIMARY KEY (substance_id, source_id)
);

CREATE TABLE neuroimaging (
    id            INTEGER PRIMARY KEY,
    substance_id  INTEGER NOT NULL REFERENCES substances(id),
    modality      TEXT NOT NULL,
    finding       TEXT NOT NULL,
    source_id     INTEGER NOT NULL REFERENCES sources(id),
    citation_id   INTEGER REFERENCES citations(id)
);

CREATE TABLE pk_routes (
    id                          INTEGER PRIMARY KEY,
    substance_id                INTEGER NOT NULL REFERENCES substances(id),
    route                       TEXT NOT NULL,
    source_id                   INTEGER NOT NULL REFERENCES sources(id),
    bioavailability_pct         REAL,
    cmax_ng_per_ml              REAL,
    tmax_min                    REAL,
    auc_0_inf_ng_h_per_ml       REAL,
    half_life_min               REAL,
    vd_l_per_kg                 REAL,
    clearance_ml_per_min_per_kg REAL,
    protein_binding_pct         REAL,
    dose_in_study_mg            REAL,
    subject_n                   INTEGER,
    demographics                TEXT,
    citation_id                 INTEGER REFERENCES citations(id),
    notes                       TEXT
);
CREATE INDEX idx_pk_substance_route ON pk_routes(substance_id, route);

CREATE TABLE concentration_effects (
    id                  INTEGER PRIMARY KEY,
    substance_id        INTEGER NOT NULL REFERENCES substances(id),
    source_id           INTEGER NOT NULL REFERENCES sources(id),
    effect              TEXT NOT NULL,
    concentration_unit  TEXT NOT NULL,
    threshold           REAL,
    peak_effect         REAL,
    citation_id         INTEGER REFERENCES citations(id)
);

CREATE TABLE metabolism (
    id                               INTEGER PRIMARY KEY,
    substance_id                     INTEGER NOT NULL REFERENCES substances(id),
    source_id                        INTEGER NOT NULL REFERENCES sources(id),
    enzyme                           TEXT NOT NULL,
    fraction_of_clearance_pct        REAL,
    metabolite_name                  TEXT,
    metabolite_active                INTEGER,
    metabolite_potency_vs_parent_pct REAL,
    citation_id                      INTEGER REFERENCES citations(id),
    notes                            TEXT
);
CREATE INDEX idx_metabolism_enzyme    ON metabolism(enzyme);
CREATE INDEX idx_metabolism_substance ON metabolism(substance_id);

CREATE TABLE drug_interactions_pk (
    id              INTEGER PRIMARY KEY,
    substance_id    INTEGER NOT NULL REFERENCES substances(id),
    with_substance  TEXT NOT NULL,
    mechanism       TEXT,
    ki_um           REAL,
    clinical_effect TEXT,
    source_id       INTEGER NOT NULL REFERENCES sources(id),
    citation_id     INTEGER REFERENCES citations(id)
);
CREATE INDEX idx_ddi_substance ON drug_interactions_pk(substance_id);

CREATE TABLE pharmacogenetics (
    id                INTEGER PRIMARY KEY,
    substance_id      INTEGER NOT NULL REFERENCES substances(id),
    gene              TEXT NOT NULL,
    phenotype_effects TEXT NOT NULL,
    source_id         INTEGER NOT NULL REFERENCES sources(id),
    citation_id       INTEGER REFERENCES citations(id)
);
CREATE INDEX idx_pgx_gene ON pharmacogenetics(gene);

CREATE TABLE off_targets (
    id                    INTEGER PRIMARY KEY,
    substance_id          INTEGER NOT NULL REFERENCES substances(id),
    target                TEXT NOT NULL,
    ki_or_ic50_nm         REAL,
    concern_level         TEXT,
    clinical_consequence  TEXT,
    source_id             INTEGER NOT NULL REFERENCES sources(id),
    citation_id           INTEGER REFERENCES citations(id)
);
CREATE INDEX idx_offtargets_target ON off_targets(target);

CREATE TABLE class_contexts (
    id                INTEGER PRIMARY KEY,
    slug              TEXT NOT NULL UNIQUE,
    display_name      TEXT NOT NULL,
    shared_mechanism  TEXT,
    shared_pk         TEXT,
    shared_safety     TEXT,
    sar_summary       TEXT,
    source_id         INTEGER REFERENCES sources(id)
);

CREATE TABLE substance_classes (
    substance_id      INTEGER NOT NULL REFERENCES substances(id),
    class_context_id  INTEGER NOT NULL REFERENCES class_contexts(id),
    PRIMARY KEY (substance_id, class_context_id)
);

CREATE TABLE class_citations (
    class_context_id INTEGER NOT NULL REFERENCES class_contexts(id),
    citation_id      INTEGER NOT NULL REFERENCES citations(id),
    PRIMARY KEY (class_context_id, citation_id)
);

CREATE TABLE interaction_rules (
    id           INTEGER PRIMARY KEY,
    class_a      TEXT NOT NULL,
    class_b      TEXT NOT NULL,
    severity     TEXT NOT NULL,
    note         TEXT NOT NULL,
    source_id    INTEGER REFERENCES sources(id),
    citation_id  INTEGER REFERENCES citations(id),
    UNIQUE (class_a, class_b)
);

CREATE TABLE indications (
    id           INTEGER PRIMARY KEY,
    substance_id INTEGER NOT NULL REFERENCES substances(id),
    source_id    INTEGER NOT NULL REFERENCES sources(id),
    text         TEXT NOT NULL,
    UNIQUE (substance_id, source_id, text)
);
CREATE INDEX idx_indications_substance ON indications(substance_id);

CREATE TABLE contraindications (
    id               INTEGER PRIMARY KEY,
    substance_id     INTEGER NOT NULL REFERENCES substances(id),
    source_id        INTEGER NOT NULL REFERENCES sources(id),
    text             TEXT NOT NULL,
    is_boxed_warning INTEGER NOT NULL DEFAULT 0,
    UNIQUE (substance_id, source_id, text)
);
CREATE INDEX idx_contraindications_substance ON contraindications(substance_id);

CREATE TABLE diazepam_equivalents (
    substance_id          INTEGER NOT NULL REFERENCES substances(id),
    source_id             INTEGER NOT NULL REFERENCES sources(id),
    dose_mg               REAL,
    equivalent_diazepam_mg REAL,
    display_text          TEXT,
    PRIMARY KEY (substance_id, source_id)
);

-- Peptide/biologic-specific reference data (1:1 with a substance). Presence of
-- a row switches the iOS detail view to a peptide presentation (sequence /
-- handling / reconstitution) instead of the psychoactive trip model.
CREATE TABLE peptide_profiles (
    substance_id                 INTEGER PRIMARY KEY REFERENCES substances(id),
    source_id                    INTEGER REFERENCES sources(id),
    sequence                     TEXT,
    -- SuppliedForm raw value: lyophilized_vial | solution | topical | implant | oral_capsule
    supplied_form                TEXT,
    typical_vial_mg              REAL,
    reconstitution_solvent       TEXT,
    -- StorageRequirement.Temperature raw value: room_temp | refrigerate | freeze
    storage_temperature          TEXT,
    storage_light_sensitive      INTEGER NOT NULL DEFAULT 0,
    reconstituted_stability_days REAL,
    iu_per_mg                    REAL
);

-- Clinical-protocol dosing (peptides / some Rx) — a schedule, not a trip ladder.
-- Amounts are in `unit`. Titration ramp is stored as a JSON array of
-- {amount, label} for the app to decode. Replaces the DoseRange ladder in the UI.
CREATE TABLE protocol_dosing (
    id              INTEGER PRIMARY KEY,
    substance_id    INTEGER NOT NULL REFERENCES substances(id),
    route           TEXT NOT NULL,
    source_id       INTEGER NOT NULL REFERENCES sources(id),
    unit            TEXT,
    low_amount      REAL,
    high_amount     REAL,
    frequency       TEXT NOT NULL,
    titration_json  TEXT,
    course_duration TEXT,
    notes           TEXT,
    salt_form       TEXT,
    citation_id     INTEGER REFERENCES citations(id),
    UNIQUE (substance_id, route, source_id, salt_form)
);
CREATE INDEX idx_protocol_substance_route ON protocol_dosing(substance_id, route);

-- Substance-level primary references (the curated `sources` array): DOIs, PMIDs,
-- URLs, or free-text labels ("Egrifta SmPC"). Surfaced in the app as tappable
-- References. Per-fact citations live in each fact table's citation_id; this is
-- the home for whole-compound provenance.
CREATE TABLE substance_citations (
    substance_id INTEGER NOT NULL REFERENCES substances(id),
    citation_id  INTEGER NOT NULL REFERENCES citations(id),
    PRIMARY KEY (substance_id, citation_id)
);
CREATE INDEX idx_substance_citations_substance ON substance_citations(substance_id);

CREATE TABLE manifest (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
"""


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


# Controlled salt-form vocabulary. Folding tags dose rows with these labels; the
# canonicaliser trims whitespace and maps case-/spelling-variants back to the one
# blessed spelling so the app sees a stable, deduplicated salt picker. Keep the
# values byte-identical to what SaltFormTests asserts ("Citrate", "Glycinate",
# "L-Threonate", "Carbonate", "Orotate") — never rename them here.
_SALT_FORM_CANON: dict[str, str] = {
    "citrate": "Citrate",
    "glycinate": "Glycinate",
    "bisglycinate": "Glycinate",
    "l-threonate": "L-Threonate",
    "threonate": "L-Threonate",
    "carbonate": "Carbonate",
    "orotate": "Orotate",
    "hydroxide": "Hydroxide",
}


def canonical_salt_form(label: str | None) -> str | None:
    """Trim/canonicalise a salt label to the controlled vocabulary.

    Unknown labels pass through trimmed (we never *drop* a salt tag), so a future
    family works before its entry is added here — but the known forms collapse to
    one blessed spelling so the picker never shows 'glycinate' and 'Glycinate' as
    two options. Idempotent: canonical_salt_form(canonical_salt_form(x)) == it."""
    if label is None:
        return None
    trimmed = label.strip()
    if not trimmed:
        return None
    return _SALT_FORM_CANON.get(trimmed.lower(), trimmed)


def dc_slugify(name: str) -> str:
    """drug.community's page-slug function: lowercase, runs of non-alphanumeric
    characters collapsed to a single '-', leading/trailing '-' trimmed. Must
    match the site's ``Kt`` exactly — its /drug/<slug> route resolves only this
    canonical form."""
    return re.sub(r"(^-|-$)", "", re.sub(r"[^a-z0-9]+", "-", (name or "").lower()))


PUBCHEM_PROPERTIES = REPO / "data/sources/pubchem-properties.json"
PUBCHEM_PROPERTIES_BY_INCHIKEY = REPO / "data/sources/pubchem-properties-by-inchikey.json"
PUBCHEM_CIDS = REPO / "data/sources/pubchem-cids.json"
IDENTIFIER_RECONCILE = REPO / "data/sources/identifier-corrections.json"
IDENTIFIER_RECONCILE_MANUAL = REPO / "data/sources/identifier-corrections-manual.json"
WIKIPEDIA_POPULARITY = REPO / "data/sources/wikipedia-popularity.json"


def apply_wikipedia_popularity(con, data: dict) -> int:
    """Set `popularity` from the reproducible Wikipedia-pageviews snapshot
    (``data/sources/wikipedia-popularity.json``), keyed by canonical_name. This
    is the authoritative popularity source — it supersedes any hand-set curated
    value so the "by popularity" sort is fully reproducible. Substances absent
    from the snapshot (no chemical Wikipedia article) keep popularity 0."""
    cur = con.cursor()
    n = 0
    for name, entry in data.items():
        score = entry.get("score")
        if score is None:
            continue
        cur.execute(
            "UPDATE substances SET popularity = ? WHERE canonical_name = ?", (float(score), name)
        )
        n += cur.rowcount
    con.commit()
    return n


# Elements a real pharmaceutical counter-ion / desalt leftover may contain
# (HCl, HBr, HI, H2SO4, H3PO4, tartrate/citrate/fumarate/maleate/mesylate, Na/K).
# Notably NOT nitrogen — no common counter-ion carries N, so a "free base" that
# drops nitrogen vs its "salt" is a wrong CID, not a desalt.
_COUNTERION_ELEMENTS = frozenset({"H", "C", "O", "S", "Cl", "Br", "I", "P", "Na", "K"})


def parse_formula(formula: str | None) -> dict[str, int] | None:
    """Parse a Hill-notation molecular formula into an element→count map.
    ``None`` / empty → ``None``. Charge suffixes ("+"/"-") are ignored."""
    if not formula:
        return None
    out: dict[str, int] = {}
    for el, ct in re.findall(r"([A-Z][a-z]?)(\d*)", formula):
        if not el:
            continue
        out[el] = out.get(el, 0) + (int(ct) if ct else 1)
    return out or None


def is_clean_desalt(freebase: str | None, salt: str | None) -> bool:
    """True when ``freebase`` is plausibly the salt-free form of ``salt`` — i.e.
    ``salt`` = k·``freebase`` + a nitrogen-free counter-ion, for a small base:acid
    ratio k. Guards the PubChem-by-CID override against wrong CIDs (a CID that
    points at an unrelated compound, e.g. VIP→C32H44O7 or a peptide→K-salt
    fragment): such a "free base" loses nitrogen or introduces foreign elements,
    which a genuine desalt never does. Structural halogens (2C-B's Br, 2C-C's
    ring Cl) are preserved because they appear in both formulae."""
    new = parse_formula(freebase)
    old = parse_formula(salt)
    if not new or not old or new == old:
        return False
    if new.get("N", 0) < 1:  # drugs keep their nitrogen; all-N-loss ⇒ wrong CID
        return False
    for k in (1, 2, 3):
        scaled = {el: c * k for el, c in new.items()}
        if any(scaled.get(el, 0) > old.get(el, 0) for el in set(old) | set(scaled)):
            continue  # k·freebase isn't contained in the salt
        remainder = {el: old.get(el, 0) - scaled.get(el, 0) for el in set(old) | set(scaled)}
        if remainder.get("N", 0) != 0 or remainder.get("P", 0) != 0:
            continue  # a counter-ion never carries N/P
        if any(c > 0 and el not in _COUNTERION_ELEMENTS for el, c in remainder.items()):
            continue  # leftover has a non-counter-ion element ⇒ not a desalt
        return True
    return False


# Verified-wrong chemical identifiers carried in from upstream sources, keyed by
# canonical_name. Resolved against PubChem by compound name + InChIKey audit
# (a stored CID/InChIKey whose structure doesn't match the compound). `cid: None`
# nulls an unresolvable wrong CID rather than keep it pointing at the wrong thing.
IDENTIFIER_CORRECTIONS: dict[str, dict] = {
    # Wrong CID (the stored CID pointed at an unrelated compound):
    "Diphenidine": {"cid": 206666},
    "Ephenidine": {"cid": 110821},
    "Methoxphenidine": {"cid": 67833251},
    "Dermorphin": {"cid": 5485199},
    "GHK": {"cid": 73587},
    "Argireline": {"cid": 71587772},
    "SS-31": {"cid": 11764719},  # elamipretide
    "AOD-9604": {"cid": 71300630},
    "VIP": {"cid": None},  # no PubChem match for the peptide — drop the wrong CID
    # Wrong InChIKey (CID was correct — the stored key belonged to another molecule,
    # e.g. MDA carried amphetamine's key):
    "MDA": {"inchikey": "NGBBVGZWCFBOGO-UHFFFAOYSA-N"},
    "Tropacocaine": {"inchikey": "XQJMXPAEFMWDOZ-UHFFFAOYSA-N"},
    "25CN-NBOH": {"inchikey": "VWEDZTZAXHMZIL-UHFFFAOYSA-N"},
}


def apply_identifier_reconciliation(con, mapping: dict) -> dict:
    """Apply PubChem-authoritative InChIKey/SMILES corrections from the
    ``data/sources/identifier-corrections.json`` snapshot (refresh via
    ``reconcile_identifiers_pubchem.py``). Keyed by canonical_name; each entry
    carries whichever field PubChem found wrong — ``inchikey`` and/or ``smiles``.

    The catalog's identifiers are corrupt in both directions (LLM-fabricated keys
    in enrichment; wrong-regioisomer SMILES in the NPS vendor dump), so the fix
    can't trust either field as the oracle. The snapshot only contains
    corrections PubChem corroborated against exactly one existing DB signal, so
    each names the field that was wrong. Runs after dedup (canonical_name matches
    the snapshot's basis) and **before** ``apply_pubchem_cids`` so CID resolution
    keys off the corrected InChIKey. Returns per-field change counts."""
    if not mapping:
        return {"inchikey": 0, "smiles": 0}
    cur = con.cursor()
    res = {"inchikey": 0, "smiles": 0, "cas": 0}
    for name, fix in mapping.items():
        if fix.get("inchikey"):
            cur.execute(
                "UPDATE substances SET inchikey = ? WHERE canonical_name = ? AND inchikey IS NOT ?",
                (fix["inchikey"], name, fix["inchikey"]),
            )
            res["inchikey"] += cur.rowcount
        if fix.get("smiles"):
            cur.execute(
                "UPDATE substances SET smiles = ? WHERE canonical_name = ? AND smiles IS NOT ?",
                (fix["smiles"], name, fix["smiles"]),
            )
            res["smiles"] += cur.rowcount
        if fix.get("cas"):
            cur.execute(
                "UPDATE substances SET cas = ? WHERE canonical_name = ? AND cas IS NOT ?",
                (fix["cas"], name, fix["cas"]),
            )
            res["cas"] += cur.rowcount
    con.commit()
    return res


def apply_pubchem_cids(con, mapping: dict) -> dict:
    """Fill ``pubchem_cid`` for substances that have an InChIKey but no CID,
    keyed by InChIKey from the ``data/sources/pubchem-cids.json`` snapshot
    (``{inchikey: {cid, formula}}``; refresh via ``fetch_pubchem_cids.py``).

    The CID was resolved *from* the substance's own InChIKey, so it is
    CID↔InChIKey-consistent by construction. **But that only helps if the stored
    InChIKey is itself right** — a slice of upstream keys are corrupt (point at an
    unrelated compound), so a faithful resolve yields a wrong CID. Guard exactly
    like ``apply_pubchem_freebase``: accept the CID only when PubChem's formula
    for it matches the substance's stored formula (equal, or a clean salt→free-
    base desalt). A corrupt key fails this because its stored formula is right
    while the wrong-CID formula differs and isn't a salt of it. When the stored
    formula is NULL we can't verify, so we skip (a wrong CID is worse than none).

    COALESCE-only: never overwrites an existing CID (those are audited/curated).
    Runs before ``apply_identifier_corrections`` so a known-wrong resolved CID can
    still be corrected, and before ``apply_pubchem_freebase`` so the verified CID
    drives the formula lookup. Returns counts + the rejected (mismatch) list."""
    if not mapping:
        return {"filled": 0, "skipped_unverifiable": 0, "rejected": []}
    cur = con.cursor()
    by_ik = {
        ik: row[0]
        for ik, row in (
            (
                ik,
                cur.execute(
                    "SELECT formula FROM substances WHERE inchikey = ? AND pubchem_cid IS NULL",
                    (ik,),
                ).fetchone(),
            )
            for ik in mapping
        )
        if row is not None
    }
    filled = skipped = 0
    rejected: list[str] = []
    for ik, entry in mapping.items():
        if ik not in by_ik:
            continue  # no NULL-CID substance carries this key
        cid = entry["cid"] if isinstance(entry, dict) else entry
        pubchem_formula = entry.get("formula") if isinstance(entry, dict) else None
        stored_formula = by_ik[ik]
        if stored_formula is None:
            skipped += 1
            continue
        if not (
            parse_formula(pubchem_formula) == parse_formula(stored_formula)
            or is_clean_desalt(pubchem_formula, stored_formula)
        ):
            rejected.append(f"{ik} cid={cid} stored={stored_formula} pubchem={pubchem_formula}")
            continue
        cur.execute(
            "UPDATE substances SET pubchem_cid = ? WHERE inchikey = ? AND pubchem_cid IS NULL",
            (cid, ik),
        )
        filled += cur.rowcount
    con.commit()
    return {"filled": filled, "skipped_unverifiable": skipped, "rejected": rejected}


def apply_identifier_corrections(con, props: dict | None = None) -> dict:
    """Overwrite verified-wrong pubchem_cid / inchikey values (see
    ``IDENTIFIER_CORRECTIONS``). Runs before ``apply_pubchem_freebase`` so the
    corrected CID drives the free-base formula lookup. When ``props`` (the
    PubChem snapshot) is given, a CID correction also adopts that CID's
    formula/MW — the CID was hand-verified, so PubChem is authoritative (fixes
    stale stored formulae the desalt guard would otherwise refuse). Returns
    {name: change}."""
    cur = con.cursor()
    changed: dict[str, str] = {}
    for name, fix in IDENTIFIER_CORRECTIONS.items():
        row = cur.execute(
            "SELECT id, pubchem_cid, inchikey FROM substances WHERE canonical_name = ?", (name,)
        ).fetchone()
        if not row:
            continue
        sid, old_cid, old_ik = row
        if "cid" in fix and fix["cid"] != old_cid:
            cur.execute("UPDATE substances SET pubchem_cid = ? WHERE id = ?", (fix["cid"], sid))
            changed[name] = f"cid {old_cid}→{fix['cid']}"
            prop = (props or {}).get(str(fix["cid"])) if fix["cid"] is not None else None
            if prop and prop.get("formula"):
                cur.execute(
                    "UPDATE substances SET formula = ?, molecular_weight = ? WHERE id = ?",
                    (prop["formula"], prop.get("molecular_weight"), sid),
                )
                changed[name] += f", formula→{prop['formula']}"
        if "inchikey" in fix and fix["inchikey"] != old_ik:
            cur.execute("UPDATE substances SET inchikey = ? WHERE id = ?", (fix["inchikey"], sid))
            changed[name] = (
                changed.get(name, "") + f" inchikey {old_ik}→{fix['inchikey']}"
            ).strip()
    con.commit()
    return changed


def apply_pubchem_freebase(con, props: dict) -> dict:
    """Set ``formula``/``molecular_weight`` from PubChem, keyed by ``pubchem_cid``.

    The identifier audit corrected every CID↔InChIKey mismatch, so **a substance
    that has both a CID and an InChIKey has a verified-consistent structure** —
    PubChem's formula/MW for that CID is authoritative. One rule then covers fill
    (was null), desalt (salt→free base), and stale-formula fix.

    A substance with a CID but **no InChIKey** can't be verified that way, so it
    stays conservative: apply only a clean desalt (``is_clean_desalt``); never
    fill from an unverifiable CID (some are wrong — GHK→C30H50, peptide→fragment)."""
    cur = con.cursor()
    rows = cur.execute(
        "SELECT id, canonical_name, pubchem_cid, formula, molecular_weight, inchikey "
        "FROM substances WHERE pubchem_cid IS NOT NULL"
    ).fetchall()
    trusted: list[str] = []  # CID verified by InChIKey → PubChem wins
    desalted: list[str] = []  # no InChIKey → clean desalt only
    flagged: list[str] = []
    unverified_no_formula = 0

    def write(sid, formula, mw):
        cur.execute(
            "UPDATE substances SET formula = ?, molecular_weight = ? WHERE id = ?",
            (formula, mw, sid),
        )

    for sid, name, cid, formula, _mw, inchikey in rows:
        prop = props.get(str(cid))
        if not prop or not prop.get("formula"):
            continue
        new_formula, new_mw = prop["formula"], prop.get("molecular_weight")
        if parse_formula(new_formula) == parse_formula(formula):
            continue  # already correct
        if inchikey:
            write(sid, new_formula, new_mw)
            trusted.append(name)
        elif formula is None:
            unverified_no_formula += 1  # can't verify an unmatched CID — leave null
        elif is_clean_desalt(new_formula, formula):
            write(sid, new_formula, new_mw)
            desalted.append(name)
        else:
            flagged.append(f"{name}({cid}): {formula}→{new_formula}")
    con.commit()
    return {
        "trusted": len(trusted),
        "desalted": len(desalted),
        "flagged": flagged,
        "unverified_no_formula": unverified_no_formula,
        "names": sorted(trusted + desalted),
    }


def apply_pubchem_computed(con, props: dict, ik_props: dict | None = None) -> dict:
    """Set computed physicochemical descriptors (``logp``/``tpsa``/``hba``/``hbd``)
    from PubChem.

    PubChem computes XLogP3/TPSA/H-bond counts by a single consistent method, so
    these supersede NPS-DataHub's mixed-provenance values wherever the structure
    is trusted. Two trusted paths:

    1. ``props`` keyed by ``pubchem_cid`` — applied where a CID is also
       InChIKey-verified (same gate as ``apply_pubchem_freebase``). An unverified
       CID is skipped: if the structure can't be trusted, neither can a descriptor
       computed from it — NPS's own value (from ``ingest_nps``) stands.
    2. ``ik_props`` keyed by ``inchikey`` — for substances with an InChIKey but no
       CID (codeine, many NPS analogues). The InChIKey *is* the structure, so
       descriptors fetched by it are unambiguously the right molecule.

    NPS retains the columns PubChem doesn't supply (``logd``/``pka``/LD50/melting/
    boiling point). All values are predicted/computed, never measured — forensic."""
    cur = con.cursor()
    # (column, prop-key) — only descriptors PubChem computes consistently.
    fields = [("logp", "xlogp"), ("tpsa", "tpsa"), ("hba", "hba"), ("hbd", "hbd")]
    applied = {col: 0 for col, _ in fields}

    def write(sid: int, prop: dict) -> None:
        sets, vals = [], []
        for col, key in fields:
            v = prop.get(key)
            if v is None:
                continue
            sets.append(f"{col} = ?")
            vals.append(v)
            applied[col] += 1
        if not sets:
            return
        vals.append(sid)
        cur.execute(f"UPDATE substances SET {', '.join(sets)} WHERE id = ?", vals)

    for sid, cid in cur.execute(
        "SELECT id, pubchem_cid FROM substances "
        "WHERE pubchem_cid IS NOT NULL AND inchikey IS NOT NULL"
    ).fetchall():
        prop = props.get(str(cid))
        if prop:
            write(sid, prop)

    if ik_props:
        for sid, ik in cur.execute(
            "SELECT id, inchikey FROM substances WHERE inchikey IS NOT NULL AND pubchem_cid IS NULL"
        ).fetchall():
            prop = ik_props.get(ik)
            if prop:
                write(sid, prop)

    con.commit()
    return applied


def normalise(s: str) -> str:
    s = unicodedata.normalize("NFKD", s or "").lower().strip()
    s = re.sub(r"^\(\s*[+\-±rs]\s*\)\s*-?\s*", "", s)
    s = re.sub(
        r"\s*[·.]?\s*(hcl|hydrochloride|sulfate|sulphate|fumarate|tartrate|maleate|mesylate|citrate|hbr|hydrobromide)\s*$",
        "",
        s,
    )
    s = re.sub(r"\s+", " ", s)
    return s


# Stereo/IUPAC prefixes that mark a name as a chemistry-noise variant.
# e.g. "(+/-)-noradrenaline", "(R)-N-trans-feruloyloctopamine",
# "(E,E)-bastadin 19", "(2E)-3-(...)", "(2R)-1-(3-chlorophenyl)-...",
# "(−)-cathinone" (U+2212 minus), "(±)-adrenaline".
_CHEM_NOISE_PREFIX = re.compile(
    r"^\(\s*[+\-±−/RrSsEeZz0-9, ]+\s*\)\s*-",
)
# Square-bracket / fully-IUPAC body patterns.
_CHEM_NOISE_BODY = re.compile(r"[\[\]]")

# Salt/descriptor suffixes that make an alias a redundant chemistry variant
# rather than a name anyone searches by ("Lisdexamfetamine dimesylate",
# "… freebase", "Dextroamphetamine prodrug"). `normalise()` already strips a
# few salts for *dedup*, but these survive as separately-displayed aliases, so
# we drop them outright from the alias list.
_ALIAS_SALT_SUFFIX = re.compile(
    r"\b(free\s*base|hydrochlorides?|dihydrochloride|hydrobromide|hbr|hcl|"
    r"di?mesylate|besylate|sulfates?|sulphates?|bisulfate|fumarate|"
    r"hemifumarate|tartrate|bitartrate|maleate|malate|citrate|phosphate|"
    r"acetate|oxalate|succinate|lactate|napsylate|pamoate|prodrug)\s*$",
    re.IGNORECASE,
)


def is_chemnoise_alias(alias: str) -> bool:
    """True for aliases that are systematic/IUPAC chemistry noise rather than a
    common name, brand, or short code. Drops salt forms ("… dimesylate"),
    stereo-prefixed and bracketed IUPAC names ("(R)-…", "…[…]…"), parenthetical
    locant names ("1-(2,5-dimethoxybenzyl)…"), and long multi-locant systematic
    strings ("L-lysine-d-amphetamine"). Keeps brands (Vyvanse) and short codes
    (LDX, 2,5-DMBZP, 2,3-MDMA, 5-MeO-DMT)."""
    a = (alias or "").strip()
    if not a:
        return False
    if _ALIAS_SALT_SUFFIX.search(a):
        return True
    if _CHEM_NOISE_PREFIX.match(a) or _CHEM_NOISE_BODY.search(a):
        return True
    if re.search(r"\(\s*\d", a):  # parenthetical locant: "(2,5-", "(1-"
        return True
    # long multi-locant systematic name
    return a.count("-") >= 3 and len(a) > 16


# Display-name overrides, popularity scores, category corrections, peptide
# enrichment, and CJK aliases used to live in separate data/curated/*.json files
# and in-module dicts. They are now folded into each compound's own
# data/curated/substances/<slug>.json (display-name override, popularity,
# category, aliases incl. CJK, dose overrides, peptideProfile, protocol dosing)
# and ingested by ingest_curated_substances(). One file fully describes one
# substance; the build has a single curated source.


# Three-letter+ acronyms that should be ALL CAPS even after title-casing.
# Used by `smart_title_case` to handle entries that arrived all-lowercase
# from drug.community / TripSit but represent acronyms (lsd, mdma, gbl).
_ACRONYMS = {
    "lsd",
    "mdma",
    "mda",
    "mde",
    "dmt",
    "dxm",
    "pcp",
    "mxe",
    "thc",
    "cbd",
    "cbn",
    "cbg",
    "cbc",
    "cbdv",
    "thcv",
    "thcp",
    "hhc",
    "gbl",
    "ghb",
    "gaba",
    "maoi",
    "ssri",
    "snri",
    "ndri",
    "sari",
    "lsa",
    "lsh",
    "amt",
    "aet",
    "dpt",
    "dipt",
    "mipt",
    "dmd",
    "nbome",
    "nboh",
    "nbmd",
    "nbf",
    "pmma",
    "pma",
    "mbdb",
    "tfmpp",
    "mcpp",
    "5-meo",
    "4-aco",
    "4-ho",
    "5-ho",
    "5-ht",
    "4-fa",
    "4-ma",
    "2c",
    "25i",
    "25c",
    "25b",
    "25h",
    "25n",
    "iv",
    "im",
    "po",
    "sl",
    "br",
    "us",
    "uk",
    "eu",
}


# Canonical-name fixups for scraped sources that mislabel a compound — keyed by
# normalised incoming name. The Swift web collector names some TripSit entries
# from the dataset *key* rather than its `pretty_name`, so paracetamol arrived as
# "apap" (the US clinical abbreviation, not a name people search). Remapping it to
# "Acetaminophen" before upsert lets it merge with the curated/pyrls entry instead
# of standing as a cryptic, recreational-classed duplicate.
_SOURCED_NAME_FIX = {
    "apap": "Acetaminophen",
}


def smart_title_case(name: str) -> str:
    """Title-case a substance name when the source supplied it all-lowercase.
    Preserves chemical naming conventions: known acronyms (LSD, MDMA, GBL)
    stay uppercase; words with embedded digits/hyphens get their first letter
    of each alpha run capitalised.

    Names already containing any uppercase letter are returned unchanged —
    the source's casing is presumed intentional (preserves "MDMA", "5-MeO-DMT",
    etc.) — EXCEPT a fully-uppercase single alphabetic word that isn't a known
    acronym, which is a SHOUTED common name (e.g. "IBOGAINE", "HARMALINE") and
    gets title-cased. Genuine acronyms are short and/or carry digits/hyphens, so
    the `isalpha()` + length≥7 + `_ACRONYMS` guard keeps "MBDB", "ADBICA",
    "25I-NBOMe" untouched. `_CANONICAL_CASE` overrides any residual edge case.
    """
    if not name:
        return name
    if name.isupper() and name.isalpha() and len(name) >= 7 and name.lower() not in _ACRONYMS:
        return name[0] + name[1:].lower()
    if any(c.isupper() for c in name):
        return name
    # Tokenise on word-separator characters, keeping the separators.
    parts = re.split(r"([\s\-,;()/.])", name)
    out: list[str] = []
    for p in parts:
        if not p or not p.isalpha() and not (p and p[0].isalpha()):
            # Mixed-alpha tokens (e.g. "2c-b") handled by the alpha-run loop below.
            if any(c.isalpha() for c in p):
                # Title-case the first alpha character of the token
                low = p.lower()
                if low in _ACRONYMS:
                    out.append(p.upper())
                else:
                    chars = list(p)
                    for i, c in enumerate(chars):
                        if c.isalpha():
                            chars[i] = c.upper()
                            break
                    out.append("".join(chars))
            else:
                out.append(p)
            continue
        low = p.lower()
        if low in _ACRONYMS:
            out.append(p.upper())
        else:
            out.append(p[0].upper() + p[1:])
    return "".join(out)


# Names that leaked from an LLM enrichment prompt into the data (e.g. the
# row "AMB-FUBINACA (AMB) — augmentation plan and justifications BEFORE JSON
# changes"). Never a real substance.
_LEAKED_PROMPT_RE = re.compile(
    r"augmentation plan|before json|justifications? before|enter section text",
    re.IGNORECASE,
)


def is_chemistry_noise(name: str) -> bool:
    """True if the substance name looks like a IUPAC chemistry artefact rather
    than a substance someone would log in a harm-reduction tracker."""
    n = (name or "").strip()
    if not n or _LEAKED_PROMPT_RE.search(n):
        return True
    return bool(_CHEM_NOISE_PREFIX.search(n)) or bool(_CHEM_NOISE_BODY.search(n))


# ---------------------------------------------------------------------------
# Display-policy classification vocab (consumed by Build.classify_compounds)
# ---------------------------------------------------------------------------

# STRONG recreational provenance — the harm-reduction wikis. A dose/duration
# here is the authoritative recreational signal AND the literal "if PsychonautWiki
# has the data, show it" dual-use rule: a medical-category drug appearing here is
# dual_use (dose shown). drug.community is deliberately EXCLUDED — it is a
# long-tail dataset that also carries CLINICAL doses for prescription meds, so
# trusting it would promote SSRIs/MAOIs/antipsychotics to a recreational ladder.
REC_SOURCE_SLUGS = {"psychonautwiki", "tripsit", "erowid-pihkal", "erowid-tihkal"}
# WEAK recreational provenance: confers recreational status only to NON-medical
# compounds (long-tail research chemicals), never promotes a medical drug.
WEAK_REC_SOURCE_SLUGS = {"drug.community"}

# Resolved categories that are recreational by nature.
RECREATIONAL_CATEGORIES = {
    "Stimulant",
    "Psychedelic",
    "Dissociative",
    "Dysdelic",
    "Opioid",
    "Benzodiazepine",
    "GABAergic",
    "Empathogen",
    "Cannabinoid",
    "Nootropic",
    "AMPAkine",
    "Eugeroic",
    "Depressant",
}
# Resolved categories that are medical/therapeutic. A compound here with a
# recreational dose signal is DUAL_USE; without one it is MEDICAL_RX.
MEDICAL_CATEGORIES = {
    "Antidepressant",
    "Antipsychotic",
    "Anticonvulsant",
    "Antihistamine",
    "Analgesic",
    "Cardiovascular",
    "Antimicrobial",
    "Gastrointestinal",
    "Respiratory",
    "Endocrine",
    "Immunological",
    "Peptide",
}
# Tags that establish recreational lineage even with no dose data (the RC
# stubs — novel psychedelics/cathinones/etc. catalogued without human dosing).
REC_TAGS = {
    "research-chemical",
    "no-human-data",
    "PIHKAL",
    "TIHKAL",
    "tryptamine",
    "phenethylamine",
    "cathinone",
    "arylcyclohexylamine",
    "designer-benzo",
    "designer-dissociative",
    "fentanyl-analog",
    "nitazene",
    "synthetic-cannabinoid",
    "semi-synthetic-cannabinoid",
    "lysergamide",
    "NBOMe",
    "psychedelic",
    "dissociative",
    "mu-opioid-agonist",
    "NMDA-antagonist",
    "salvinorin",
}
# Tags / category that mark a compound as having NO recreational value: it stays
# trackable for medication adherence but is hidden from recreational browsing.
ANTIBIOTIC_TAGS = {"antibiotic", "antiviral", "antifungal", "antiparasitic", "antimicrobial"}

# OTC compounds whose dose is on the package — dose may be shown even without a
# recreational signal (the developer's explicit exception to dose-suppression).
OTC_ALLOWLIST = {
    "melatonin",
    "caffeine",
    "ibuprofen",
    "acetaminophen",
    "paracetamol",
    "aspirin",
    "naproxen",
    "diphenhydramine",
    "doxylamine",
    "loratadine",
    "cetirizine",
    "famotidine",
    "loperamide",
    "dextromethorphan",
    "pseudoephedrine",
    "phenylephrine",
    "guaifenesin",
    "nicotine",
    "dimenhydrinate",
    "meclizine",
    "ranitidine",
    "omeprazole",
    "bismuth subsalicylate",
    "simethicone",
}

# OTC medicines with **no** recreational use that harm-reduction wikis still list
# (for overdose/interaction safety) and that aggregators tag "common". Without
# this, a TripSit/drug.community dose row classes paracetamol/ibuprofen as
# "recreational" and the TripSit "common" tag drops them into the recreational
# Common browse card — wrong for a painkiller. These are forced to `otc` and have
# the "common" tag stripped so they live in their clinical category instead.
# Deliberately excludes genuinely-abused OTC drugs (DXM, diphenhydramine,
# pseudoephedrine), which keep their recreational signal.
NON_RECREATIONAL_OTC = {
    "acetaminophen",
    "paracetamol",
    "ibuprofen",
    "aspirin",
    "naproxen",
}

# The Library's "Common" card is a curated entry point — "everyday substances,
# by the names most people know" — NOT a dump of every compound an aggregator
# happened to flag `common`. Upstream "common" tags (TripSit et al.) bled ~70
# research chemicals, designer benzos, and obscure isomers into it (25I-NBOMe,
# clonazolam, 4-HO-MET, …), which is the opposite of "common". So the build
# OWNS this tag: every upstream `common` tag is dropped and re-asserted for
# exactly this hand-picked set (~20). To add/remove a substance from the Common
# card, edit this set — nothing else. Matched by normalise()d name against the
# final (post-dedup) survivors; a name that resolves to nothing is reported
# (no silent drops), so a rename/merge that orphans an entry is caught at build.
COMMON_CARD_ALLOWLIST = {
    # Legal / ubiquitous
    "caffeine",
    "alcohol",
    "nicotine",
    "cannabis",
    # Well-known recreational
    "cocaine",
    "heroin",
    "mdma",
    "lysergic acid diethylamide",
    "mushrooms",
    "methamphetamine",
    "ketamine",
    "amphetamine",
    # Household opioid names
    "morphine",
    "codeine",
    "oxycodone",
    # Household benzo names
    "diazepam",
    "alprazolam",
    # Other names most people know
    "methylphenidate",
    "nitrous",
    "melatonin",
}

# Dosage-form vocabulary. pyrls/medtap dump the FDA `dosageForm` string straight
# into tags ("tablet, chewable tablet, extended release tablet, …"), which is
# noise as a class chip — the form lives in its own field. A tag whose *every*
# comma-part names a dosage form is dropped; a mixed drug-class label like
# "calcium channel blocker, dihydropyridine" is kept (not all parts are forms).
_DOSAGE_FORM_RE = re.compile(
    r"\b(tablet|capsule|injection|solution|suspension|syrup|cream|ointment|lotion|"
    r"gel|patch|suppositor(?:y|ies)|spray|powder|granules?|lozenge|elixir|aerosol|"
    r"drops?|film|wafer|implant|emulsion|paste|foam|enema|troche|sachet|concentrate|"
    r"liquid|inhalant|inhaler|pellet|sprinkle|syringe|cartridge|pen|packet|infusor|"
    r"delivery system|nebuli[sz]er|douche|shampoo|kit)\b",
    re.I,
)
# Form qualifiers that can stand alone as a comma-part ("orally disintegrating").
_DOSAGE_MODIFIER_RE = re.compile(
    r"^(extended[- ]release|delayed[- ]release|immediate[- ]release|modified[- ]release|"
    r"controlled[- ]release|sustained[- ]release|delayed onset|orally disintegrating|"
    r"chewable|dispersible|sublingual|buccal|effervescent|pre[- ]?filled|metered dose|"
    r"dry powder|osmotic|oral|topical|nasal|ophthalmic|otic|rectal|vaginal|"
    r"\d+ ?hour)\b",
    re.I,
)


def is_dosage_form_tag(tag: str) -> bool:
    # Drop brand parentheticals first — their inner commas ("(diskus, hfa)") would
    # otherwise split into non-form fragments and defeat the all-parts test.
    stripped = re.sub(r"\([^)]*\)", "", tag)
    parts = [p.strip() for p in stripped.split(",") if p.strip()]
    if not parts:
        return False
    return all(_DOSAGE_FORM_RE.search(p) or _DOSAGE_MODIFIER_RE.match(p) for p in parts)


# ---------------------------------------------------------------------------
# Name normalisation helpers (chirality, chemical-abbreviation casing)
# ---------------------------------------------------------------------------

# Leading chirality/optical prefix. Two names equal after stripping it but
# different before are stereoisomers (distinct compounds). Single-letter forms
# require a following hyphen/space so they can't eat the first letter of an
# ordinary name (lsd, dmt). Operates on a normalise()d (lowercased) string.
_STEREO_PREFIX_RE = re.compile(
    r"^(dextro|laevo|levo|dex|lev|rac|racemic|meso|es|ar|[dlrs](?=[\-\s]))[\-\s]*"
)


def strip_stereo(normalised: str) -> str:
    return _STEREO_PREFIX_RE.sub("", normalised)


# Short morphemes that must stay lowercase even inside a chemical code (so we
# don't render "2-oxo-PCE" as "2-OXO-PCE"). Everything else ≤4 chars in a
# code-style name is treated as an acronym and upper-cased.
# Note: chemical locant prefixes N-, O-, S- ARE upper-case ("N-methyl"), so they
# are deliberately NOT kept lower. "bk" (beta-keto) is the main lowercase prefix.
_CHEM_KEEP_LOWER = {
    "bk",
    "cis",
    "oxo",
    "keto",
    "aza",
    "oxa",
    "nor",
    "iso",
    "neo",
    "di",
    "tri",
    "bis",
    "mono",
    "homo",
    "seco",
    "nido",
    "para",
    "meta",
    "iodo",
    "endo",
    "exo",
    "syn",
    "thia",
    "sec",
    "tert",
}
# Alkyl-group morphemes that read as title-case in RC codes ("2-Me-PiHP",
# "N-Et-…"), NOT acronyms — so they aren't upper-cased to ME/ET. Distinct from
# hydroxy/methoxy (HO/MeO) which ARE upper/camel. Kept deliberately small to
# avoid clobbering real acronyms.
_CHEM_KEEP_TITLE = {"me", "et", "pr", "bu"}
# Conventional camelCase chemical segments. When a source supplies the name
# all-lowercase, title-casing produces "Meo"/"Mipt" and the acronym rule would
# upper-case them to MEO/MIPT; these restore the standard mixed-case form. Keyed
# by lowercased segment. (Names that arrive already cased are preserved by the
# interior-uppercase rule and never reach here.)
_CHEM_CAMEL = {
    "meo": "MeO",
    "aco": "AcO",
    "eto": "EtO",
    "tho": "ThO",
    "mipt": "MiPT",
    "dipt": "DiPT",
    "eipt": "EiPT",
    "pipt": "PiPT",
    "pihp": "PiHP",
    "nbome": "NBOMe",
    "nboh": "NBOH",
    "ipr": "iPr",
}
# Chemical-code names contain a digit (2-FMA, 4-HO-MET, bk-MDMA, 1P-LSD).
_CHEM_SEG_RE = re.compile(r"([\-/])")


def chem_caps(name: str) -> str:
    """Upper-case acronym segments in a chemical-code name so abbreviations read
    correctly: '2-Fma' → '2-FMA', '4-Ho-Met' → '4-HO-MET', 'bk-Mdma' → 'bk-MDMA'.
    Only touches names containing a digit (true chemical codes), and only short
    (≤4-char) alpha segments that aren't known lowercase morphemes — long word
    segments like '2-Aminoindane' are left title-cased.

    A segment with an INTERIOR uppercase letter is already intentionally
    mixed-case (PiHP, MeO, MiPT, NBOMe) and is left untouched — only the
    leading-cap form that title-casing produces from lowercase input
    ('fma'→'Fma') is treated as an acronym to upper-case."""
    if not any(c.isdigit() for c in name):
        return name
    out = []
    for seg in _CHEM_SEG_RE.split(name):
        if seg in ("-", "/") or not seg.isalpha():
            out.append(seg)
            continue
        low = seg.lower()
        if low in _CHEM_KEEP_LOWER:
            out.append(low)
        elif low in _CHEM_CAMEL:
            # Authoritative camelCase for known morphemes, regardless of input
            # case — canonicalises MEO/Meo/meo → MeO, MIPT → MiPT, NBOME → NBOMe.
            out.append(_CHEM_CAMEL[low])
        elif any(c.isupper() for c in seg[1:]):
            out.append(seg)  # other intentional interior caps — preserve as authored
        elif low in _CHEM_KEEP_TITLE:
            out.append(seg[0].upper() + seg[1:].lower())  # alkyl morpheme: Me, Et…
        elif len(seg) <= 4:
            out.append(seg.upper())
        else:
            out.append(seg)
    return "".join(out)


# Canonical category enum (mirrors SubstanceCategory in Swift). Keep in sync
# with Piru/Models/Substance.swift `SubstanceCategory` rawValue strings.
_CATEGORY_ENUM = {
    "Stimulant",
    "Psychedelic",
    "Dissociative",
    "Dysdelic",
    "Deliriant",
    "Opioid",
    "Benzodiazepine",
    "GABAergic",
    "Empathogen",
    "Cannabinoid",
    "Nootropic",
    "AMPAkine",
    "Eugeroic",
    "Depressant",
    "Antidepressant",
    "Antipsychotic",
    "Analgesic",
    "Antihistamine",
    "Cardiovascular",
    "Antimicrobial",
    "Gastrointestinal",
    "Respiratory",
    "Endocrine",
    "Immunological",
    "Supplement",
    "Peptide",
    "Anticonvulsant",
    "Other",
}

# Category normalization rules — (regex, canonical). FIRST match wins, so
# order encodes priority. Substance-class identifiers like "MAOI", "tricyclic"
# come before generic "antidepressant"; "NMDA antagonist" beats "psychedelic"
# (dissociatives are NOT psychedelics in our taxonomy); psychedelic beats
# stimulant/empathogen (per user: 2C-B is psychedelic first, not empathogen).
_CATEGORY_RULES: list[tuple[re.Pattern, str]] = [
    # --- Highest priority: medication classes ---
    # Peptide first — GLP-1 agonists, GH secretagogues, etc. are categorised by
    # delivery class, not by the Endocrine effect they have.
    (
        re.compile(
            r"\b(peptide|peptide[\s-]?mimetic|GLP[\s-]?1[\s-]?agonist|GIP[\s-]?agonist|GHRH[\s-]?analogue|GH[\s-]?secretagogue|healing[\s-]?peptide|nootropic[\s-]?peptide|melanocortin[\s-]?agonist)\b",
            re.I,
        ),
        "Peptide",
    ),
    # Anticonvulsant / mood-stabilizer covers antiseizure meds AND lithium.
    # Mood stabilizers used psychiatrically (lamotrigine, valproate, lithium)
    # land here rather than Antidepressant — they aren't antidepressants.
    (
        re.compile(
            r"\b(anticonvulsant|antiepileptic|mood[\s-]?(stabiliser|stabilizer)|antiseizure)\b",
            re.I,
        ),
        "Anticonvulsant",
    ),
    (re.compile(r"\b(antipsychotic|neuroleptic|atypical antipsychotic)\b", re.I), "Antipsychotic"),
    (
        re.compile(r"\b(antihistamine|H[12][\s-]?antagonist|H[12][\s-]?blocker)\b", re.I),
        "Antihistamine",
    ),
    (
        re.compile(
            r"\b(SSRI|SNRI|MAOI|NDRI|SARI|NaSSA|TCA|tricyclic|tetracyclic|monoamine[\s-]?oxidase[\s-]?inhibitor)\b",
            re.I,
        ),
        "Antidepressant",
    ),
    (re.compile(r"\bantidepressant\b", re.I), "Antidepressant"),
    # --- Cannabinoid & opioid (chemistry-defined, take precedence) ---
    (
        re.compile(r"\bcannabinoid\b|\bCB[12][\s-]?agonist\b|\bphytocannabinoid\b", re.I),
        "Cannabinoid",
    ),
    (
        re.compile(
            r"\b(μ[\s-]?opioid|µ[\s-]?opioid|mu[\s-]?opioid|opioid|opiate|narcotic|nitazene|fentanyl|fentanyl[\s-]?class)\b",
            re.I,
        ),
        "Opioid",
    ),
    # --- Dissociative beats psychedelic (NMDA mechanism) ---
    (
        re.compile(
            r"\bdissociative\b|\bNMDA[\s-]?(receptor[\s-]?)?antagonist\b|\bPCP[\s-]?(site|analogue|class)\b|\bketamine[\s-]?class\b",
            re.I,
        ),
        "Dissociative",
    ),
    # --- Dysdelic (κ-opioid hallucinogens) ---
    (re.compile(r"\bdysdelic\b|\b(κ|kappa)[\s-]?opioid\b|\bsalvinorin\b", re.I), "Dysdelic"),
    # --- Psychedelic beats empathogen + stimulant ---
    (
        re.compile(
            r"\bpsychedelic\b|\bhallucinogen\b|\b5[\s-]?HT2A[\s-]?(agonist|partial[\s-]?agonist)\b|\bDOx\b|\b2C[\s-]?[xX]?\b",
            re.I,
        ),
        "Psychedelic",
    ),
    # --- Empathogen / entactogen ---
    (re.compile(r"\b(empathogen|entactogen)\b", re.I), "Empathogen"),
    # --- GABAergic & benzodiazepine ---
    (re.compile(r"\bbenzodiazepine\b", re.I), "Benzodiazepine"),
    (re.compile(r"\b(gabapentinoid|gabaergic|alpha[\s-]?2[\s-]?delta|α2δ)\b", re.I), "GABAergic"),
    # --- Eugeroic before generic stimulant ---
    (re.compile(r"\b(eugeroic|wakefulness[\s-]?promoting|afinil)\b", re.I), "Eugeroic"),
    # --- AMPAkine (ampakine, AMPA PAM) ---
    (
        re.compile(
            r"\b(AMPAkine|ampakine|AMPA[\s-]?(receptor[\s-]?)?(positive[\s-]?)?modulator|AMPA[\s-]?PAM)\b",
            re.I,
        ),
        "AMPAkine",
    ),
    # --- Nootropic ---
    (re.compile(r"\b(nootropic|racetam)\b", re.I), "Nootropic"),
    # --- Antimicrobial ---
    (
        re.compile(
            r"\b(antimicrobial|antibiotic|antifungal|antiviral|antimalarial|antiparasitic)\b", re.I
        ),
        "Antimicrobial",
    ),
    # --- Cardiovascular ---
    (
        re.compile(
            r"\b(cardiovascular|beta[\s-]?blocker|β[\s-]?blocker|antihypertensive|alpha[\s-]?(1|2)[\s-]?(agonist|blocker)|calcium[\s-]?channel[\s-]?blocker|ACE[\s-]?inhibitor|ARB|statin|diuretic|antiarrhythmic|vasodilator)\b",
            re.I,
        ),
        "Cardiovascular",
    ),
    # --- Gastrointestinal / antiemetic ---
    (
        re.compile(
            r"\b(antiemetic|antidiarrhe[ai]l|laxative|proton[\s-]?pump[\s-]?inhibitor|PPI|prokinetic)\b",
            re.I,
        ),
        "Gastrointestinal",
    ),
    # --- Respiratory ---
    (
        re.compile(r"\b(bronchodilator|β2[\s-]?agonist|mucolytic|antitussive|expectorant)\b", re.I),
        "Respiratory",
    ),
    # --- Endocrine ---
    (
        re.compile(
            r"\b(estrogen|androgen|progestin|insulin|thyroid|GLP[\s-]?1|GIP|aromatase|hormone|steroid|corticosteroid)\b",
            re.I,
        ),
        "Endocrine",
    ),
    # --- Analgesic (non-opioid) ---
    (re.compile(r"\b(NSAID|paracetamol|acetaminophen|analgesic)\b", re.I), "Analgesic"),
    # --- Supplement / vitamin ---
    (
        re.compile(
            r"\b(supplement|vitamin|mineral|adaptogen|amino[\s-]?acid|herbal|nutraceutical)\b", re.I
        ),
        "Supplement",
    ),
    # --- Stimulant (after all higher-priority classes) ---
    (
        re.compile(
            r"\b(stimulant|sympathomimetic|monoamine[\s-]?releaser|DA[\s-]?releaser|NDRI[\s-]?stimulant|amphetamine|cathinone|piperazine[\s-]?stimulant|psychostimulant)\b",
            re.I,
        ),
        "Stimulant",
    ),
    # --- Depressant (catch-all for sedative-hypnotics not benzo/GABAergic) ---
    (
        re.compile(
            r"\b(depressant|sedative|hypnotic|anxiolytic|barbiturate|GHB|GABA[\s-]?A[\s-]?(positive[\s-]?)?(allosteric[\s-]?)?modulator|GABAA[\s-]?PAM)\b",
            re.I,
        ),
        "Depressant",
    ),
    # --- Deliriant (anticholinergic/antimuscarinic hallucinogens: tropane alkaloids,
    # glycolate-ester incapacitants, and the deliriant first-gen antihistamines) ---
    (
        re.compile(
            r"\b(deliriant|anticholinergic|antimuscarinic|muscarinic[\s-]?antagonist)\b", re.I
        ),
        "Deliriant",
    ),
]


def normalize_category(raw: str | None) -> str:
    """Map any free-form category string from any source to one of the
    canonical SubstanceCategory rawValue strings. Used at build time so the
    iOS app's `SubstanceCategory(rawValue:)` decode succeeds for every row
    and substances land in the correct grouping instead of "Other"."""
    if not raw:
        return "Other"
    s = str(raw).strip()
    if not s:
        return "Other"
    if s in _CATEGORY_ENUM:
        return s
    for pat, canonical in _CATEGORY_RULES:
        if pat.search(s):
            return canonical
    return "Other"


def parse_reference(ref: str | None) -> tuple[str | None, int | None, str | None, str | None]:
    """Parse a reference string into ``(doi, pmid, url, title)``.

    Beyond the clean ``doi:`` / ``pmid:`` / ``https://`` forms, sources hand us
    free text with a structured id embedded in a human label:
      - "PubChem CID 170703347"           → a real PubChem compound link
      - "PMID 12345"                       → a PubMed id (space form, no colon)
      - "Baar 2017 Cell; https://…/FOXO4"  → the URL + "Baar 2017 Cell" as title
      - "Azuma 2026 Drug Test Anal DOI:10.1002/…" → the DOI + label as title
    Extracting these turns ~1.2k dead-text "references" into tappable, titled
    links. A pure label with no id (e.g. "Ambien FDA label", "CAS 50-37-3") is
    kept verbatim in ``url`` — it both renders as readable text and keeps the
    (doi,pmid,url) dedup key unique (a bare title in the 4th slot would collapse
    every label onto one citation)."""
    if not ref:
        return (None, None, None, None)
    s = str(ref).strip()
    if not s:
        return (None, None, None, None)
    low = s.lower()
    if low.startswith("doi:"):
        return (s[4:].strip().lower(), None, None, None)
    if low.startswith("pmid:"):
        try:
            return (None, int(s[5:].strip()), None, None)
        except ValueError:
            return (None, None, s, None)
    if low.startswith("https://") or low.startswith("http://"):
        # Try to extract DOI from URL
        m = re.search(r"10\.\d{4,9}/[^\s]+", s)
        if m:
            return (m.group(0).lower(), None, s, None)
        m = re.search(r"/(\d{6,9})(?:/|$)", s)
        if m and "pubmed" in low:
            try:
                return (None, int(m.group(1)), s, None)
            except ValueError:
                pass
        return (None, None, s, None)
    if re.match(r"^10\.\d{4,9}/", s):
        return (s.lower(), None, None, None)
    # "PubChem CID <n>" → canonical compound link.
    m = re.fullmatch(r"(?i)pubchem\s+cid[:\s]+(\d+)", s)
    if m:
        return (None, None, f"https://pubchem.ncbi.nlm.nih.gov/compound/{m.group(1)}", None)
    # "PMID <n>" (space form, no colon).
    m = re.fullmatch(r"(?i)pmid[:\s]+(\d+)", s)
    if m:
        return (None, int(m.group(1)), None, None)
    # Descriptive label with an embedded URL — keep the prose as the title.
    m = re.search(r"https?://[^\s;]+", s)
    if m:
        url = m.group(0).rstrip(".,;")
        title = s[: m.start()].strip(" ;,-—:") or None
        dm = re.search(r"10\.\d{4,9}/[^\s]+", url)
        return (dm.group(0).lower() if dm else None, None, url, title)
    # Descriptive label with an embedded DOI.
    m = re.search(r"(?i)\bdoi[:\s]+(10\.\d{4,9}/\S+)", s) or re.search(r"\b(10\.\d{4,9}/\S+)", s)
    if m:
        title = s[: m.start()].strip(" ;,-—:") or None
        return (m.group(1).rstrip(".,;").lower(), None, None, title)
    return (None, None, s, None)


# Citation URLs/labels that are chemical identifiers or database landing pages,
# NOT primary literature. They already appear elsewhere — CAS/InChIKey in the
# Chemistry card, PubChem behind "View on PubChem", and tripsit/psychonautwiki/
# wikidata/drug.community in the Databases provenance subsection — so listing
# them again as "references" reads as spurious citations for trivial claims.
_NON_LITERATURE_HOSTS = (
    "pubchem.ncbi.nlm.nih.gov",
    "wikidata.org",
    "psychonautwiki.org",
    "drug.community",
    "tripsit.me",
    "github.com/tripsit",
)
_IDENTIFIER_LABEL_RE = re.compile(
    r"(?i)^(cas|pubchem(\s+cid)?|wikidata|inchi(key)?|unii|chembl|drugbank|smiles|chemspider)\b"
)


def is_identifier_citation(
    doi: str | None, pmid: int | None, url: str | None, title: str | None
) -> bool:
    """True when a parsed reference is a bare chemical identifier or a database
    landing page rather than primary literature, so it should not be stored as a
    citation. A DOI or PMID is always real literature and never matches; Erowid
    book pages and ordinary paper/article URLs are kept."""
    if doi or pmid:
        return False
    if not url:
        return True  # a label with no id and no link — nothing to cite
    u = url.strip().lower()
    if u.startswith("http"):
        return any(host in u for host in _NON_LITERATURE_HOSTS)
    return bool(_IDENTIFIER_LABEL_RE.match(u))


def to_float(v) -> float | None:
    if v is None or v == "":
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def to_int(v) -> int | None:
    if v is None or v == "":
        return None
    try:
        return int(v)
    except (TypeError, ValueError):
        try:
            return int(float(v))
        except (TypeError, ValueError):
            return None


# "Oral 80-90%", "Oral: 84%.", "Oral 70% +/- 24%.", and pipe-joined multi-route
# strings ("Oral 85-90% | Insufflated 76-80%"). Pull (route, pct) per segment:
# pct is the first %-value or a range midpoint; segments with no % (e.g. "Oral
# [variable - first-pass]") yield no row. The raw segment is kept as the note.
_BIOAVAIL_RE = re.compile(
    r"^\s*([A-Za-z/ ]+?)\s*:?\s*\[?\s*(\d+(?:\.\d+)?)\s*(?:[-–]\s*(\d+(?:\.\d+)?))?\s*%"
)


def _parse_bioavailability(text: str | None) -> list[tuple[str, float, str]]:
    if not text:
        return []
    out: list[tuple[str, float, str]] = []
    for seg in text.split("|"):
        seg = seg.strip()
        m = _BIOAVAIL_RE.match(seg)
        if not m:
            continue
        lo = float(m.group(2))
        pct = round((lo + float(m.group(3))) / 2.0, 1) if m.group(3) else lo
        out.append((m.group(1).strip(), pct, seg.rstrip(".")))
    return out


def get(d: dict | None, *keys, default=None):
    """Safe nested-dict access."""
    cur = d
    for k in keys:
        if not isinstance(cur, dict):
            return default
        cur = cur.get(k)
    return cur if cur is not None else default


def split_compound_name(name: str) -> tuple[str, list[str]]:
    """drug.community formats names as 'Primary (alias1, alias2)' — split."""
    if not name:
        return ("", [])
    if "(" in name and name.endswith(")"):
        base, parens = name.split("(", 1)
        return (base.strip(), [a.strip() for a in parens.rstrip(")").split(",") if a.strip()])
    return (name.strip(), [])


# Map source-specific route name spellings onto the canonical
# RouteOfAdministration raw values used by the iOS app's enum. The query
# layer relies on these strings matching across rows, so normalise here.
#
# Inhalation collapse: smoking, vaping, and vaporising are physiologically
# the same route — the substance enters via the lungs. Sources disagree on
# the label (PsychonautWiki "smoked", TripSit "inhalation", others "vaped"),
# which split the resolver and caused Cannabis to lose its 2–4 mg common
# dose data under "smoked" in favour of TripSit's 20–60 mg under "inhalation".
# Map everything in this family to `inhalation`.
_ROUTE_ALIASES = {
    "insufflated": "insufflation",
    "insufflated*": "insufflation",
    "snorted": "insufflation",
    "snorting": "insufflation",
    "nasal": "insufflation",
    "intranasal": "insufflation",
    "intra-nasal": "insufflation",
    "inhaled": "inhalation",
    "smoked": "inhalation",
    "smoke": "inhalation",
    "smoking": "inhalation",
    "vaped": "inhalation",
    "vaping": "inhalation",
    "vape": "inhalation",
    "vaped / smoked": "inhalation",
    "vaporized": "inhalation",
    "vaporised": "inhalation",
    "vapourized": "inhalation",
    "vapourised": "inhalation",
    "vaporization": "inhalation",
    "nebulised": "inhalation",
    "nebulized": "inhalation",
    "plugged": "rectal",
    "iv": "intravenous",
    "im": "intramuscular",
    "sc": "subcutaneous",
    "subq": "subcutaneous",
    "sublingually": "sublingual",
    "buccally": "buccal",
    "rectally": "rectal",
    "po": "oral",
    "by mouth": "oral",
    "in": "",
    # Eye drops: no dedicated route in the 10-value enum — surface as "other"
    # rather than leaking a non-enum "ophthalmic" string the app decodes to .other anyway.
    "ophthalmic": "other",
    "ocular": "other",
}


def normalise_route(route: str) -> str:
    r = (route or "").strip().lower()
    return _ROUTE_ALIASES.get(r, r)


# Name remap: when a source uses an alternate name for an existing canonical
# substance, redirect to the canonical name BEFORE row insertion so the
# duplicate substance row never gets created. Keyed by the lowercased
# alternate name; value is the canonical name we want to use everywhere.
#
# drug.community ingested "Cannabidiol" as a separate substance from PW's
# "CBD" entry, creating two parallel rows with different data attached.
# This map collapses them at the ingester.
_NAME_REMAP: dict[str, str] = {
    "cannabidiol": "CBD",
    "cannabichromene": "CBC",
    "cannabigerol": "CBG",
    # Adderall is a brand of mixed amphetamine salts — PsychonautWiki treats it
    # as an Amphetamine alias. Merge so it isn't a parallel standalone entry.
    "adderall": "Amphetamine",
    "adderall ir": "Amphetamine",
    "adderall xr": "Amphetamine",
    "mydayis": "Amphetamine",
    # Brand → generic for compounds whose brand record carries no InChIKey, so
    # the structural auto-dedup can't catch them. (The InChIKey connectivity
    # match handles all structurally-confirmed duplicates automatically.)
    "vyvanse": "Lisdexamfetamine",
    "elvanse": "Lisdexamfetamine",
    "focalin": "Dexmethylphenidate",
    "focalin xr": "Dexmethylphenidate",
    # Wikidata long-form / synonym variants that never matched the enriched
    # canonical (different or absent InChIKey) and would otherwise be dropped as
    # content-less stubs — fold them so their name survives as a search alias.
    "dimethyltryptamine": "DMT",  # DMT = N,N-dimethyltryptamine
    "dimethyltryptamine fumarate": "DMT",  # DMT fumarate salt
    "dimethyltryptamine hydrochloride": "DMT",  # DMT HCl salt
    "bufotenine": "Bufotenin",  # alternate spelling of 5-HO-DMT
    "indopan": "AMT",  # Indopan = brand name for α-methyltryptamine
    "5-bromodimethyltryptamine": "5-Bromo-DMT",  # same InChIKey ATEYZYQLBQUZJE
    "4-hydroxy-n,n diethyltryptamine": "4-HO-DET",  # same InChIKey OHHYMKDBKJPILO
}

# Same-compound clusters the structural auto-dedup leaves split because the
# members carry different/absent InChIKeys (RC analogues catalogued under a code
# name, a code name, AND a trivial name, each holding partial dose/duration
# data). Unlike _NAME_REMAP these fire AFTER all ingest+dedup, by exact current
# canonical name, so they consolidate whatever survived. Each tuple is
# (loser canonical, winner canonical, fold loser's aliases?). Verified synonyms
# only — never enantiomers or merely-related drugs.
_FORCE_MERGE: list[tuple[str, str, bool]] = [
    # Bisfluoro-modafinil (flmodafinil = bisfluoromodafinil = CRL-40,940)
    ("Bisfluoromodafinil", "Flmodafinil", True),
    ("CRL-40,940", "Flmodafinil", True),
    ("CRL-40-940", "Flmodafinil", True),
    # Fladrafinil = CRL-40,941
    ("CRL-40,941", "Fladrafinil", True),
    ("CRL-40-941", "Fladrafinil", True),
    # Desoxypipradrol = 2-DPMP (2-diphenylmethylpiperidine)
    ("Desoxypipradrol", "2-DPMP", True),
    # N-Ethylpentedrone = NEP = ethyl-pentedrone
    ("NEP", "N-Ethylpentedrone", True),
    ("Ethyl-pentedrone", "N-Ethylpentedrone", True),
    # Aspirin = acetylsalicylic acid (Aspirin is the recognisable canonical)
    ("Acetylsalicylic acid", "Aspirin", True),
    # Same-InChIKey real duplicates dedup missed (not alias-linked).
    ("S-Ketamine", "Esketamine", True),  # esketamine IS the S-enantiomer (YQEZLKZALYSWHR)
    ("Ethylcathinone", "N-Ethylcathinone", True),  # ethcathinone (QTFKIBOSWFGCSL); NEC is curated
    # Psilocybin's mg dose ladder lives in a mislabelled same-InChIKey sibling.
    # Fold the DATA but NOT the name — "4-HO-DMT" is psilocin, a different drug.
    ("4-HO-DMT / 4-HO-DMT PHOSPHATE ESTER", "Psilocybin", False),
    # 2-FDCK doubled: the short-name stub carries a WRONG InChIKey
    # (PHFAGYYTDLITTB) so structural dedup never matched the full-name record
    # (BAHANNQVCQDQQT, the correct key). Fold the stub into the correctly-keyed
    # canonical; display stays "2-FDCK" via its display_name.
    ("2-FDCK", "2-Fluorodeschloroketamine", True),
]

# Do-NOT-merge pairs: distinct compounds whose source InChIKeys collide on the
# first-14 connectivity block, so the structural auto-dedup (mergeable()) would
# wrongly fuse them if a linking alias ever puts them in the same union-find
# group (#8). The collisions are NPS-catalogue salt-form / mislabelled-key
# artifacts — e.g. Methylone and Cyclobenzaprine both carry JURKNVYFZMSNLP in the
# raw data though they are unrelated molecules. Keyed on the unordered pair of
# normalise(canonical) names; the guard fires regardless of which is winner/loser.
# Floor deliverable (no external PubChem re-lookup required); each pair is
# verified to stay SPLIT after rebuild.
_DO_NOT_MERGE: set[frozenset[str]] = {
    frozenset({normalise("Methylone"), normalise("Cyclobenzaprine")}),
    frozenset({normalise("Cannabis"), normalise("THC")}),
    frozenset({normalise("CBC"), normalise("CBG")}),
    frozenset({normalise("3-MMC"), normalise("Myristicin")}),
    # Further mislabelled-InChIKey collisions surfaced by the by-category audit
    # (_FLAGS dup_same_inchikey_block). Each pair is unrelated chemistry sharing
    # a connectivity block only because one record carries a wrong key.
    frozenset({normalise("Tilidine"), normalise("Methylphenidate")}),
    frozenset({normalise("Tilidine"), normalise("Dexmethylphenidate")}),
    frozenset({normalise("Picamilon"), normalise("Selegiline")}),
    frozenset({normalise("CBDV"), normalise("THCV")}),
    frozenset({normalise("4-Chloroamphetamine"), normalise("Fenfluramine")}),
}

# Force a specific canonical display casing for names that arrive mis-cased and
# that smart_title_case can't fix (all-caps like "MELATONIN", or mixed-case
# chemistry conventions like AcO / NBOMe). Keyed on normalise(name).
_CANONICAL_CASE: dict[str, str] = {
    "melatonin": "Melatonin",  # was all-caps MELATONIN
    "lsa": "LSA",  # was Lsa
    "4-aco-dmt": "4-AcO-DMT",  # acetoxy = AcO
    "25i-nbome": "25I-NBOMe",  # NBOMe convention
    # 2C = phenethylamine class, uppercase C (the fused "2c" segment carries a
    # digit so chem_caps skips it; bare 2C-B/2C-I arrive cased from source).
    "bk-2c-b": "bk-2C-B",
    "bk-2c-i": "bk-2C-I",
    "βh-2c-b": "βH-2C-B",  # β-hydroxy-2C-B
    # Cathinones / piperazines / RCs whose lowercase-from-source names get
    # title-cased to "Mdpv"/"Bzp" — these are acronyms and read ALL CAPS.
    "mdpv": "MDPV",
    "mdai": "MDAI",
    "mdpa": "MDPA",
    "mdphp": "MDPHP",
    "mbdb": "MBDB",
    "mbzp": "MBZP",
    "bzp": "BZP",
    "dmaa": "DMAA",
    "mpa": "MPA",
    "pce": "PCE",
    "aet": "AET",
    "ept": "EPT",
    "lsz": "LSZ",
    "pma": "PMA",
    "pmma": "PMMA",
    "apap": "APAP",
    "mcpp": "mCPP",  # meta-chlorophenylpiperazine — lowercase locant m
    "pipt": "PiPT",  # propyl-isopropyltryptamine — camel morpheme
}


# Per-substance tag blocklist: tags a source wrongly attaches to the keyed
# substance. Keys are normalised canonical names; values are tags to drop.
# Applied AFTER dedup so it catches tags inherited from a merged-in stub
# (e.g. Wikidata's LSD record tags it "phenethylamine" — it's a tryptamine /
# lysergamide — and "no-human-data", absurd for the most-studied psychedelic).
# These are cosmetic, not classification-load-bearing: LSD keeps recreational
# lineage via its category + lysergamide/tryptamine/TIHKAL/common tags.
_TAG_BLOCKLIST: dict[str, set[str]] = {
    "lsd": {"no-human-data", "phenethylamine"},
    # Pure dopaminergic/noradrenergic stimulants wrongly carrying an empathogen
    # tag (no meaningful serotonin release). Category is pinned via curated; this
    # strips the residual cosmetic tag so the detail card doesn't call them
    # empathogens. (See findings A/B — empathogen requires 5-HT release.)
    "mdpv": {"empathogen", "entactogen"},
    "2-fea": {"empathogen", "entactogen"},
    "a-pihp": {"empathogen", "entactogen"},
    "alpha-pihp": {"empathogen", "entactogen"},
    "md-pihp": {"empathogen", "entactogen"},
    "2-me-pihp": {"empathogen", "entactogen"},
    "3f-pihp": {"empathogen", "entactogen"},
    "flephedrone": {"empathogen", "entactogen"},
    "methcathinone": {"empathogen", "entactogen"},
    "n-ethylpentedrone": {"empathogen", "entactogen"},
    "mexedrone": {"empathogen", "entactogen"},
    "3-chloromethcathinone": {"empathogen", "entactogen"},
    "3-fea": {"empathogen", "entactogen"},
    "3-fma": {"empathogen", "entactogen"},
    "4-fluoropentedrone": {"empathogen", "entactogen"},
    "4-mpd": {"empathogen", "entactogen"},
    "3-fluoromethcathinone": {"empathogen", "entactogen"},
}

# Final removal blocklist: rows that are NOT consumable substances and should
# never reach the app. Keyed on normalise(canonical_name). Distinct from the
# medtap protein-name regex (which fires at ingest): these are arbitrary
# non-drug entries (enzymes, lab reagents, hoaxes) that slipped through from
# any source. Verified non-substances only.
_REMOVE_NAMES: set[str] = {
    normalise("DNA (cytosine-5)-methyltransferase 1"),
    normalise("Tetrakis(2-Methoxyisobutylisocyanide)Copper(I) Tetrafluoroborate"),
    normalise("Jenkem"),  # urban-legend hoax, no active pharmacology
    # Periodic-table / biomolecule entries that aren't consumable substances —
    # this is a substance tracker, not a chemistry catalogue. (Calcium / Iodine /
    # Lithium / Potassium / Sodium stay: they're real supplements / medications.)
    normalise("DNA"),
    normalise("Silver"),
    normalise("Hydrogen"),
    # Redundant protonated-cation duplicate of Oxedrine (synephrine).
    normalise("D-synephrine(1+)"),
}

# Tags that mark a row as pharmacologically inert / fake. A substance carrying
# any of these AND with no dose data AND no curated file is dropped as clutter
# (PV-9/PV-10/4-CIC/Methoxypiperamide-class inert RCs). Recreational provenance
# or a dose ladder protects it (we never drop something with real data).
_INERT_TAGS: set[str] = {
    "inactive",
    "not-psychoactive",
    "no-known-active-pharmacology",
    "hoax",
    "hoax-or-urban-legend",
}


# Per-substance alias blocklist: aliases that sources sometimes provide for
# the keyed substance but that refer to a structurally distinct compound.
# drug.community + a few other sources list "THC", "CBD", "Dronabinol",
# "Epidiolex", and similar specific molecule names as aliases of "Cannabis"
# (the plant). They're not — they're individual constituents OF the plant,
# and the app already carries them as separate substance entries. Surfacing
# them as Cannabis aliases makes the search results misleading and conflates
# logging a joint with logging a pure-cannabinoid product.
#
# Keys are normalised canonical names (lowercase). Values are sets of
# normalised alias strings to drop on insert.
_ALIAS_BLOCKLIST: dict[str, set[str]] = {
    "cannabis": {
        # Δ⁹-THC and synonyms — distinct molecule, has its own entry
        "thc",
        "delta-9-thc",
        "delta-9 thc",
        "delta 9 thc",
        "delta‑9 thc",
        "delta-9-tetrahydrocannabinol",
        "tetrahydrocannabinol",
        "δ9-thc",
        "δ9‑thc",
        "δ⁹-thc",
        "dronabinol",
        "dronabinol (natural)",
        "marinol",
        "syndros",
        # CBD and synonyms — distinct molecule, has its own entry
        "cbd",
        "cannabidiol",
        "(-)-cannabidiol",
        "epidiolex",
        "epidiolex (purified cbd)",
        # Other cannabinoids — each has its own entry
        "cbg",
        "cannabigerol",
        "cbn",
        "cannabinol",
        "cbc",
        "cannabichromene",
        "cbdv",
        "cannabidivarin",
        # Mixtures and prepared products — not synonyms for raw cannabis
        "nabiximols",
        "nabiximols (sativex)",
        "sativex",
        "thc+cbd",
        "tetrahydrocannabinol+cannabidiol",
    },
    # Plant / preparation aliased onto the active MOLECULE (each has its own entry).
    "mescaline": {
        "peyote",
        "san pedro",
        "san-pedro",
        "san",
        "peyote alkaloid",
        "san pedro/trichocereus cactus alkaloid",
    },
    "mushrooms": {"psilocybin", "psilocin"},
    "caffeine": {"coffee"},
    # Distinct compounds wrongly cross-aliased (dangerous in a HR tracker).
    "mdma": {"ma"},  # MA = methamphetamine abbrev
    "methylone": {"molly", "bath salt", "bath salts"},  # Molly = MDMA slang
    "5-htp": {"l-tryptophan", "tryptophan"},  # distinct precursor
    "melatonin": {"5-mt", "5-methoxytryptamine", "ramelteon"},
    "diphenhydramine": {"dimenhydrinate", "fexofenadine", "meclizine"},
    "4-ho-met": {"ethocin"},  # ethocin = 4-HO-DET
    "dextromethorphan": {"duract"},  # bromfenac (an NSAID)
    # Methylphenidate (racemate) ≠ dexmethylphenidate (d-isomer, Focalin) — a
    # distinct, ~2x-potency compound with its own entry. Don't cross-alias.
    "methylphenidate": {
        "dexmethylphenidate",
        "focalin",
        "focalin xr",
        "dexmethylphenidate hydrochloride extended-release",
    },
    # medtap (FDA product labels) cross-drug contamination: a combo-product or
    # related-drug label leaked another compound's name in as an alias. Each
    # alias below names a DIFFERENT substance that has its own entry — dangerous
    # in a dose tracker (searching the alias resolves to the wrong drug).
    "salicylic acid": {"bismuth", "ibuprofen", "magnesium"},
    "loratadine": {"fexofenadine"},
    "famotidine": {"ranitidine"},
    "epinephrine": {"bupivacaine"},
    "estradiol": {"ethynodiol"},
    "d-glucose": {"heparin"},
    "aluminum hydroxide": {"calcium"},
    "bismuth subsalicylate": {"bismuth"},
    "docusate/sennosides": {"sennosides"},
}


# Class-keyed dose-magnitude invariants. Same family as the existing
# tier-inversion / tier-regression / ambiguous-unit guards in `add_dose`,
# but informed by chemistry rather than purely structural shape. The
# guard targets the failure mode the audit caught most often: a row
# with a single tier value, structurally consistent (no inversion, no
# regression), but with the magnitude grossly wrong for the chemistry
# (e.g. TripSit's Valerylfentanyl bare "50 mg" — a single tier, valid
# unit, but ~100× lethal for a fentanyl-class opioid).
#
# Tags chosen for high precision: each identifies a class whose safe
# maximum dose is well under the ceiling regardless of route. We
# deliberately avoid broader tags (e.g. plain `nitazene` without an
# explicit potency marker) because they include weaker analogs like
# Clonitazene where upstream values may be legitimately higher.
_CLASS_DOSE_CEILING_MG: dict[str, float] = {
    # Fentanyl-class opioids: every clinically-used route fits in <2 mg.
    "fentanyl-class-potency": 2.0,
    "fentanyl-analog": 2.0,
    # Nitazenes flagged as extreme-potency (etonitazene & friends).
    # `extreme-potency` also covers designer-benzos (clonazolam etc.)
    # whose heavy doses are at most ~2 mg, so the same ceiling fits.
    "extreme-potency": 2.0,
    "ultra-high-potency": 2.0,
    # Benzodiazepines: most max-therapeutic single doses are ≤100 mg, but
    # legacy compounds like Tetrazepam (50–200 mg) and Cinolazepam (≤120
    # mg in some references) sit higher. Ceiling at 300 mg preserves
    # those while still catching obvious unit confusion (e.g. Halazepam
    # "3600 mg" from a row whose value is really a daily-total artefact).
    "benzodiazepine": 300.0,
    "designer-benzo": 300.0,
    "triazolobenzodiazepine": 300.0,
    # Lysergamides: LSD threshold ~15 µg, heavy ~300 µg. 5 mg = 5000 µg,
    # which is well above every entry in the DB but flags obvious
    # mg/µg unit confusion (e.g. a `light 100 mg` LSD row).
    "class:lysergamides": 5.0,
    "class:Lysergamide": 5.0,
}


# Convert a dose unit string to a milligram multiplier. Returns None
# for non-mass units (mg/kg, per-day, seeds, IU, sprays, ml, %, etc.)
# — those rows can't be magnitude-checked against the class ceiling
# and pass through the invariant gate unchanged.
def _unit_to_mg_factor(unit: str | None) -> float | None:
    if unit is None:
        return 1.0
    u = unit.lower().strip()
    if not u:
        return 1.0
    # Reject anything with per-kg, per-day, per-hour-of-non-mass,
    # salt/freebase qualifiers — the bare numeric tier value is not a
    # direct mass and the invariant doesn't apply cleanly. (Note: pure
    # `µg/hr` patch units ARE handled below, since the numeric value
    # is still a microgram quantity.)
    if "/kg" in u or "/day" in u or "/24h" in u:
        return None
    if u in ("mg", "mgs"):
        return 1.0
    if u in ("g", "gram", "grams"):
        return 1000.0
    if u in ("µg", "ug", "mcg", "μg", "micrograms"):
        return 0.001
    # Patch / per-hour delivery rates: the numeric magnitude check still
    # applies — a "100 µg/hr" patch's numeric is in micrograms.
    if u in ("µg/hr", "ug/hr", "mcg/hr", "mcg/hour", "mcg/hr (patch)"):
        return 0.001
    # Anything else (seeds, drops, sprays, IU, ml, mg-with-qualifier-text,
    # percentages) can't be safely interpreted — skip the check.
    return None


# ---------------------------------------------------------------------------
# Build pipeline
# ---------------------------------------------------------------------------


class Build:
    def __init__(self, db: sqlite3.Connection):
        self.db = db
        self.cur = db.cursor()
        self.source_ids: dict[str, int] = {}
        # Normalised salt-variant names (Magnesium Citrate, …) folded into a
        # salt-family parent — protected from the chemnoise alias purge so the
        # variant stays searchable. Populated by fold_salt_families().
        self.salt_alias_protect: set[str] = set()
        self.substance_ids: dict[str, int] = {}  # normalised_name -> id
        self.citation_cache: dict[tuple[str | None, int | None, str | None], int] = {}
        # Per-substance union of tags seen across every source so far. The
        # tag-keyed dose-magnitude gate in `add_dose` consults this; populated
        # by `add_tag`.
        self.substance_tags: dict[int, set[str]] = defaultdict(set)
        # Whitelisted PW effect strings that resolved to no controlled-vocab
        # entry (vocab_id NULL). Surfaced as curation candidates at build end —
        # no-silent-caps: they still ship (raw `text` is the fallback).
        self.effect_vocab_unmatched: Counter[str] = Counter()
        self.stats: dict[str, int] = defaultdict(int)

    # ---- seeds ----

    def seed_sources(self) -> None:
        for prio, (slug, name, desc) in enumerate(SOURCES, start=1):
            self.cur.execute(
                "INSERT INTO sources(slug, display_name, description, default_priority, default_enabled) VALUES (?, ?, ?, ?, 1)",
                (slug, name, desc, prio),
            )
            self.source_ids[slug] = self.cur.lastrowid

    def seed_effect_vocab(self) -> None:
        """Seed the controlled effect vocabulary (Track 1 localization).

        Populates ``effect_vocab`` (slug + category) and ``effect_vocab_labels``
        (en + curated zh-Hans/zh-Hant). Must run after ``seed_sources`` and
        before any ingest, so the FK from ``effects.vocab_id`` is satisfiable
        (foreign_keys is ON). The English label + category come from the PW SEI
        whitelist; zh labels from the curated crosswalk JSON.
        """
        for vid, (_en_label, category) in EFFECT_VOCAB.items():
            self.cur.execute(
                "INSERT INTO effect_vocab(vocab_id, category) VALUES (?, ?)",
                (vid, category),
            )
        for vid, language, label, machine_translated in vocab_labels():
            self.cur.execute(
                "INSERT INTO effect_vocab_labels(vocab_id, language, label, machine_translated) VALUES (?, ?, ?, ?)",
                (vid, language, label, machine_translated),
            )
        self.stats["effect_vocab"] = len(EFFECT_VOCAB)

    # ---- citations ----

    def cite(self, ref: str | None) -> int | None:
        if not ref:
            return None
        doi, pmid, url, title = parse_reference(ref)
        if (doi, pmid, url) == (None, None, None):
            return None
        # Identifiers and database landing pages are not literature — drop them
        # so they never reach the references list (they live in Chemistry / the
        # PubChem link / the Databases subsection instead).
        if is_identifier_citation(doi, pmid, url, title):
            self.stats["citations_dropped_identifier"] = (
                self.stats.get("citations_dropped_identifier", 0) + 1
            )
            return None
        # Dedup key stays (doi, pmid, url) — the UNIQUE constraint; title is
        # descriptive metadata that backfills onto the shared citation.
        key = (doi, pmid, url)
        if key in self.citation_cache:
            cid = self.citation_cache[key]
            if title:
                self.cur.execute(
                    "UPDATE citations SET title=COALESCE(title, ?) WHERE id=?", (title, cid)
                )
            return cid
        try:
            self.cur.execute(
                "INSERT INTO citations(doi, pmid, url, title) VALUES (?, ?, ?, ?)",
                (doi, pmid, url, title),
            )
            cid = self.cur.lastrowid
        except sqlite3.IntegrityError:
            row = self.cur.execute(
                "SELECT id FROM citations WHERE doi IS ? AND pmid IS ? AND url IS ?",
                (doi, pmid, url),
            ).fetchone()
            cid = row[0]
            if title:
                self.cur.execute(
                    "UPDATE citations SET title=COALESCE(title, ?) WHERE id=?", (title, cid)
                )
        self.citation_cache[key] = cid
        return cid

    # ---- substances ----

    def upsert_substance(
        self,
        name: str,
        *,
        aliases: list[str] | None = None,
        inchikey: str | None = None,
        pubchem_cid: int | None = None,
        cas: str | None = None,
        iupac: str | None = None,
        smiles: str | None = None,
        formula: str | None = None,
        molecular_weight: float | None = None,
        regulatory_status: str | None = None,
        source_slug: str | None = None,
    ) -> int | None:
        name = (name or "").strip()
        if not name:
            return None
        # Single choke-point for blocking IUPAC chemistry noise from any
        # ingester (wikidata SPARQL, drug.community, enrichment).
        if is_chemistry_noise(name):
            return None
        # Collapse known alt-names onto their canonical entry so a source
        # supplying "Cannabidiol" merges into the existing "CBD" row instead
        # of creating a parallel one. The original name still gets preserved
        # as an alias of the canonical via the caller's aliases list.
        remapped = _NAME_REMAP.get(name.lower())
        if remapped is not None and remapped.lower() != name.lower():
            original_name = name
            name = remapped
            # Keep the original as an alias so it's still searchable.
            aliases = list(aliases or [])
            if original_name not in aliases:
                aliases.append(original_name)
            self.stats.setdefault("name_remapped", 0)
            self.stats["name_remapped"] += 1
        name = smart_title_case(name)
        name = _CANONICAL_CASE.get(normalise(name), name)
        name = chem_caps(name)
        norm = normalise(name)
        if norm in self.substance_ids:
            sid = self.substance_ids[norm]
            # Backfill identifier columns if we now have something better
            self.cur.execute(
                "UPDATE substances SET inchikey = COALESCE(inchikey, ?), pubchem_cid = COALESCE(pubchem_cid, ?), cas = COALESCE(cas, ?), iupac_name = COALESCE(iupac_name, ?), smiles = COALESCE(smiles, ?), formula = COALESCE(formula, ?), molecular_weight = COALESCE(molecular_weight, ?), regulatory_status = COALESCE(regulatory_status, ?) WHERE id = ?",
                (
                    inchikey,
                    pubchem_cid,
                    cas,
                    iupac,
                    smiles,
                    formula,
                    molecular_weight,
                    regulatory_status,
                    sid,
                ),
            )
        else:
            try:
                self.cur.execute(
                    "INSERT INTO substances(canonical_name, normalized_name, inchikey, pubchem_cid, cas, iupac_name, smiles, formula, molecular_weight, regulatory_status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (
                        name,
                        norm,
                        inchikey,
                        pubchem_cid,
                        cas,
                        iupac,
                        smiles,
                        formula,
                        molecular_weight,
                        regulatory_status,
                    ),
                )
                sid = self.cur.lastrowid
            except sqlite3.IntegrityError:
                # Race on canonical_name — happens when name normalises to existing entry
                row = self.cur.execute(
                    "SELECT id FROM substances WHERE canonical_name = ?", (name,)
                ).fetchone()
                if not row:
                    return None
                sid = row[0]
            self.substance_ids[norm] = sid
            self.stats["substances"] += 1

        # Sorted so alias rows insert in a stable order regardless of how the
        # caller built the list (many sources pass a set-derived list, whose
        # iteration order is randomized by str hashing — see _add_alias). This
        # keeps the built DB byte-reproducible across runs.
        for alias in sorted(aliases or []):
            self._add_alias(sid, alias, source_slug)
        return sid

    # A trailing "(...)" annotation sources tack onto brand names, e.g.
    # "OxyContin (ER oxycodone)" → "OxyContin", "Nicorette (gum, brand)".
    _ALIAS_PAREN_RE = re.compile(r"\s*\([^()]*\)\s*$")

    def _add_alias(self, sid: int, alias: str, source_slug: str | None) -> None:
        alias = (alias or "").strip().strip('"“”').strip()
        # Strip a trailing parenthetical annotation, then drop descriptive /
        # list / fragment junk that leaked in as aliases: colons ("Counterfeit
        # slang: M30 blues"), braces ("{N-[2-...]} Acetamide"), ", "-separated
        # combo-product lists ("Brompheniramine Maleate, Pseudoephedrine ..."),
        # and absurdly long systematic strings. Chemical names with bare commas
        # ("1,3,7-trimethylxanthine") are kept — only comma+space is a list.
        alias = self._ALIAS_PAREN_RE.sub("", alias).strip()
        if not alias:
            return
        # Drop structural junk + fragments: a bare number ("3", split out of a
        # "3,4-…" systematic name) or a CAS registry number ("87913-26-6") is
        # noise as an "also known as" chip and useless for search. Single letters
        # are kept — some are real slang (G, K, L, H).
        if (
            ":" in alias
            or "{" in alias
            or "}" in alias
            or ", " in alias
            or len(alias) > 70
            or alias.isdigit()
            or re.fullmatch(r"\d{2,7}-\d{2}-\d", alias) is not None
        ):
            self.stats["dropped_junk_alias"] = self.stats.get("dropped_junk_alias", 0) + 1
            return
        # Per-substance alias blocklist: drop aliases that name a structurally
        # distinct compound (e.g. "psilocybin" on the Mushrooms plant record).
        canon = self.cur.execute(
            "SELECT canonical_name FROM substances WHERE id=?", (sid,)
        ).fetchone()
        if canon:
            if alias.lower() in _ALIAS_BLOCKLIST.get(canon[0].lower(), ()):
                self.stats["dropped_blocked_alias"] = self.stats.get("dropped_blocked_alias", 0) + 1
                return
            if alias.lower() == canon[0].lower():
                return  # don't alias a substance to its own canonical name
            # Strip chiral/optical variants of the base canonical name — pure
            # clutter ("(±)-MDMA"; "Dextroamphetamine" on the "Amphetamine"
            # base). Only when the canonical is itself the prefix-free base, so
            # the Dextroamphetamine record keeps its own name.
            cnorm = normalise(canon[0])
            anorm = normalise(alias)
            if anorm != cnorm and strip_stereo(anorm) == cnorm and strip_stereo(cnorm) == cnorm:
                self.stats["dropped_chiral_alias"] = self.stats.get("dropped_chiral_alias", 0) + 1
                return
        norm = normalise(alias)
        # Case-/salt-insensitive dedup: skip if a variant alias already exists
        # (collapses "Acid"/"acid", "Robitussin"/"robitussin", "X"/"X HCl").
        # Exception: if the stored variant is chemistry-noise ("(+)-LSD") and
        # the incoming one is a clean common name ("LSD"), swap in the clean
        # variant. Otherwise the noise variant holds the normalized slot and the
        # final chemnoise-alias purge deletes it — leaving the form (e.g. plain
        # "LSD") with no alias at all.
        existing = self.cur.execute(
            "SELECT rowid, alias FROM aliases WHERE substance_id=? AND alias_normalized=?",
            (sid, norm),
        ).fetchone()
        if existing:
            existing_rowid, existing_alias = existing
            if is_chemnoise_alias(existing_alias) and not is_chemnoise_alias(alias):
                self.cur.execute(
                    "UPDATE aliases SET alias=? WHERE rowid=?", (alias, existing_rowid)
                )
            elif (
                is_chemnoise_alias(alias) == is_chemnoise_alias(existing_alias)
                and alias < existing_alias
            ):
                # Deterministic casing tiebreak. Two spellings that normalise to
                # the same form but differ only in case ("Alpha-O"/"alpha-O",
                # "Indian Pipe"/"Indian pipe") used to race: whichever the build
                # happened to insert FIRST held the slot, and insertion order is
                # randomized by Python's per-process str hashing (set/dict
                # iteration). That made the shipped casing nondeterministic. Keep
                # the lexicographically smaller spelling instead — order-independent
                # and it prefers the capitalised display form (ASCII upper < lower).
                self.cur.execute(
                    "UPDATE aliases SET alias=? WHERE rowid=?", (alias, existing_rowid)
                )
            self.stats["dropped_dup_alias"] = self.stats.get("dropped_dup_alias", 0) + 1
            return
        source_id = self.source_ids.get(source_slug) if source_slug else None
        try:
            self.cur.execute(
                "INSERT INTO aliases(substance_id, alias, alias_normalized, source_id) VALUES (?, ?, ?, ?)",
                (sid, alias, norm, source_id),
            )
            self.stats["aliases"] += 1
        except sqlite3.IntegrityError:
            pass  # already present

    # ---- per-source field inserters ----

    def add_category(
        self, sid: int, source_slug: str, category: str, confidence: str | None = None
    ) -> None:
        if not category:
            return
        # Normalise to the canonical SubstanceCategory enum at write time so
        # the iOS app's `SubstanceCategory(rawValue:)` decode succeeds for
        # every row. Without this, drug.community's long descriptive
        # categories ("Antidepressant (NaSSA: noradrenergic...)") and the
        # enrichment swarm's mechanism-heavy strings all fall into "Other".
        category = normalize_category(category)
        src = self.source_ids[source_slug]
        try:
            self.cur.execute(
                "INSERT INTO categories(substance_id, source_id, category, confidence) VALUES (?, ?, ?, ?)",
                (sid, src, category, confidence),
            )
            self.stats["categories"] += 1
        except sqlite3.IntegrityError:
            pass

    def add_tag(self, sid: int, source_slug: str, tag: str, confidence: str | None = None) -> None:
        if not tag or is_dosage_form_tag(tag):
            return
        src = self.source_ids[source_slug]
        # Cache unconditionally so the dose-magnitude gate sees every tag
        # any source asserts for this substance, even if the row was already
        # inserted by an earlier pass.
        self.substance_tags[sid].add(tag)
        try:
            self.cur.execute(
                "INSERT INTO tags(substance_id, tag, source_id, confidence) VALUES (?, ?, ?, ?)",
                (sid, tag, src, confidence),
            )
            self.stats["tags"] += 1
        except sqlite3.IntegrityError:
            pass

    def add_dose(
        self,
        sid: int,
        source_slug: str,
        route: str,
        unit: str,
        *,
        threshold=None,
        light=None,
        common=None,
        strong=None,
        heavy=None,
        notes: str | None = None,
        citation: str | None = None,
        salt_form: str | None = None,
    ) -> None:
        route = normalise_route(route)
        if not route:
            return

        # Reject ambiguous unit strings. Sources occasionally store dose-row
        # units as "mg (weighed) or µg (weighed)" or "mg (or mcg)" — the
        # numeric tier values then become unintelligible since they could be
        # in either unit (and the two differ by 1000×). The display has no
        # way to reconcile this; safer to drop than to render ambiguous
        # values for a harm-reduction app.
        if unit and (" or " in unit.lower() or "(or " in unit.lower()):
            self.stats.setdefault("dropped_ambiguous_unit", 0)
            self.stats["dropped_ambiguous_unit"] += 1
            return

        src = self.source_ids[source_slug]
        ll, lu = (
            (None, None)
            if not light
            else (to_float(light.get("lower")), to_float(light.get("upper")))
        )
        cl, cu = (
            (None, None)
            if not common
            else (to_float(common.get("lower")), to_float(common.get("upper")))
        )
        sl, su = (
            (None, None)
            if not strong
            else (to_float(strong.get("lower")), to_float(strong.get("upper")))
        )
        t = to_float(threshold)
        h = to_float(heavy)

        # Monotonicity sanity check #1: gross inversion (≥10×). Catches
        # unit-mixing within a row (e.g. Butyrfentanyl oral light 400–800,
        # common 800–1500, strong 1.5–3 — first two are µg miscoded as mg).
        # Source data is structurally untrustworthy; show nothing rather
        # than a "common 800 mg" tier of a fentanyl analogue.
        tiers_flat = [v for v in (t, ll, lu, cl, cu, sl, su, h) if v is not None and v > 0]
        if len(tiers_flat) >= 2:
            for prev, nxt in zip(tiers_flat, tiers_flat[1:], strict=False):
                if prev > nxt * 10:
                    self.stats.setdefault("dropped_inverted_tiers", 0)
                    self.stats["dropped_inverted_tiers"] += 1
                    return

        # Monotonicity sanity check #2: tier-upper regression. Each tier's
        # upper bound must be ≥ the previous tier's upper bound. Catches
        # cases like Cloniprazepam oral light 1–5 mg, common 1–2 mg —
        # `level(dose)` would classify a 3 mg dose as "light" even though
        # it's above the common upper bound, which is misleading.
        tier_uppers = [
            (name, val)
            for name, val in (("light", lu), ("common", cu), ("strong", su), ("heavy", h))
            if val is not None and val > 0
        ]
        if len(tier_uppers) >= 2:
            for (_, prev), (_, nxt) in zip(tier_uppers, tier_uppers[1:], strict=False):
                if prev > nxt:
                    self.stats.setdefault("dropped_regressed_tiers", 0)
                    self.stats["dropped_regressed_tiers"] += 1
                    return

        # Class-keyed dose-magnitude sanity check. Each tag the substance
        # carries (across every source seen so far) contributes a max-dose
        # ceiling in mg; the effective ceiling for this row is the strictest
        # of them. Any tier value that, once converted to mg, exceeds the
        # ceiling indicates source-data unit confusion or a content error
        # — the same failure mode as the BLOCKER curated overrides this
        # session (Valerylfentanyl oral "50 mg", Acetylfentanyl insufflation
        # "10–15 mg common", etc.) but caught at ingest rather than after
        # the audit.
        tags = self.substance_tags.get(sid, ())
        ceilings = [_CLASS_DOSE_CEILING_MG[t] for t in tags if t in _CLASS_DOSE_CEILING_MG]
        if ceilings:
            factor = _unit_to_mg_factor(unit)
            if factor is not None:
                ceiling_mg = min(ceilings)
                for v in tiers_flat:
                    if v * factor > ceiling_mg:
                        self.stats.setdefault("dropped_class_dose_ceiling", 0)
                        self.stats["dropped_class_dose_ceiling"] += 1
                        return

        try:
            self.cur.execute(
                "INSERT INTO dose_ranges(substance_id, route, source_id, unit, threshold, light_lower, light_upper, common_lower, common_upper, strong_lower, strong_upper, heavy, notes, salt_form, citation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    sid,
                    route,
                    src,
                    unit or "mg",
                    t,
                    ll,
                    lu,
                    cl,
                    cu,
                    sl,
                    su,
                    h,
                    notes,
                    salt_form,
                    self.cite(citation),
                ),
            )
            self.stats["dose_ranges"] += 1
        except sqlite3.IntegrityError:
            pass

    def add_peptide_profile(self, sid: int, source_slug: str, profile: dict) -> None:
        """Insert the 1:1 peptide/biologic reference row. No-op if every field
        is empty (so a bare `{}` doesn't create a useless row)."""
        if not isinstance(profile, dict):
            return
        storage = profile.get("storage") if isinstance(profile.get("storage"), dict) else {}
        fields = (
            profile.get("sequence"),
            profile.get("suppliedForm"),
            to_float(profile.get("typicalVialMg")),
            profile.get("reconstitutionSolvent"),
            storage.get("temperature"),
            to_float(profile.get("iuPerMg")),
        )
        if not any(v is not None for v in fields):
            return
        src = self.source_ids.get(source_slug)
        try:
            self.cur.execute(
                "INSERT INTO peptide_profiles(substance_id, source_id, sequence, supplied_form, "
                "typical_vial_mg, reconstitution_solvent, storage_temperature, "
                "storage_light_sensitive, reconstituted_stability_days, iu_per_mg) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    sid,
                    src,
                    profile.get("sequence"),
                    profile.get("suppliedForm"),
                    to_float(profile.get("typicalVialMg")),
                    profile.get("reconstitutionSolvent"),
                    storage.get("temperature"),
                    1 if storage.get("lightSensitive") else 0,
                    to_float(storage.get("reconstitutedStabilityDays")),
                    to_float(profile.get("iuPerMg")),
                ),
            )
            self.stats["peptide_profiles"] = self.stats.get("peptide_profiles", 0) + 1
        except sqlite3.IntegrityError:
            pass

    def add_protocol_dosing(
        self,
        sid: int,
        source_slug: str,
        route: str,
        unit: str,
        protocol: dict,
        salt_form: str | None = None,
    ) -> None:
        """Insert a clinical-protocol dosing row (peptides/Rx). Requires a
        frequency — that's the minimum that makes a schedule meaningful. An
        optional `source` ref on the protocol is recorded as its citation."""
        route = normalise_route(route)
        if not route or not isinstance(protocol, dict):
            return
        freq = protocol.get("frequency")
        if not freq:
            return
        src = self.source_ids[source_slug]
        titration = protocol.get("titration")
        titration_json = json.dumps(titration, ensure_ascii=False) if titration else None
        try:
            self.cur.execute(
                "INSERT INTO protocol_dosing(substance_id, route, source_id, unit, low_amount, "
                "high_amount, frequency, titration_json, course_duration, notes, salt_form, citation_id) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    sid,
                    route,
                    src,
                    unit or None,
                    to_float(protocol.get("lowAmount")),
                    to_float(protocol.get("highAmount")),
                    freq,
                    titration_json,
                    protocol.get("courseDuration"),
                    protocol.get("notes"),
                    salt_form,
                    self.cite(protocol.get("source")),
                ),
            )
            self.stats["protocol_dosing"] = self.stats.get("protocol_dosing", 0) + 1
        except sqlite3.IntegrityError:
            pass

    def add_substance_citation(self, sid: int, ref: str) -> None:
        """Link a substance-level primary reference (the curated `sources` array)
        to the compound. Free-text labels and URLs both dedup via cite()."""
        cid = self.cite(ref)
        if cid is None:
            return
        try:
            self.cur.execute(
                "INSERT INTO substance_citations(substance_id, citation_id) VALUES (?, ?)",
                (sid, cid),
            )
            self.stats["substance_citations"] = self.stats.get("substance_citations", 0) + 1
        except sqlite3.IntegrityError:
            pass

    def prune_generic_book_citations(self) -> int:
        """Drop the generic PIHKAL/TIHKAL index link from a substance that also
        cites its specific chapter. Erowid's ``tihkal.shtml`` / ``pihkal.shtml``
        are book front-matter; ``tihkalNN.shtml`` / ``pihkalNN.shtml`` are the
        per-compound entries. Many substances carry both, so the index page reads
        as a duplicate of the real chapter (the "TIHKAL referenced twice" case).
        The generic citation row stays for substances that have only it."""
        rows = self.cur.execute(
            """
            SELECT sc.substance_id, sc.citation_id, c.url
              FROM substance_citations sc
              JOIN citations c ON c.id = sc.citation_id
             WHERE c.url LIKE '%erowid.org/library/books_online/%hkal/%'
            """
        ).fetchall()
        by_sub: dict[int, list[tuple[int, str]]] = defaultdict(list)
        for sub, cid, url in rows:
            by_sub[sub].append((cid, url or ""))
        generic_re = re.compile(r"/(?:pi|ti)hkal\.shtml(?:[?#].*)?$", re.I)
        specific_re = re.compile(r"/(?:pi|ti)hkal\d+\.shtml(?:[?#].*)?$", re.I)
        removed = 0
        for sub, items in by_sub.items():
            if not any(specific_re.search(u) for _, u in items):
                continue
            for cid, u in items:
                if generic_re.search(u):
                    self.cur.execute(
                        "DELETE FROM substance_citations WHERE substance_id=? AND citation_id=?",
                        (sub, cid),
                    )
                    removed += 1
        return removed

    def drop_dead_citations(self, cache_path: Path) -> int:
        """Remove citations the link validator confirmed dead (HTTP 404/410) so
        the app never ships a broken reference link. Reads the committed
        link-cache.json — the audit trail of what we checked. A fresh citation
        not yet in the cache is kept until the next validation run; unknown /
        bot-blocked links are NOT removed (they aren't proof of death)."""
        if not cache_path.exists():
            return 0
        cache = json.loads(cache_path.read_text())
        dead = [u for u, e in cache.items() if e.get("verdict") == "dead"]
        if not dead:
            return 0
        # Fact tables that carry a nullable citation_id (everything except the
        # substance_citations link table, which we clear by deletion instead).
        cit_tables = [
            t
            for (t,) in self.cur.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            ).fetchall()
            if t != "substance_citations"
            and any(
                col[1] == "citation_id"
                for col in self.cur.execute(f"PRAGMA table_info({t})").fetchall()
            )
        ]
        removed = 0
        for url in dead:
            for (cid,) in self.cur.execute(
                "SELECT id FROM citations WHERE url=?", (url,)
            ).fetchall():
                self.cur.execute("DELETE FROM substance_citations WHERE citation_id=?", (cid,))
                for t in cit_tables:
                    self.cur.execute(f"UPDATE {t} SET citation_id=NULL WHERE citation_id=?", (cid,))
                self.cur.execute("DELETE FROM citations WHERE id=?", (cid,))
                removed += 1
        return removed

    def add_duration_profile(
        self,
        sid: int,
        source_slug: str,
        route: str,
        profile: dict,
        citation: str | None = None,
        salt_form: str | None = None,
    ) -> None:
        route = normalise_route(route)
        if not route or not profile:
            return
        src = self.source_ids[source_slug]
        for phase in ("onset", "comeup", "peak", "offset", "afterglow", "total"):
            p = profile.get(phase)
            if not p:
                continue
            mn = to_float(p.get("min"))
            mx = to_float(p.get("max"))
            if mn is None or mx is None:
                continue
            try:
                self.cur.execute(
                    "INSERT INTO durations(substance_id, route, source_id, phase, min_minutes, max_minutes, salt_form, citation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                    (sid, route, src, phase, mn, mx, salt_form, self.cite(citation)),
                )
                self.stats["durations"] += 1
            except sqlite3.IntegrityError:
                pass

    _DOA_UNIT_MINUTES = {
        "hour": 60,
        "hours": 60,
        "h": 60,
        "day": 1440,
        "days": 1440,
        "d": 1440,
        "week": 1440 * 7,
        "weeks": 1440 * 7,
        "w": 1440 * 7,
        "month": 1440 * 30,
        "months": 1440 * 30,
        "mo": 1440 * 30,
    }

    def add_duration_of_action(
        self,
        sid: int,
        source_slug: str,
        route: str,
        doa: dict,
        citation: str | None = None,
        salt_form: str | None = None,
    ) -> None:
        """Ingest a long-acting release/duration-of-action window ({min, max, unit})."""
        route = normalise_route(route)
        if not route or not isinstance(doa, dict):
            return
        mn = to_float(doa.get("min"))
        mx = to_float(doa.get("max"))
        if mn is None or mx is None:
            return
        factor = self._DOA_UNIT_MINUTES.get(str(doa.get("unit", "days")).lower(), 1440)
        src = self.source_ids[source_slug]
        try:
            self.cur.execute(
                "INSERT INTO durations_of_action(substance_id, route, source_id, min_minutes, max_minutes, salt_form, citation_id) VALUES (?, ?, ?, ?, ?, ?, ?)",
                (sid, route, src, mn * factor, mx * factor, salt_form, self.cite(citation)),
            )
            self.stats["durations_of_action"] = self.stats.get("durations_of_action", 0) + 1
        except sqlite3.IntegrityError:
            pass

    # Substances (canonical_name lowercased) whose acute `durations` are a
    # chronic / therapeutic-timescale miscode — there is no genuine
    # onset→peak→offset curve. Drop ALL their duration rows so the dose logs as a
    # point marker and no multi-day "Total" surfaces on the card. Deliberately
    # excludes genuinely-long *acute* trips (the DOx family, long-acting benzos,
    # ibogaine, bromo-dragonfly, 2-DPMP / desoxypipradrol), which are correct and
    # left intact. See acute-vs-depot-duration.
    DURATION_SCRUB_NAMES = {
        "tranylcypromine",  # MAOI: 10–21 d is enzyme regeneration, not acute effect
        "acamprosate",  # anti-craving, steady-state med
        "fluconazole",  # antifungal dosing interval
        "phenytoin",  # anticonvulsant, chronic
        "nadolol",  # beta-blocker, chronic
        "sibutramine",  # withdrawn appetite suppressant, chronic
        "arimistane",  # aromatase-inhibitor supplement
        "5-amino-1mq",  # NNMT-inhibitor supplement
        "magnesium glycinate",
        "magnesium citrate",
        "creatine",
        "creatine monohydrate",
        "pqq",
        "vitamin b6",
        "panax ginseng",
        "citicoline",
        "theobromine",  # mild, very-long; no meaningful acute curve
    }

    # Real depot / long-acting release windows that arrived miscoded as acute
    # `durations`. Move them to `durations_of_action` (the card's "Release window"
    # row) and drop the bogus acute rows for that route only. Keyed by
    # canonical_name lowercased → [(route, min, max, unit)].
    DURATION_TO_DOA = {
        "estradiol": [
            ("intramuscular", 7, 28, "days"),  # depot ester injection
            ("transdermal", 1, 3, "days"),  # patch
        ],
        "buprenorphine": [
            ("transdermal", 3, 7, "days"),  # patch
        ],
        "fentanyl": [
            ("transdermal", 2, 3, "days"),  # 72 h patch
        ],
        "liraglutide": [
            ("subcutaneous", 1, 1, "days"),  # daily GLP-1 injection
        ],
    }

    def scrub_durations(self) -> dict:
        """Remove chronic/therapeutic durations miscoded as acute curves, and
        migrate real depot/long-acting windows into ``durations_of_action``.

        Runs after all ingest but BEFORE ``classify_compounds`` so the
        ``duration_implausible`` flag is baked from the cleaned table."""
        cur = self.cur
        stats = {"scrub_substances": 0, "scrub_rows": 0, "migrated_doa": 0}
        name_to_id: dict[str, int] = {}
        for sid, cname in cur.execute("SELECT id, canonical_name FROM substances"):
            if cname:
                name_to_id[cname.lower()] = sid

        for name in self.DURATION_SCRUB_NAMES:
            sid = name_to_id.get(name)
            if sid is None:
                continue
            n = cur.execute("DELETE FROM durations WHERE substance_id = ?", (sid,)).rowcount
            if n:
                stats["scrub_substances"] += 1
                stats["scrub_rows"] += n

        for name, entries in self.DURATION_TO_DOA.items():
            sid = name_to_id.get(name)
            if sid is None:
                continue
            for route, mn, mx, unit in entries:
                r = normalise_route(route)
                deleted = cur.execute(
                    "DELETE FROM durations WHERE substance_id = ? AND route = ?",
                    (sid, r),
                ).rowcount
                stats["scrub_rows"] += max(deleted, 0)
                self.add_duration_of_action(
                    sid, "piru-curated", r, {"min": mn, "max": mx, "unit": unit}
                )
                stats["migrated_doa"] += 1
        return stats

    def add_half_life(
        self, sid: int, source_slug: str, minutes: float, citation: str | None = None
    ) -> None:
        if minutes is None:
            return
        src = self.source_ids[source_slug]
        try:
            self.cur.execute(
                "INSERT INTO half_lives(substance_id, source_id, half_life_minutes, citation_id) VALUES (?, ?, ?, ?)",
                (sid, src, minutes, self.cite(citation)),
            )
            self.stats["half_lives"] += 1
        except sqlite3.IntegrityError:
            pass

    def add_mechanism_summary(
        self,
        sid: int,
        source_slug: str,
        summary: str,
        description: str | None = None,
        citation: str | None = None,
        language: str = "en",
        machine_translated: bool = False,
    ) -> None:
        if not summary:
            return
        src = self.source_ids[source_slug]
        try:
            self.cur.execute(
                "INSERT INTO mechanisms_summary(substance_id, source_id, summary, description, language, machine_translated, citation_id) VALUES (?, ?, ?, ?, ?, ?, ?)",
                (
                    sid,
                    src,
                    summary,
                    description,
                    language,
                    1 if machine_translated else 0,
                    self.cite(citation),
                ),
            )
            self.stats["mechanisms_summary"] += 1
        except sqlite3.IntegrityError:
            pass

    def add_description(
        self,
        sid: int,
        source_slug: str,
        text: str,
        language: str = "en",
        machine_translated: bool = False,
        citation: str | None = None,
    ) -> None:
        text = (text or "").strip()
        if not text:
            return
        src = self.source_ids[source_slug]
        try:
            self.cur.execute(
                "INSERT INTO descriptions(substance_id, source_id, text, language, machine_translated, citation_id) VALUES (?, ?, ?, ?, ?, ?)",
                (sid, src, text, language, 1 if machine_translated else 0, self.cite(citation)),
            )
            self.stats["descriptions"] = self.stats.get("descriptions", 0) + 1
        except sqlite3.IntegrityError:
            pass

    def add_indication(self, sid: int, source_slug: str, text: str) -> None:
        text = (text or "").strip()
        if not text:
            return
        src = self.source_ids[source_slug]
        try:
            self.cur.execute(
                "INSERT INTO indications(substance_id, source_id, text) VALUES (?, ?, ?)",
                (sid, src, text),
            )
            self.stats["indications"] += 1
        except sqlite3.IntegrityError:
            pass

    def add_contraindication(
        self, sid: int, source_slug: str, text: str, *, boxed: bool = False
    ) -> None:
        text = (text or "").strip()
        if not text:
            return
        src = self.source_ids[source_slug]
        try:
            self.cur.execute(
                "INSERT INTO contraindications(substance_id, source_id, text, is_boxed_warning) VALUES (?, ?, ?, ?)",
                (sid, src, text, 1 if boxed else 0),
            )
            self.stats["contraindications"] += 1
        except sqlite3.IntegrityError:
            pass

    def add_diazepam_equivalent(
        self,
        sid: int,
        source_slug: str,
        *,
        dose_mg: float | None,
        equivalent_diazepam_mg: float | None,
        display_text: str | None,
    ) -> None:
        src = self.source_ids[source_slug]
        try:
            self.cur.execute(
                "INSERT INTO diazepam_equivalents(substance_id, source_id, dose_mg, equivalent_diazepam_mg, display_text) VALUES (?, ?, ?, ?, ?)",
                (sid, src, dose_mg, equivalent_diazepam_mg, display_text),
            )
            self.stats["diazepam_equivalents"] += 1
        except sqlite3.IntegrityError:
            pass

    def add_effect(
        self,
        sid: int,
        source_slug: str,
        text: str,
        kind: str | None = None,
        language: str = "en",
        machine_translated: bool = False,
    ) -> None:
        if not text:
            return
        # Whitelist + categorize against the canonical PsychonautWiki subjective
        # effect index. The `effects` arrays across every source are heavily
        # polluted with non-effects — TripSit/Erowid mis-ingest substance-summary
        # prose and PiHKAL/TiHKAL dose-report fragments, and curated NPS files
        # dump SAR/risk descriptors ("DAT-selective DRI", "No human data"). Only
        # genuine PW taxonomy terms survive, each tagged with its category so the
        # detail view can group them. Source JSON is untouched, so relocating the
        # descriptor blurbs to a dedicated notes field later remains possible.
        category = PW_EFFECT_CATEGORY.get(normalize_effect(text))
        if category is None:
            self.stats["effects_dropped"] = self.stats.get("effects_dropped", 0) + 1
            return
        # Controlled-vocabulary reference (Track 1). Deterministic — `text` is
        # already a whitelisted PW name, so this resolves by normalized lookup
        # (no fuzzy auto-merge). NULL keeps the raw `text` as the localized
        # fallback; such strings are surfaced as curation candidates, not dropped.
        vocab_id = vocab_id_for(text)
        if vocab_id is None:
            self.effect_vocab_unmatched[text] += 1
        src = self.source_ids[source_slug]
        self.cur.execute(
            "INSERT INTO effects(substance_id, source_id, text, kind, effect_category, language, machine_translated, vocab_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (sid, src, text, kind, category, language, 1 if machine_translated else 0, vocab_id),
        )
        self.stats["effects"] += 1

    def add_subjective_effect(
        self,
        sid: int,
        source_slug: str,
        name: str,
        description: str | None = None,
        language: str = "en",
        machine_translated: bool = False,
    ) -> None:
        if not name:
            return
        src = self.source_ids[source_slug]
        self.cur.execute(
            "INSERT INTO subjective_effects(substance_id, source_id, name, description, language, machine_translated) VALUES (?, ?, ?, ?, ?, ?)",
            (sid, src, name, description, language, 1 if machine_translated else 0),
        )
        self.stats["subjective_effects"] += 1

    def add_tolerance(self, sid: int, source_slug: str, t: dict) -> None:
        if not t:
            return
        src = self.source_ids[source_slug]
        try:
            self.cur.execute(
                "INSERT INTO tolerance(substance_id, source_id, half_life_days, full_reset_days, build_rate, notes) VALUES (?, ?, ?, ?, ?, ?)",
                (
                    sid,
                    src,
                    to_float(t.get("halfLife") or t.get("half_life_days")),
                    to_float(t.get("fullResetDays") or t.get("full_reset_days")),
                    t.get("buildRate") or t.get("build_rate"),
                    t.get("notes"),
                ),
            )
            self.stats["tolerance"] += 1
        except sqlite3.IntegrityError:
            pass

    # ---- deep-pharma inserters ----

    def add_binding(self, sid: int, source_slug: str, b: dict) -> None:
        if not isinstance(b, dict) or not b.get("target"):
            return
        src = self.source_ids[source_slug]
        ki_ci = b.get("ki_ci_nm") or [None, None]
        self.cur.execute(
            "INSERT INTO bindings(substance_id, target, action, ki_nm, ki_ci_lower_nm, ki_ci_upper_nm, kd_nm, ec50_nm, ic50_nm, emax_pct, intrinsic_activity_pct, reference_agonist, species, tissue_or_cell, radioligand, assay_notes, source_id, citation_id, is_review, notes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                sid,
                b.get("target"),
                b.get("action") or "modulator",
                to_float(b.get("ki_nm")),
                to_float(ki_ci[0]) if isinstance(ki_ci, list) and len(ki_ci) > 0 else None,
                to_float(ki_ci[1]) if isinstance(ki_ci, list) and len(ki_ci) > 1 else None,
                to_float(b.get("kd_nm")),
                to_float(b.get("ec50_nm")),
                to_float(b.get("ic50_nm")),
                to_float(b.get("emax_pct")),
                to_float(b.get("intrinsic_activity_pct")),
                b.get("reference_agonist"),
                b.get("species"),
                b.get("tissue_or_cell"),
                b.get("radioligand_or_probe") or b.get("radioligand"),
                b.get("assay_buffer_notes") or b.get("assay_notes"),
                src,
                self.cite(b.get("reference")),
                1 if b.get("is_review") else 0,
                b.get("notes"),
            ),
        )
        self.stats["bindings"] += 1

    def add_functional(self, sid: int, source_slug: str, f: dict) -> None:
        if not isinstance(f, dict) or not f.get("target"):
            return
        src = self.source_ids[source_slug]
        self.cur.execute(
            "INSERT INTO functional_assays(substance_id, target, readout, ec50_nm, ic50_nm, emax_pct, reference_agonist, species, cell_system, source_id, citation_id, notes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                sid,
                f.get("target"),
                f.get("readout") or "unspecified",
                to_float(f.get("ec50_nm")),
                to_float(f.get("ic50_nm")),
                to_float(f.get("emax_pct")),
                f.get("reference_agonist"),
                f.get("species"),
                f.get("cell_system"),
                src,
                self.cite(f.get("reference")),
                f.get("notes"),
            ),
        )
        self.stats["functional_assays"] += 1

    def add_biased(self, sid: int, source_slug: str, b: dict) -> None:
        if not isinstance(b, dict) or not b.get("target"):
            return
        src = self.source_ids[source_slug]
        pathways = b.get("pathways_compared") or []
        if isinstance(pathways, list):
            pathways = ",".join(pathways)
        self.cur.execute(
            "INSERT INTO biased_agonism(substance_id, target, pathways_compared, bias_factor_log, bias_reference_compound, interpretation, source_id, citation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (
                sid,
                b.get("target"),
                pathways,
                to_float(b.get("bias_factor_log")),
                b.get("bias_reference_compound"),
                b.get("interpretation"),
                src,
                self.cite(b.get("reference")),
            ),
        )
        self.stats["biased_agonism"] += 1

    def add_oligomer(self, sid: int, source_slug: str, o: dict) -> None:
        if not isinstance(o, dict) or not o.get("complex"):
            return
        src = self.source_ids[source_slug]
        self.cur.execute(
            "INSERT INTO receptor_oligomers(substance_id, complex_description, evidence_type, functional_consequence, source_id, citation_id) VALUES (?, ?, ?, ?, ?, ?)",
            (
                sid,
                o.get("complex"),
                o.get("evidence"),
                o.get("functional_consequence"),
                src,
                self.cite(o.get("reference")),
            ),
        )
        self.stats["receptor_oligomers"] += 1

    def add_downstream(self, sid: int, source_slug: str, summary: str) -> None:
        if not summary:
            return
        src = self.source_ids[source_slug]
        try:
            self.cur.execute(
                "INSERT INTO downstream_signalling(substance_id, source_id, summary) VALUES (?, ?, ?)",
                (sid, src, summary),
            )
            self.stats["downstream_signalling"] += 1
        except sqlite3.IntegrityError:
            pass

    def add_neuroimaging(self, sid: int, source_slug: str, n: dict) -> None:
        if not isinstance(n, dict) or not n.get("modality"):
            return
        src = self.source_ids[source_slug]
        self.cur.execute(
            "INSERT INTO neuroimaging(substance_id, modality, finding, source_id, citation_id) VALUES (?, ?, ?, ?, ?)",
            (sid, n.get("modality"), n.get("finding") or "", src, self.cite(n.get("reference"))),
        )
        self.stats["neuroimaging"] += 1

    def add_pk_route(self, sid: int, source_slug: str, r: dict) -> None:
        if not isinstance(r, dict) or not r.get("route"):
            return
        route = normalise_route(r.get("route", ""))
        if not route:
            return
        src = self.source_ids[source_slug]
        self.cur.execute(
            "INSERT INTO pk_routes(substance_id, route, source_id, bioavailability_pct, cmax_ng_per_ml, tmax_min, auc_0_inf_ng_h_per_ml, half_life_min, vd_l_per_kg, clearance_ml_per_min_per_kg, protein_binding_pct, dose_in_study_mg, subject_n, demographics, citation_id, notes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                sid,
                route,
                src,
                to_float(r.get("bioavailability_pct")),
                to_float(r.get("cmax_ng_per_ml")),
                to_float(r.get("tmax_min")),
                to_float(r.get("auc_0_inf_ng_h_per_ml")),
                to_float(r.get("half_life_min")),
                to_float(r.get("vd_l_per_kg")),
                to_float(r.get("clearance_ml_per_min_per_kg")),
                to_float(r.get("protein_binding_pct")),
                to_float(r.get("dose_in_study_mg")),
                to_int(r.get("subject_n")),
                r.get("subject_demographics") or r.get("demographics"),
                self.cite(r.get("reference")),
                r.get("notes"),
            ),
        )
        self.stats["pk_routes"] += 1

    def add_conc_effect(self, sid: int, source_slug: str, c: dict) -> None:
        if not isinstance(c, dict) or not c.get("effect"):
            return
        src = self.source_ids[source_slug]
        self.cur.execute(
            "INSERT INTO concentration_effects(substance_id, source_id, effect, concentration_unit, threshold, peak_effect, citation_id) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (
                sid,
                src,
                c.get("effect"),
                c.get("concentration_unit") or "ng/mL",
                to_float(c.get("threshold")),
                to_float(c.get("peak_effect")),
                self.cite(c.get("reference")),
            ),
        )
        self.stats["concentration_effects"] += 1

    def add_metabolism(self, sid: int, source_slug: str, m: dict) -> None:
        if not isinstance(m, dict) or not m.get("enzyme"):
            return
        src = self.source_ids[source_slug]
        self.cur.execute(
            "INSERT INTO metabolism(substance_id, source_id, enzyme, fraction_of_clearance_pct, metabolite_name, metabolite_active, metabolite_potency_vs_parent_pct, citation_id, notes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                sid,
                src,
                m.get("enzyme"),
                to_float(m.get("fraction_of_clearance_pct")),
                m.get("metabolite_name"),
                1
                if m.get("metabolite_active")
                else (0 if m.get("metabolite_active") is False else None),
                to_float(m.get("metabolite_potency_vs_parent_pct")),
                self.cite(m.get("reference")),
                m.get("notes"),
            ),
        )
        self.stats["metabolism"] += 1

    def add_ddi(self, sid: int, source_slug: str, d: dict) -> None:
        if not isinstance(d, dict) or not d.get("with"):
            return
        src = self.source_ids[source_slug]
        self.cur.execute(
            "INSERT INTO drug_interactions_pk(substance_id, with_substance, mechanism, ki_um, clinical_effect, source_id, citation_id) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (
                sid,
                d.get("with"),
                d.get("mechanism"),
                to_float(d.get("ki_um")),
                d.get("clinical_effect"),
                src,
                self.cite(d.get("reference")),
            ),
        )
        self.stats["drug_interactions_pk"] += 1

    def add_pgx(
        self, sid: int, source_slug: str, gene: str, phenotype: str, citation: str | None = None
    ) -> None:
        if not gene or not phenotype:
            return
        src = self.source_ids[source_slug]
        self.cur.execute(
            "INSERT INTO pharmacogenetics(substance_id, gene, phenotype_effects, source_id, citation_id) VALUES (?, ?, ?, ?, ?)",
            (sid, gene, phenotype, src, self.cite(citation)),
        )
        self.stats["pharmacogenetics"] += 1

    def add_off_target(self, sid: int, source_slug: str, o: dict) -> None:
        if not isinstance(o, dict) or not o.get("target"):
            return
        src = self.source_ids[source_slug]
        self.cur.execute(
            "INSERT INTO off_targets(substance_id, target, ki_or_ic50_nm, concern_level, clinical_consequence, source_id, citation_id) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (
                sid,
                o.get("target"),
                to_float(o.get("ki_or_ic50_nm")),
                o.get("concern_level"),
                o.get("clinical_consequence"),
                src,
                self.cite(o.get("reference")),
            ),
        )
        self.stats["off_targets"] += 1

    def add_class_context(self, ctx: dict, source_slug: str = "peer-review-primary") -> int | None:
        if not isinstance(ctx, dict):
            return None
        slug = ctx.get("class_context_id") or ctx.get("slug")
        name = ctx.get("class_name") or ctx.get("display_name") or slug
        if not slug or not name:
            return None
        src = self.source_ids.get(source_slug)
        try:
            self.cur.execute(
                "INSERT INTO class_contexts(slug, display_name, shared_mechanism, shared_pk, shared_safety, sar_summary, source_id) VALUES (?, ?, ?, ?, ?, ?, ?)",
                (
                    slug,
                    name,
                    ctx.get("shared_mechanism"),
                    ctx.get("shared_pk_summary") or ctx.get("shared_pk"),
                    ctx.get("shared_safety"),
                    ctx.get("sar_summary"),
                    src,
                ),
            )
            cid = self.cur.lastrowid
        except sqlite3.IntegrityError:
            row = self.cur.execute(
                "SELECT id FROM class_contexts WHERE slug = ?", (slug,)
            ).fetchone()
            cid = row[0] if row else None
        if cid:
            for ref in ctx.get("key_references") or []:
                citation_id = self.cite(ref)
                if citation_id:
                    try:
                        self.cur.execute(
                            "INSERT INTO class_citations(class_context_id, citation_id) VALUES (?, ?)",
                            (cid, citation_id),
                        )
                    except sqlite3.IntegrityError:
                        pass
            self.stats["class_contexts"] += 1
        return cid

    def link_substance_class(self, sid: int, class_context_id: int) -> None:
        try:
            self.cur.execute(
                "INSERT INTO substance_classes(substance_id, class_context_id) VALUES (?, ?)",
                (sid, class_context_id),
            )
        except sqlite3.IntegrityError:
            pass

    # ---- file ingesters ----

    def _ingest_substance_record(
        self,
        s: dict,
        slug: str,
        *,
        inchikey: str | None = None,
        pubchem_cid: int | None = None,
        cas: str | None = None,
    ) -> int | None:
        """Insert all facts from one BundledSubstance dict, attributing every
        row to the given source slug. Shared body for the merged-JSON and
        sourced-JSON ingesters.

        Records with chemistry-noise names ("(R)-...", "(+/-)-..." etc.) are
        skipped at the source — they're IUPAC artefacts, not substances anyone
        would log in a harm-reduction tracker.
        """
        name = s.get("name") or ""
        if is_chemistry_noise(name):
            return None
        # Fix up scraped-source mislabels (e.g. TripSit's "apap" → Acetaminophen)
        # so they merge with the properly-named entry rather than duplicating it.
        name = _SOURCED_NAME_FIX.get(normalise(name), name)
        # Chemical identifiers ride the provenance wrapper for scraped sources
        # (inchikey/pubchem_cid/cas kwargs); the curated overlay carries them —
        # plus formula/molarMass — on the substance object itself. Prefer the
        # wrapper, fall back to the object, so both paths populate the row.
        sid = self.upsert_substance(
            name,
            aliases=s.get("aliases") or [],
            inchikey=inchikey or s.get("inchikey"),
            pubchem_cid=pubchem_cid if pubchem_cid is not None else to_int(s.get("pubchemCID")),
            cas=cas or s.get("cas"),
            formula=s.get("formula"),
            molecular_weight=to_float(s.get("molarMass")),
            source_slug=slug,
        )
        if sid is None:
            return None
        # Curated presentation/sort overrides (also valid on override-only files).
        if slug == "piru-curated":
            if s.get("displayName"):
                self.cur.execute(
                    "UPDATE substances SET display_name = ? WHERE id = ?", (s["displayName"], sid)
                )
            if s.get("popularity") is not None:
                self.cur.execute(
                    "UPDATE substances SET popularity = ? WHERE id = ?",
                    (to_float(s["popularity"]), sid),
                )
        if s.get("category"):
            self.add_category(sid, slug, s["category"])
        for tag in s.get("tags") or []:
            self.add_tag(sid, slug, tag)
        for r in s.get("routes") or []:
            if not isinstance(r, dict):
                continue
            doses = r.get("doses") or {}
            route_ref = r.get("source")  # optional per-route citation (dose + duration)
            self.add_dose(
                sid,
                slug,
                r.get("route", ""),
                r.get("unit", "mg"),
                threshold=doses.get("threshold"),
                light=doses.get("light"),
                common=doses.get("common"),
                strong=doses.get("strong"),
                heavy=doses.get("heavy"),
                notes=r.get("notes"),
                citation=route_ref,
            )
            if r.get("duration"):
                self.add_duration_profile(
                    sid, slug, r.get("route", ""), r["duration"], citation=route_ref
                )
            if r.get("durationOfAction"):
                self.add_duration_of_action(
                    sid, slug, r.get("route", ""), r["durationOfAction"], citation=route_ref
                )
            if r.get("protocolDosing"):
                self.add_protocol_dosing(
                    sid, slug, r.get("route", ""), r.get("unit", "mg"), r["protocolDosing"]
                )
        if s.get("peptideProfile"):
            self.add_peptide_profile(sid, slug, s["peptideProfile"])
        if s.get("halfLifeMinutes") is not None:
            self.add_half_life(
                sid, slug, float(s["halfLifeMinutes"]), citation=s.get("halfLifeSource")
            )
        if s.get("mechanismOfAction"):
            moa = s["mechanismOfAction"]
            self.add_mechanism_summary(
                sid,
                slug,
                moa.get("summary") or moa.get("description") or "",
                description=moa.get("description"),
                citation=(moa.get("references") or [None])[0],
            )
            for b in moa.get("bindings") or []:
                if not isinstance(b, dict):
                    continue
                # Pass the binding through intact so a per-binding `reference`
                # (and any measured Ki/IC50) is preserved, not dropped.
                self.add_binding(sid, slug, {**b, "action": b.get("action") or "modulator"})
        # Substance-level references: the top-level `sources` plus any mechanism
        # `references`. Every distinct primary ref becomes a tappable citation.
        refs = list(s.get("sources") or [])
        refs += list((s.get("mechanismOfAction") or {}).get("references") or [])
        for ref in refs:
            if isinstance(ref, str) and ref.strip():
                self.add_substance_citation(sid, ref.strip())
        for e in s.get("effects") or []:
            self.add_effect(sid, slug, e)
        for se in s.get("subjectiveEffects") or []:
            if isinstance(se, dict):
                self.add_subjective_effect(sid, slug, se.get("name"), se.get("description"))
            elif isinstance(se, str):
                self.add_subjective_effect(sid, slug, se)
        if s.get("toleranceInfo"):
            self.add_tolerance(sid, slug, s["toleranceInfo"])
        return sid

    def ingest_curated_substances(self, directory: Path) -> list[str]:
        """Ingest the hand-curated per-substance files (data/curated/substances/
        *.json). Each file is one substance object matching the iOS `Substance`
        Codable; attributed to `piru-curated`. Run BEFORE the scraped sources so
        curated chemical identifiers win the COALESCE in `upsert_substance`.

        Returns the list of normalised curated names so the sourced-JSON
        ingester can treat them as known (and let Wikidata enrich rather than
        skip a noise-named variant of a curated compound)."""
        names: list[str] = []
        if not directory.is_dir():
            return names
        # Sort by filename for a deterministic, reproducible ingest order.
        for fp in sorted(directory.glob("*.json")):
            try:
                entry = json.loads(fp.read_text())
            except (ValueError, OSError) as exc:
                print(f"  WARNING: curated file {fp.name} failed to load: {exc}", file=sys.stderr)
                continue
            if not isinstance(entry, dict) or not entry.get("name"):
                print(
                    f"  WARNING: curated file {fp.name} is not a substance object", file=sys.stderr
                )
                continue
            names.append(normalise(entry["name"]))
            self._ingest_substance_record(
                entry,
                "piru-curated",
                inchikey=entry.get("inchikey"),
                pubchem_cid=to_int(entry.get("pubchemCID")),
                cas=entry.get("cas"),
            )
            # Additional browse homes (multi-class compounds). Primary category
            # stays the resolved winner; these only add browse membership.
            extra = entry.get("extraCategories") or []
            if extra:
                sid = self.substance_ids.get(normalise(entry["name"]))
                if sid is not None:
                    for cat in extra:
                        self.cur.execute(
                            "INSERT OR IGNORE INTO browse_extra_categories"
                            "(substance_id, category) VALUES(?, ?)",
                            (sid, cat),
                        )
        self.stats["curated_files"] = len(names)
        return names

    def ingest_sourced_substances(self, path: Path, *, known_names: set[str] | None = None) -> None:
        """SubstanceCollector's per-record sourced output. Each record carries
        its provenance (mapped 1:1 to sources.slug) so every fact gets
        attributed correctly without merge-time information loss.

        `piru-curated` records here are IGNORED — curated data is ingested
        directly from CURATED_DIR by ingest_curated_substances(). This keeps a
        single source of truth and is robust even if a stale collector run
        re-bakes the overlay into this file. `known_names` (the curated names)
        seed the Wikidata-noise allowlist so a noise-named Wikidata variant of a
        curated compound enriches it instead of being dropped.

        Wikidata's SPARQL net catches IUPAC chemistry noise that isn't useful
        in a harm-reduction library: stereo-prefixed variants like
        "(+/-)-noradrenaline", "(R)-N-trans-feruloyloctopamine",
        "(E,E)-bastadin 19" — chemical curiosities, not consumed substances.
        Skip wikidata records whose name matches the noise pattern UNLESS
        another source also carries them (in which case the merged record
        keeps real data and the wikidata row just adds aliases).
        """
        if not path.exists():
            return
        data = json.loads(path.read_text())
        if not isinstance(data, list):
            return
        # Index non-wikidata names so we can let wikidata enrich them but
        # skip the wikidata-only noise rows. Seed with the curated names too —
        # curated substances were ingested separately and are real compounds, so
        # a wikidata noise-variant of one should enrich it, not be dropped.
        non_wikidata_names: set[str] = set(known_names or set())
        for rec in data:
            substance = rec.get("substance")
            slug = rec.get("provenance")
            if isinstance(substance, dict) and slug and slug != "wikidata":
                name = (substance.get("name") or "").strip()
                if name:
                    non_wikidata_names.add(normalise(name))

        records = sorted(
            data,
            key=lambda r: (
                r.get("provenance", ""),
                (r.get("substance") or {}).get("name", "").lower(),
            ),
        )
        for rec in records:
            substance = rec.get("substance")
            slug = rec.get("provenance")
            if not isinstance(substance, dict) or not slug:
                continue
            # Curated data is ingested from CURATED_DIR, not here — ignore any
            # stale piru-curated rows a collector run may have left behind.
            if slug == "piru-curated":
                continue
            if slug == "wikidata":
                name = (substance.get("name") or "").strip()
                if is_chemistry_noise(name) and normalise(name) not in non_wikidata_names:
                    continue
            if slug not in self.source_ids:
                slug = "piru-curated"
            self._ingest_substance_record(
                substance,
                slug,
                inchikey=rec.get("inchiKey"),
                pubchem_cid=to_int(rec.get("pubchemCID")),
                cas=rec.get("cas"),
            )

    def ingest_bundled_substances(self, path: Path) -> None:
        """Legacy ingester for the post-merge bundled JSON. Attributes
        everything to piru-curated. Used only when sourced-substances.json is
        absent (e.g. a clean clone that hasn't run the Swift collector yet);
        in that case we still want *something* in the DB rather than nothing.
        """
        if not path.exists():
            return
        data = json.loads(path.read_text())
        for s in sorted(data, key=lambda x: x.get("name", "").lower()):
            self._ingest_substance_record(s, "piru-curated")

    def ingest_psychonautwiki_snapshot(self, path: Path) -> None:
        """Ingest the PsychonautWiki GraphQL snapshot generated by
        ``Tools/SubstanceCollector/fetch-psychonautwiki.py``. Each record has
        the same shape as ``sourced-substances.json`` records but is read
        from a separate file so the snapshot is regeneratable and reviewable
        independently of the SubstanceCollector pipeline. Without this PW
        contributes zero rows and ~46% of substances lose their duration
        coverage compared to the pre-merge runtime-fetch era.
        """
        if not path.exists():
            print(
                f"  (no psychonautwiki snapshot at {path}; run fetch-psychonautwiki.py)",
                file=sys.stderr,
            )
            return
        data = json.loads(path.read_text())
        if not isinstance(data, list):
            return
        for rec in sorted(data, key=lambda r: ((r.get("substance") or {}).get("name", "")).lower()):
            substance = rec.get("substance")
            if not isinstance(substance, dict):
                continue
            self._ingest_substance_record(substance, "psychonautwiki")

    def ingest_drug_community(self, path: Path) -> None:
        if not path.exists():
            return
        data = json.loads(path.read_text())
        slug = "drug.community"
        for s in sorted(data, key=lambda x: (x.get("drug_name") or "").lower()):
            raw = s.get("drug_name") or ""
            name, paren_aliases = split_compound_name(raw)
            if not name:
                continue
            alt = s.get("alternative_names") or []
            aliases = list({a for a in (paren_aliases + alt) if a and a.lower() != name.lower()})
            sid = self.upsert_substance(name, aliases=aliases, source_slug=slug)
            if sid is None:
                continue
            # Record the canonical drug.community page slug (from the full
            # original drug_name) so the app can deep-link /drug/<slug> reliably.
            self.cur.execute(
                "UPDATE substances SET drug_community_slug=COALESCE(drug_community_slug, ?) WHERE id=?",
                (dc_slugify(raw), sid),
            )
            if s.get("psychoactive_class"):
                self.add_category(sid, slug, s["psychoactive_class"])
            elif s.get("categories"):
                cats = s["categories"]
                if cats:
                    self.add_category(sid, slug, cats[0] if isinstance(cats, list) else str(cats))
            if s.get("chemical_class"):
                # drug.community sometimes stores a paragraph of chemistry here
                # rather than a class label; keep only concise labels as a chip.
                cc = str(s["chemical_class"]).strip()
                if cc and len(cc) <= 48 and ";" not in cc and "(" not in cc:
                    self.add_tag(sid, slug, f"class:{cc}")
            dosages = (s.get("dosages") or {}).get("routes_of_administration") or []
            for r in dosages:
                dr = r.get("dose_ranges") or {}
                row_unit = r.get("units") or "mg"
                threshold = self._parse_dc_scalar(dr.get("threshold"), row_unit)
                light = self._parse_dc_range(dr.get("light"), row_unit)
                common = self._parse_dc_range(dr.get("common"), row_unit)
                strong = self._parse_dc_range(dr.get("strong"), row_unit)
                heavy = self._parse_dc_scalar(dr.get("heavy"), row_unit)
                self.add_dose(
                    sid,
                    slug,
                    r.get("route", ""),
                    row_unit,
                    threshold=threshold,
                    light=light,
                    common=common,
                    strong=strong,
                    heavy=heavy,
                    notes=r.get("notes"),
                )
            for dc in s.get("duration_curves") or []:
                curve = dc.get("duration_curve")
                if not isinstance(curve, dict):
                    continue
                route = (dc.get("method") or "oral").lower()
                # drug.community labels each curve with its own unit. Earlier
                # versions assumed hours unconditionally, which inflated minute-
                # denominated entries (e.g. 6-MAM IV 90 min → 5400 min = 90 h)
                # by 60×. Always check the unit before converting.
                unit = (curve.get("units") or "hours").lower()
                if unit in ("h", "hour", "hours"):
                    to_minutes = 60.0
                elif unit in ("m", "min", "mins", "minute", "minutes"):
                    to_minutes = 1.0
                elif unit in ("s", "sec", "secs", "second", "seconds"):
                    to_minutes = 1.0 / 60.0
                elif unit in ("d", "day", "days"):
                    to_minutes = 60.0 * 24.0
                else:
                    to_minutes = 60.0
                # drug.community gives each phase as an ABSOLUTE [start, end]
                # window measured from ingestion (onset/peak/offset/after_effects
                # use start/end; only total_duration uses min/max). Piru's
                # DurationProfile instead stores per-phase *durations* that it
                # accumulates by midpoint to recover the curve boundaries. So we
                # convert by differencing consecutive absolute ends — this
                # reproduces the source's absolute boundaries exactly. The source
                # supplies windows, not duration uncertainty, so per-phase ranges
                # are degenerate (min == max); `total` keeps its real min/max.
                onset_b = self._dc_phase_bounds(curve.get("onset"))
                peak_b = self._dc_phase_bounds(curve.get("peak"))
                offset_b = self._dc_phase_bounds(curve.get("offset"))
                after_b = self._dc_phase_bounds(curve.get("after_effects"))

                profile = {}
                if onset_b:
                    onset_end = onset_b[1] * to_minutes
                    profile["onset"] = {"min": onset_end, "max": onset_end}
                if onset_b and peak_b:
                    comeup = max(0.0, (peak_b[0] - onset_b[1]) * to_minutes)
                    if comeup > 0:
                        profile["comeup"] = {"min": comeup, "max": comeup}
                if peak_b:
                    peak_len = max(0.0, (peak_b[1] - peak_b[0]) * to_minutes)
                    profile["peak"] = {"min": peak_len, "max": peak_len}
                if peak_b and offset_b:
                    # Normal case: offset spans from peak's end to offset's end,
                    # reproducing the source's absolute boundary. For the ~5% of
                    # malformed curves where the source gives offset the same or
                    # an earlier window as peak (offset.end <= peak.end), fall
                    # back to the offset window's own length so a comedown still
                    # renders instead of collapsing to zero.
                    offset_len = (offset_b[1] - peak_b[1]) * to_minutes
                    if offset_len <= 0:
                        offset_len = (offset_b[1] - offset_b[0]) * to_minutes
                    if offset_len > 0:
                        profile["offset"] = {"min": offset_len, "max": offset_len}
                if offset_b and after_b:
                    afterglow = max(0.0, (after_b[1] - offset_b[1]) * to_minutes)
                    if afterglow > 0:
                        profile["afterglow"] = {"min": afterglow, "max": afterglow}
                td = curve.get("total_duration")
                if isinstance(td, dict) and td.get("min") is not None and td.get("max") is not None:
                    profile["total"] = {
                        "min": float(td["min"]) * to_minutes,
                        "max": float(td["max"]) * to_minutes,
                    }
                if profile:
                    self.add_duration_profile(sid, slug, route, profile)
            for se in s.get("subjective_effects") or []:
                if isinstance(se, str):
                    self.add_subjective_effect(sid, slug, se)

    # drug.community phase-key aliases: source key → profile dict key.
    _DC_PHASE_KEY = {"after_effects": "afterglow", "total_duration": "total"}

    @staticmethod
    def _dc_phase_bounds(phase) -> tuple[float, float] | None:
        """Absolute (start, end) for a drug.community phase dict, in source units.

        Returns None when the phase is absent or malformed. Phase windows use
        `start`/`end`; `total_duration` (handled separately) uses `min`/`max`.
        """
        if not isinstance(phase, dict):
            return None
        start, end = phase.get("start"), phase.get("end")
        if start is None or end is None:
            return None
        try:
            return (float(start), float(end))
        except (TypeError, ValueError):
            return None

    # Unit-to-mg conversion factors. Anything not here keeps its row unit.
    _DC_UNIT_FACTORS = {
        "g": 1000.0,
        "mg": 1.0,
        "µg": 0.001,
        "ug": 0.001,
        "mcg": 0.001,
        "ng": 1e-6,
        "ml": 1.0,
        "l": 1000.0,
    }

    # Inline unit between a number and a range dash ("5 mg - 15 mg").
    # Stripped before the range regex so the trailing unit is the only one
    # left; without this ~100 drug.community ranges parsed as None.
    _DC_INLINE_UNIT_RE = re.compile(
        r"(\d)\s*(?:mg|µg|ug|mcg|ng|g|ml|l)\s*(?=[-–])",
        re.IGNORECASE,
    )

    @classmethod
    def _dc_clean(cls, s: str) -> str:
        # drug.community uses three thousand separators: comma ("1,000 mg"),
        # non-breaking space ("1 200 µg"), and regular space
        # ("1 000 µg"). Without normalising, `\d+` matches "1" and
        # silently truncates the value to 1.0.
        cleaned = str(s).replace(",", "").replace(" ", " ")
        # Collapse whitespace BETWEEN digits ("1 000" → "1000") but
        # preserve number-unit spacing ("5 mg").
        cleaned = re.sub(r"(?<=\d)\s+(?=\d)", "", cleaned)
        return cls._DC_INLINE_UNIT_RE.sub(r"\1", cleaned)

    # Match the FIRST unit token following a digit, tolerating operators
    # (+, >, <, ≥, ≤, ~, =, -) and whitespace between the number and unit.
    # The original `\d\s*unit` pattern silently failed on "200+ µg",
    # ">800 µg" etc. — those rows then inherited the row-level unit ("mg")
    # and stored e.g. Fentanyl oral heavy as 200 mg (lethal) instead of
    # 200 µg (= 0.2 mg). Using the first match (not last) is important
    # because drug.community frequently annotates the primary value with a
    # parenthetical equivalent — "0.01 mg (10 µg)" — and the primary unit
    # is always the first one.
    _DC_UNIT_TOKEN_RE = re.compile(
        r"\d[+\->≥<≤~=\s]*(g|mg|µg|ug|mcg|ng|ml|l)(?![a-z])",
        re.IGNORECASE,
    )

    @classmethod
    def _dc_unit_factor(cls, cleaned: str, row_unit: str) -> float:
        """If the value string contains an explicit unit that differs from the
        row's declared unit, return the conversion factor so the value can be
        rescaled into `row_unit`. Otherwise 1.0.

        drug.community frequently switches units inside a single dose row
        (e.g. row unit "mg" but heavy="200+ µg"). Without this conversion,
        Fentanyl oral heavy would store as 200 mg — a lethal value hundreds
        of times the actual 200 µg threshold.
        """
        m = cls._DC_UNIT_TOKEN_RE.search(cleaned)
        if not m:
            return 1.0
        inline = m.group(1).lower()
        if inline == row_unit.lower():
            return 1.0
        f_in = cls._DC_UNIT_FACTORS.get(inline)
        f_row = cls._DC_UNIT_FACTORS.get(row_unit.lower())
        if f_in is None or f_row is None or f_row == 0:
            return 1.0
        return f_in / f_row

    @classmethod
    def _parse_dc_scalar(cls, s: str | None, row_unit: str = "mg") -> float | None:
        if not s:
            return None
        cleaned = cls._dc_clean(s)
        m = re.search(r"(\d+(?:\.\d+)?)", cleaned)
        if not m:
            return None
        return float(m.group(1)) * cls._dc_unit_factor(cleaned, row_unit)

    @classmethod
    def _parse_dc_range(cls, s: str | None, row_unit: str = "mg") -> dict | None:
        if not s:
            return None
        cleaned = cls._dc_clean(s)
        m = re.search(r"(\d+(?:\.\d+)?)\s*[-–]\s*(\d+(?:\.\d+)?)", cleaned)
        if not m:
            return None
        factor = cls._dc_unit_factor(cleaned, row_unit)
        return {"lower": float(m.group(1)) * factor, "upper": float(m.group(2)) * factor}

    def promote_via_tags(self) -> dict[str, int]:
        """For each substance whose resolved category would be 'Other' (either
        because no source supplied a category, or every supplied category
        already normalised to 'Other'), check tags for a class-specific
        signal and insert a piru-curated category row that wins resolution.

        Returns counts of promotions per derived category.
        """
        # (priority-ordered tag predicates → canonical category)
        tag_rules: list[tuple[set[str], str]] = [
            ({"peptide", "peptide-mimetic"}, "Peptide"),
            # GABAergic must come before Anticonvulsant — gabapentin/pregabalin
            # carry both `gabapentinoid` AND `anticonvulsant` tags, but their
            # primary class is gabapentinoid (α2δ ligand). Without this
            # ordering they regress out of GABAergic into Anticonvulsant.
            ({"gabapentinoid", "alpha2-delta-ligand", "GABAergic"}, "GABAergic"),
            (
                {"anticonvulsant", "antiepileptic", "mood-stabilizer", "mood-stabiliser"},
                "Anticonvulsant",
            ),
            ({"antipsychotic", "atypical-antipsychotic", "typical-antipsychotic"}, "Antipsychotic"),
            (
                # NB: `NDRI` deliberately excluded — bupropion is an NDRI but so
                # are many stimulants (pyrovalerones like MD-PiHP). The NDRI tag
                # alone is not antidepressant-specific and used to drag stimulants
                # into Antidepressant. Require an antidepressant-class tag instead.
                {"antidepressant", "SSRI", "SNRI", "TCA", "MAOI", "SARI", "NaSSA"},
                "Antidepressant",
            ),
            ({"antihistamine", "H1-antagonist", "H2-antagonist", "deliriant"}, "Antihistamine"),
            (
                {
                    "cannabinoid",
                    "phytocannabinoid",
                    "synthetic-cannabinoid",
                    "semi-synthetic-cannabinoid",
                    "CB1-agonist",
                    "CB1-partial-agonist",
                },
                "Cannabinoid",
            ),
            (
                {
                    "opioid",
                    "mu-opioid-agonist",
                    "designer-opioid",
                    "nitazene",
                    "fentanyl-class-potency",
                },
                "Opioid",
            ),
            ({"dissociative", "NMDA-antagonist"}, "Dissociative"),
            ({"benzodiazepine"}, "Benzodiazepine"),
            ({"eugeroic", "wakefulness-promoting"}, "Eugeroic"),
            ({"AMPAkine", "ampakine", "AMPA-PAM"}, "AMPAkine"),
            ({"nootropic", "racetam", "nootropic-peptide"}, "Nootropic"),
            (
                {
                    "beta-blocker",
                    "antihypertensive",
                    "alpha2-agonist",
                    "alpha1-blocker",
                    "calcium-channel-blocker",
                },
                "Cardiovascular",
            ),
            (
                {"supplement", "vitamin", "mineral", "adaptogen", "amino-acid", "herbal"},
                "Supplement",
            ),
            ({"antiemetic"}, "Gastrointestinal"),
            ({"stimulant", "psychostimulant", "amphetamine", "cathinone-derivative"}, "Stimulant"),
            # Both `5HT2A-agonist` and `5-HT2A-agonist` (with hyphen) appear
            # depending on source — accept both. `tryptamine-not-phenethylamine`
            # is the peer-review-primary tag for classical tryptamine psychedelics.
            (
                {
                    "psychedelic",
                    "5HT2A-agonist",
                    "5-HT2A-agonist",
                    "phenethylamine-psychedelic",
                    "tryptamine-not-phenethylamine",
                    "psilocybe-mushroom",
                    "DMT-containing",
                    "PIHKAL",
                    "TIHKAL",
                },
                "Psychedelic",
            ),
            ({"empathogen", "entactogen"}, "Empathogen"),
            (
                {
                    "muscle-relaxant",
                    "Z-drug",
                    "orexin-antagonist",
                    "sedative-hypnotic",
                    "barbiturate",
                },
                "Depressant",
            ),
        ]

        # Substances whose effective resolved category is "Other" or absent.
        rows = self.cur.execute("""
            SELECT s.id
              FROM substances s
             WHERE NOT EXISTS (
                 SELECT 1 FROM categories c
                  WHERE c.substance_id = s.id AND c.category != 'Other'
             )
        """).fetchall()
        target_sids = [r[0] for r in rows]
        if not target_sids:
            return {}

        # Pull each substance's tag set (any source).
        tags_by_sid: dict[int, set[str]] = {sid: set() for sid in target_sids}
        for r in self.cur.execute(
            f"SELECT substance_id, tag FROM tags WHERE substance_id IN ({','.join('?' * len(target_sids))})",
            target_sids,
        ):
            tags_by_sid[r[0]].add(r[1])

        counts: dict[str, int] = {}
        for sid, tagset in tags_by_sid.items():
            for required_tags, canonical in tag_rules:
                if tagset & required_tags:
                    self.add_category(sid, "piru-curated", canonical)
                    counts[canonical] = counts.get(canonical, 0) + 1
                    break
        return counts

    # ---- external datasource ingesters (pyrls / medtap / benzos / nps) ----

    @staticmethod
    def _parse_regulatory(raw: str | None) -> str | None:
        """Normalise pyrls/medtap regulatory strings into a canonical token.
        pyrls: 'rx; Prescription only', 'otc; ...'; medtap: 'OTC' / 'Rx'."""
        if not raw:
            return None
        s = raw.lower()
        has_otc = "otc" in s or "over-the-counter" in s or "over the counter" in s
        has_rx = "rx" in s or "prescription" in s
        m = re.search(r"\bc([1-5])\b", s)
        if m:
            return f"controlled_schedule_{m.group(1)}"
        if has_otc and has_rx:
            return "rx_otc_dependent"
        if has_otc:
            return "otc"
        if has_rx:
            return "rx"
        return None

    @staticmethod
    def _as_text_list(value) -> list[str]:
        """pyrls indications are arrays; medtap are single strings. Normalise to
        a clean list, dropping placeholder text."""
        if value is None:
            return []
        items = value if isinstance(value, list) else [value]
        out: list[str] = []
        for it in items:
            t = (str(it) if it is not None else "").strip()
            if not t or t.lower() in ("enter section text here", "n/a", "none"):
                continue
            out.append(t)
        return out

    def reapply_curated_display_names(self, directory: Path) -> int:
        """Re-stamp curated `displayName` overrides onto the surviving rows after
        all dedup/fold passes. display_name is first set during curated ingest,
        but later merges (which pick a survivor and demote the other name to an
        alias) can land the survivor on the row that lacked the override — e.g.
        a FreeOD-introduced synonym absorbing the curated entry. Resolving each
        curated name through canonical-then-alias finds the survivor regardless
        of which name won, so the override is authoritative and applied last."""
        canon = {
            norm: sid
            for sid, norm in self.cur.execute("SELECT id, normalized_name FROM substances")
        }
        alias: dict[str, int] = {}
        for sid, anorm in self.cur.execute("SELECT substance_id, alias_normalized FROM aliases"):
            alias.setdefault(anorm, sid)
        n = 0
        for fp in sorted(directory.glob("*.json")):
            e = json.loads(fp.read_text())
            dn, nm = e.get("displayName"), e.get("name")
            if not dn or not nm or is_chemistry_noise(nm):
                continue
            sid = canon.get(normalise(nm)) or alias.get(normalise(nm))
            if sid is None:
                continue
            self.cur.execute("UPDATE substances SET display_name = ? WHERE id = ?", (dn, sid))
            n += 1
        return n

    def ingest_freeodwiki(self, path: Path) -> None:
        """FreeOD Wiki (CC BY-SA 4.0) Chinese harm-reduction data.

        Lowest priority, so its numeric facts (dose/duration) only FILL GAPS in
        English, while its zh text (description/mechanism/effects) is stored
        language-tagged so the app's locale-aware resolver floats it above
        higher-priority English sources when the app runs in Chinese. Optional
        machine-translated English fields (``*_en``) ride along as en rows that
        fill gaps for substances English sources don't cover.

        FreeOD pages are titled in Chinese; ``upsert_substance`` matches only by
        normalised canonical name, so we feed it a Latin name (from the page's
        extracted aliases) and keep the zh title as an alias — which also
        enriches Chinese search. Compounds with no Latin name keep their zh
        title as canonical (a new FreeOD-only substance).
        """
        if not path.exists():
            return
        data = json.loads(path.read_text())
        slug = "freeodwiki"
        created: list[str] = []
        # upsert_substance matches only by canonical name. FreeOD's English
        # names are frequently RC acronyms (DCK, O-DSMT, α-PVP) that exist in
        # the DB under a fuller canonical name with the acronym as an alias, so
        # resolve names against existing aliases too to avoid duplicate rows.
        # Canonical-name match first (strongest); alias match only for names
        # specific enough (≥4 chars) to avoid "K"/"E"/"X" false merges.
        # Alias- and display-name-keyed lookup. display_name is a presentation
        # override (e.g. "2-FA" for "2-Fluoroamphetamine") that is NOT in the
        # aliases table, so match it too or FreeOD duplicates those entries.
        existing_alias: dict[str, int] = {}
        for anorm, asid in self.cur.execute(
            "SELECT alias_normalized, substance_id FROM aliases"
        ).fetchall():
            existing_alias.setdefault(anorm, asid)
        for dname, dsid in self.cur.execute(
            "SELECT display_name, id FROM substances WHERE display_name IS NOT NULL"
        ).fetchall():
            existing_alias.setdefault(normalise(dname), dsid)

        def canonical_of(sid_: int) -> str | None:
            row = self.cur.execute(
                "SELECT canonical_name FROM substances WHERE id=?", (sid_,)
            ).fetchone()
            return row[0] if row else None

        def resolve_existing(cands: list[str]) -> str | None:
            for cand in cands:
                n = normalise(cand)
                sid_canon = self.substance_ids.get(n)
                sid_alias = existing_alias.get(n)
                # An acronym that is BOTH a canonical and an alias/display of a
                # *different* substance signals a pre-existing duplicate (e.g.
                # "2-FA" exists as its own row and as the display_name of the
                # curated "2-Fluoroamphetamine"). Prefer the fuller-named,
                # usually-curated alias target so FreeOD data lands there and
                # the later dedup keeps the canonical name, not the acronym.
                if sid_canon and sid_alias and sid_alias != sid_canon:
                    if name := canonical_of(sid_alias):
                        return name
                if sid_canon:
                    return cand
            for cand in cands:
                if len(cand) >= 3 and any(ch.isalpha() for ch in cand):
                    if sid_ := existing_alias.get(normalise(cand)):
                        if name := canonical_of(sid_):
                            return name
            return None

        for rec in sorted(data, key=lambda r: r.get("page_slug") or ""):
            title = (rec.get("title") or "").strip()
            if title in FREEOD_SKIP_PAGES:
                continue
            names = rec.get("names") or []
            canonical = _freeod_canonical_name(title, names)
            if not canonical:
                continue
            # Prefer an existing substance the page's names already resolve to.
            # A curated zh→English override (for fully-Chinese pages) leads the
            # candidate list so it both matches and supplies an English name.
            override = FREEOD_NAME_OVERRIDE.get(title)
            latin_cands = (
                ([override] if override else [])
                + [canonical]
                + [n for n in names if n and not _CJK_RE.search(n)]
            )
            canonical = resolve_existing(latin_cands) or override or canonical
            # All FreeOD names + the zh title become searchable aliases.
            aliases = list(dict.fromkeys([n for n in ([title] + names) if n and n != canonical]))
            before = self.stats["substances"]
            sid = self.upsert_substance(
                canonical,
                aliases=aliases,
                cas=rec.get("cas") or None,
                formula=rec.get("formula") or None,
                iupac=rec.get("iupac") or None,
                source_slug=slug,
            )
            if sid is None:
                continue
            if self.stats["substances"] > before:
                created.append(f"{canonical}  ←  {title}")

            page_slug = rec.get("page_slug")
            if page_slug:
                self.cur.execute(
                    "UPDATE substances SET freeodwiki_slug=COALESCE(freeodwiki_slug, ?) WHERE id=?",
                    (page_slug, sid),
                )

            for cat in rec.get("categories") or []:
                mapped = FREEOD_CATEGORY_MAP.get(cat)
                if mapped:
                    self.add_category(sid, slug, mapped)

            for route, d in (rec.get("doses") or {}).items():
                unit = d.get("unit") or "mg"
                self.add_dose(
                    sid,
                    slug,
                    route,
                    unit,
                    threshold=d.get("threshold"),
                    light=_freeod_range(d.get("light")),
                    common=_freeod_range(d.get("common")),
                    strong=_freeod_range(d.get("strong")),
                    heavy=d.get("heavy"),
                )
            for route, phases in (rec.get("durations") or {}).items():
                if phases:
                    self.add_duration_profile(sid, slug, route, phases)

            # zh originals (language-tagged); the resolver floats them above
            # English sources only when the app runs in Chinese.
            if rec.get("description"):
                self.add_description(sid, slug, rec["description"], language="zh-Hans")
            if rec.get("mechanism"):
                self.add_mechanism_summary(sid, slug, rec["mechanism"], language="zh-Hans")
            for eff in rec.get("subjective_effects") or []:
                self.add_subjective_effect(sid, slug, eff, language="zh-Hans")

            # English text for the Overview. Authentic PsychonautWiki lead prose is
            # attributed to `psychonautwiki` (not machine-translated); the remainder
            # — substances PW doesn't cover — is machine-translated from FreeOD's zh
            # and attributed to `freeodwiki` with machine_translated=1 so the UI can
            # mark it. Effect names are mapped to canonical PW Subjective Effect Index
            # names, so they ride as plain en rows (not flagged translated).
            if rec.get("description_en"):
                self.add_description(
                    sid,
                    rec.get("description_en_source", slug),
                    rec["description_en"],
                    language="en",
                    machine_translated=bool(rec.get("description_en_mt", True)),
                )
            if rec.get("mechanism_en"):
                self.add_mechanism_summary(
                    sid,
                    slug,
                    rec["mechanism_en"],
                    language="en",
                    machine_translated=bool(rec.get("mechanism_en_mt", True)),
                )
            for eff in rec.get("subjective_effects_en") or []:
                self.add_subjective_effect(sid, slug, eff, language="en", machine_translated=False)

        self.stats["freeodwiki_substances"] = len(data)
        self.stats["freeodwiki_created"] = len(created)
        if created:
            report = Path("/tmp/freeodwiki-match-report.txt")
            report.write_text(
                f"FreeOD: {len(data)} records, {len(data) - len(created)} matched "
                f"existing, {len(created)} created new (no English match):\n\n"
                + "\n".join(created)
                + "\n",
                encoding="utf-8",
            )
            print(
                f"[freeodwiki] {len(data)} records: "
                f"{len(data) - len(created)} matched, {len(created)} new — "
                f"full list at {report}"
            )

    def ingest_pyrls(self, path: Path) -> None:
        """Prescription-drug clinical reference. Adds NEW medical substances
        (trackable, dose-suppressed by policy) plus regulatory status,
        mechanism, indications, contraindications. No recreational dose."""
        if not path.exists():
            return
        slug = "pyrls"
        for rec in json.loads(path.read_text()):
            name = rec.get("name")
            if not name:
                continue
            reg = self._parse_regulatory(rec.get("x_regulatory_status"))
            sid = self.upsert_substance(
                name, aliases=rec.get("aliases") or [], regulatory_status=reg, source_slug=slug
            )
            if sid is None:
                continue
            cat = rec.get("category")
            if cat and cat != "Other":
                self.add_category(sid, slug, cat)
            for t in rec.get("tags") or []:
                self.add_tag(sid, slug, t)
            moa = rec.get("mechanismOfAction") or {}
            if moa.get("summary"):
                self.add_mechanism_summary(sid, slug, moa["summary"], moa.get("description"))
            for ind in self._as_text_list(rec.get("x_indications")):
                self.add_indication(sid, slug, ind)
            for c in self._as_text_list(rec.get("x_contraindications")):
                self.add_contraindication(sid, slug, c)
            for b in self._as_text_list(rec.get("x_boxed_warning")):
                self.add_contraindication(sid, slug, b, boxed=True)

    # Protein-target / non-drug junk rows in medtap (e.g. "Mu-type opioid
    # receptor", "5-hydroxytryptamine receptor 2A", "30S ribosomal protein S12",
    # "Sodium channel protein type 5 subunit alpha", "Penicillin-binding
    # protein 2"). The keyword can sit anywhere in the name, not just the end,
    # so match on word boundaries rather than endswith.
    _MEDTAP_JUNK_RE = re.compile(
        r"\b(receptor|transporter|channel|subunit|ribosomal|topoisomerase|atpase|"
        r"binding protein|reductase|synthase|kinase|polymerase|integrase|protease|"
        r"transferase|methyltransferase|dehydrogenase|hydroxylase|carboxylase|"
        r"transaminase|aminotransferase|lyase|ligase|isomerase)\b",
        re.IGNORECASE,
    )

    def ingest_medtap(self, path: Path) -> None:
        """FDA structured product labels. Like pyrls but lower priority and with
        a junk/combo filter. Category intentionally NOT ingested (322/387 'Other'
        with mislabels). Supplies regulatory status, mechanism, indications."""
        if not path.exists():
            return
        slug = "medtap"
        for rec in json.loads(path.read_text()):
            name = (rec.get("name") or "").strip()
            if not name or rec.get("x_is_combination"):
                continue
            if self._MEDTAP_JUNK_RE.search(name):
                continue
            reg = self._parse_regulatory(rec.get("x_regulatory_status"))
            sid = self.upsert_substance(
                name, aliases=rec.get("aliases") or [], regulatory_status=reg, source_slug=slug
            )
            if sid is None:
                continue
            moa = rec.get("mechanismOfAction") or {}
            if moa.get("summary"):
                self.add_mechanism_summary(sid, slug, moa["summary"], moa.get("description"))
            for ind in self._as_text_list(rec.get("x_indications")):
                self.add_indication(sid, slug, ind)
            for c in self._as_text_list(rec.get("x_contraindications")):
                self.add_contraindication(sid, slug, c)

    # "Alprazolam - 0.5mg ~=10mg Diazepam." → (0.5, 10.0)
    _DIAZ_RE = re.compile(r"(\d+(?:\.\d+)?)\s*mg\b.*?(\d+(?:\.\d+)?)\s*mg", re.IGNORECASE)

    def ingest_benzos_cited(self, path: Path) -> None:
        """Enrichment-only (0 novel). Attaches cross-benzo diazepam-equivalency,
        plus the curated prose fields (discontinuation warning, summary, oral
        bioavailability, tolerance note), to existing benzodiazepine records —
        data Piru has nowhere else."""
        if not path.exists():
            return
        slug = "benzos-cited"
        # name/alias → sid index. benzos-cited is 0-novel: every record already
        # exists in Piru (often as an alias, not a canonical name), so we match
        # against both and NEVER mint a new substance — minting brand-named rows
        # like "Ativan" was the bug this guards against.
        name_to_sid: dict[str, int] = dict(self.substance_ids)
        for row in self.cur.execute("SELECT substance_id, alias_normalized FROM aliases"):
            name_to_sid.setdefault(row[1], row[0])
        for rec in json.loads(path.read_text()):
            name = rec.get("name")
            if not name:
                continue
            candidates = [normalise(name)] + [normalise(a) for a in (rec.get("aliases") or [])]
            sid = next((name_to_sid[c] for c in candidates if c and c in name_to_sid), None)
            if sid is None:
                continue
            prose = rec.get("x_dose_to_diazepam")
            if prose:
                dose_mg = equiv_mg = None
                m = self._DIAZ_RE.search(prose)
                if m:
                    dose_mg = float(m.group(1))
                    equiv_mg = float(m.group(2))
                self.add_diazepam_equivalent(
                    sid,
                    slug,
                    dose_mg=dose_mg,
                    equivalent_diazepam_mg=equiv_mg,
                    display_text=prose.strip(),
                )
            # x_summary → a plain description; x_avoid → a contraindication
            # (discontinuation/combination warning, not a boxed warning);
            # x_tolerance → the tolerance note; x_bioavailability → pk_routes
            # rows (one per route segment, with a numeric % where parseable).
            self.add_description(sid, slug, rec.get("x_summary") or "")
            if rec.get("x_avoid"):
                self.add_contraindication(sid, slug, rec["x_avoid"])
            if rec.get("x_tolerance"):
                self.add_tolerance(sid, slug, {"notes": rec["x_tolerance"]})
            for route, pct, note in _parse_bioavailability(rec.get("x_bioavailability")):
                self.add_pk_route(
                    sid, slug, {"route": route, "bioavailability_pct": pct, "notes": note}
                )

    def ingest_nps(self, path: Path) -> None:
        """IDENTIFIER + PHYSICOCHEMICAL backfill. Matches nps records to EXISTING
        Piru substances by normalised name/alias and donates chemical identifiers
        (CAS/InChIKey/SMILES/formula/MW) and forensic physicochemical properties
        (logP/logD/pKa/TPSA/HBA/HBD, rodent LD50, melting/boiling point) via
        COALESCE — never overwrites an existing value, never mints a new
        substance (avoids catalog pollution from ~5000 forensic one-off names).

        These physicochemical values are predicted/forensic (logP is typically a
        computed estimate; LD50 is rodent, order-of-magnitude), not clinical —
        their provenance is the NPS-DataHub source attached to the substance. For
        InChIKey-verified CIDs, ``apply_pubchem_computed`` later supersedes
        logP/TPSA/HBA/HBD with PubChem's consistently-computed values."""
        if not path.exists():
            return
        # name/alias → sid index over what's already in the DB.
        name_to_sid: dict[str, int] = dict(self.substance_ids)
        for row in self.cur.execute("SELECT substance_id, alias_normalized FROM aliases"):
            name_to_sid.setdefault(row[1], row[0])
        matched = 0
        chem = 0
        for rec in json.loads(path.read_text()):
            candidates = [normalise(rec.get("name") or "")]
            candidates += [normalise(a) for a in (rec.get("aliases") or [])]
            sid = next((name_to_sid[c] for c in candidates if c and c in name_to_sid), None)
            if sid is None:
                continue
            self.cur.execute(
                "UPDATE substances SET inchikey = COALESCE(inchikey, ?), cas = COALESCE(cas, ?), "
                "smiles = COALESCE(smiles, ?), iupac_name = COALESCE(iupac_name, ?), "
                "formula = COALESCE(formula, ?), molecular_weight = COALESCE(molecular_weight, ?), "
                "logp = COALESCE(logp, ?), logd = COALESCE(logd, ?), pka = COALESCE(pka, ?), "
                "tpsa = COALESCE(tpsa, ?), hba = COALESCE(hba, ?), hbd = COALESCE(hbd, ?), "
                "ld50_oral_mg_per_kg = COALESCE(ld50_oral_mg_per_kg, ?), "
                "ld50_dermal_mg_per_kg = COALESCE(ld50_dermal_mg_per_kg, ?), "
                "melting_point_c = COALESCE(melting_point_c, ?), "
                "boiling_point_c = COALESCE(boiling_point_c, ?) WHERE id = ?",
                (
                    rec.get("x_inchikey") or None,
                    rec.get("x_cas") or None,
                    rec.get("x_smiles") or None,
                    rec.get("x_iupac") or None,
                    rec.get("x_chemical_formula") or None,
                    to_float(rec.get("x_mw")),
                    to_float(rec.get("x_logp")),
                    to_float(rec.get("x_logd")),
                    to_float(rec.get("x_pka")),
                    to_float(rec.get("x_tpsa")),
                    to_int(rec.get("x_hba")),
                    to_int(rec.get("x_hbd")),
                    to_float(rec.get("x_ld50_oral")),
                    to_float(rec.get("x_ld50_dermal")),
                    to_float(rec.get("x_melting_point_c")),
                    to_float(rec.get("x_boiling_point_c")),
                    sid,
                ),
            )
            matched += 1
            if any(
                rec.get(k) is not None
                for k in (
                    "x_logp",
                    "x_ld50_oral",
                    "x_ld50_dermal",
                    "x_melting_point_c",
                    "x_boiling_point_c",
                )
            ):
                chem += 1
        self.stats["nps_identifier_matches"] = matched
        self.stats["nps_physicochem_matches"] = chem

    def _substance_tables(self) -> list[str]:
        """Every table (besides ``substances``) that carries a substance_id.

        Materialised in full BEFORE any PRAGMA is issued on the cursor — reusing
        the cursor mid-iteration would truncate the outer query.
        """
        tnames = [
            r[0]
            for r in self.cur.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            ).fetchall()
        ]
        out = []
        for tname in tnames:
            if tname == "substances":
                continue
            cols = [c[1] for c in self.cur.execute(f"PRAGMA table_info({tname})").fetchall()]
            if "substance_id" in cols:
                out.append(tname)
        return out

    def _merge_into(self, winner: int, loser: int, *, fold_aliases: bool = True) -> None:
        """Fold the ``loser`` substance into ``winner`` and delete it.

        COALESCEs the loser's chemical identifiers into the winner (winner wins),
        reassigns every child-table row, and removes the loser. When
        ``fold_aliases`` is true the loser's canonical name and aliases become
        winner aliases (the default — preserves searchability). Pass
        ``fold_aliases=False`` when the loser's name is wrong/misleading and must
        NOT attach to the winner (e.g. a mislabelled entry whose data is correct
        but whose name belongs to a different molecule).
        """
        if winner == loser:
            return
        cur = self.cur
        lname_row = cur.execute(
            "SELECT canonical_name FROM substances WHERE id=?", (loser,)
        ).fetchone()
        laliases = [
            r[0] for r in cur.execute("SELECT alias FROM aliases WHERE substance_id=?", (loser,))
        ]
        cur.execute("DELETE FROM aliases WHERE substance_id=?", (loser,))
        cur.execute(
            "UPDATE substances SET "
            "inchikey=COALESCE(inchikey,(SELECT inchikey FROM substances WHERE id=:l)), "
            "pubchem_cid=COALESCE(pubchem_cid,(SELECT pubchem_cid FROM substances WHERE id=:l)), "
            "cas=COALESCE(cas,(SELECT cas FROM substances WHERE id=:l)), "
            "smiles=COALESCE(smiles,(SELECT smiles FROM substances WHERE id=:l)), "
            "formula=COALESCE(formula,(SELECT formula FROM substances WHERE id=:l)), "
            "molecular_weight=COALESCE(molecular_weight,(SELECT molecular_weight FROM substances WHERE id=:l)), "
            "regulatory_status=COALESCE(regulatory_status,(SELECT regulatory_status FROM substances WHERE id=:l)), "
            "drug_community_slug=COALESCE(drug_community_slug,(SELECT drug_community_slug FROM substances WHERE id=:l)) "
            "WHERE id=:w",
            {"l": loser, "w": winner},
        )
        for t in self._substance_tables():
            if t == "aliases":
                continue
            cur.execute(
                f"UPDATE OR IGNORE {t} SET substance_id=? WHERE substance_id=?",
                (winner, loser),
            )
            cur.execute(f"DELETE FROM {t} WHERE substance_id=?", (loser,))
        cur.execute("DELETE FROM substances WHERE id=?", (loser,))
        if lname_row:
            self.substance_ids.pop(normalise(lname_row[0]), None)
        if fold_aliases:
            if lname_row:
                self._add_alias(winner, lname_row[0], "piru-curated")
            for a in laliases:
                self._add_alias(winner, a, None)

    def apply_forced_merges(self) -> dict[str, int]:
        """Consolidate the verified same-compound clusters in _FORCE_MERGE that
        structural auto-dedup can't reach (different/absent InChIKeys). Resolves
        each pair by exact current canonical name and folds loser into winner.
        Runs after dedup."""
        merged, missing = 0, []
        for loser_name, winner_name, fold in _FORCE_MERGE:
            lr = self.cur.execute(
                "SELECT id FROM substances WHERE canonical_name=?", (loser_name,)
            ).fetchone()
            wr = self.cur.execute(
                "SELECT id FROM substances WHERE canonical_name=?", (winner_name,)
            ).fetchone()
            if not lr or not wr:
                missing.append(loser_name if not lr else winner_name)
                continue
            if lr[0] == wr[0]:
                continue
            self._merge_into(wr[0], lr[0], fold_aliases=fold)
            merged += 1
        if missing:
            print(f"  apply_forced_merges: targets not found: {missing}", file=sys.stderr)
        return {"merged": merged, "missing": len(missing)}

    def merge_self_flagged_duplicates(
        self, protect_norms: set[str] | None = None
    ) -> dict[str, int]:
        """Fold rows a prior enrichment pass already tagged `duplicate-of-<X>`
        into their target X. The structural dedup leaves these split because the
        stub carries no/clashing InChIKey, but the curators identified them by
        hand. Target is matched on normalise() so the tag suffix may be a slug
        ('chloral-hydrate') or a name ('2-MeO-Ketamine'). Honours _DO_NOT_MERGE.

        A loser that has its own curated file (``protect_norms``) is NEVER merged
        away — a hand-authored entry is deliberate; if it's truly a duplicate the
        curator deletes its file. Runs after apply_forced_merges (survivors)."""
        protect = protect_norms or set()
        by_norm: dict[str, int] = {}
        for sid, cname in self.cur.execute("SELECT id, canonical_name FROM substances").fetchall():
            by_norm.setdefault(normalise(cname), sid)
        prefix = "duplicate-of-"
        pairs: list[tuple[int, int, str]] = []
        for sid, tag in self.cur.execute(
            "SELECT substance_id, tag FROM tags WHERE tag LIKE 'duplicate-of-%'"
        ).fetchall():
            target_norm = normalise(tag[len(prefix) :])
            winner = by_norm.get(target_norm)
            if winner is None or winner == sid:
                continue
            lname = self.cur.execute(
                "SELECT canonical_name FROM substances WHERE id=?", (sid,)
            ).fetchone()
            if not lname:
                continue
            if normalise(lname[0]) in protect:
                continue
            if frozenset({normalise(lname[0]), target_norm}) in _DO_NOT_MERGE:
                continue
            pairs.append((winner, sid, tag))
        merged = 0
        for winner, loser, _tag in pairs:
            # Both may have been consumed by an earlier merge in this loop.
            if not self.cur.execute("SELECT 1 FROM substances WHERE id=?", (loser,)).fetchone():
                continue
            if not self.cur.execute("SELECT 1 FROM substances WHERE id=?", (winner,)).fetchone():
                continue
            self._merge_into(winner, loser, fold_aliases=True)
            merged += 1
        return {"merged": merged}

    # A route spelled into the canonical name as a suffix (`Fluticasone-nasal`,
    # `Hydrocortisone-topical`, `Beclomethasone-inhaled`) — the route belongs in
    # the `route` dimension, not the name. Maps each suffix to the enum case the
    # app decodes it to (`RouteOfAdministration.from(string:)`), so any
    # dose/duration rows the variant carries render identically once re-keyed.
    # (Today these medtap catalog stubs carry no dose rows — the rewrite is a
    # defensive no-op that keeps the pass correct if dose data ever lands on a
    # nasal/topical entry.)
    _ROUTE_SUFFIX_MAP = {
        "inhaled": "inhalation",
        "nasal": "insufflation",
        "topical": "transdermal",
        "ophthalmic": "other",
    }
    _ROUTE_SUFFIX_RE = re.compile(
        r"^(?P<base>.+)-(?P<suffix>topical|inhaled|nasal|ophthalmic)$", re.IGNORECASE
    )

    def collapse_route_suffixes(self) -> dict[str, int]:
        """Fold `<base>-<route>` canonicals into a single parent `<base>`, moving
        the route from the name into the `route` column.

        Each variant's dose/duration/duration-of-action/protocol rows are
        re-keyed to the mapped route *before* `_merge_into` folds the variant
        into its parent (created if absent). The variant's name and brand
        aliases survive as parent aliases, so `Flonase`/`Fluticasone-nasal`
        still resolve. Runs after dedup/forced-merges (operates on survivors)
        and before classify (the merged parent is reclassified from final
        signals). See Specs/salt-forms-and-route-collapse.md (Part B)."""
        collapsed, parents_created, rerouted = 0, 0, 0
        rows = self.cur.execute("SELECT id, canonical_name FROM substances").fetchall()
        for vid, vname in rows:
            m = self._ROUTE_SUFFIX_RE.match(vname)
            if not m:
                continue
            base = m.group("base").strip()
            new_route = self._ROUTE_SUFFIX_MAP[m.group("suffix").lower()]
            parent_norm = normalise(base)
            existing_parent = self.substance_ids.get(parent_norm)
            parent_id = self.upsert_substance(base, source_slug="piru-curated")
            if parent_id is None or parent_id == vid:
                continue
            if existing_parent is None:
                parents_created += 1
            for table in ("dose_ranges", "durations", "durations_of_action", "protocol_dosing"):
                cur = self.cur.execute(
                    f"UPDATE OR IGNORE {table} SET route=? WHERE substance_id=?",
                    (new_route, vid),
                )
                rerouted += cur.rowcount
            self._merge_into(parent_id, vid, fold_aliases=True)
            collapsed += 1
        return {
            "collapsed": collapsed,
            "parents_created": parents_created,
            "rerouted_rows": rerouted,
        }

    # Curated salt families: a shared parent canonical → [(variant, salt label)].
    # The salt genuinely changes dosing (elemental fraction, indication), so each
    # variant keeps its own dose ladder under the parent, tagged by `salt_form`,
    # surfaced by the app's salt picker. Only families with ≥2 real ladders are
    # listed — single-salt supplements (Iron Bisglycinate, Zinc Picolinate) gain
    # nothing from a one-option picker and stay standalone. Antacid *combos*
    # (Magnesium/Magaldrate, Magnesium/Sodium) are mixtures, not salt forms, and
    # are deliberately excluded. See Specs/salt-forms-and-route-collapse.md (A.2).
    _SALT_FAMILIES: dict[str, list[tuple[str, str]]] = {
        "Magnesium": [
            ("Magnesium Citrate", "Citrate"),
            ("Magnesium Glycinate", "Glycinate"),
            ("Magnesium Threonate", "L-Threonate"),
            ("Magnesium hydroxide", "Hydroxide"),
        ],
        "Lithium": [
            ("Lithium Carbonate", "Carbonate"),
            ("Lithium orotate", "Orotate"),
        ],
    }

    # Per-salt curated metadata, keyed by (parent canonical, salt label). Drives
    # two forward-looking dose_ranges columns the loader consumes later (WS-2b):
    #
    #   rank      0 = the default the app should pre-select; 1, 2 … = the rest.
    #             Kiri-approved: Magnesium Glycinate (best-absorbed/best-tolerated
    #             common form) and Lithium Carbonate (the pharma standard) lead.
    #   elemental mass fraction of the elemental metal in the salt — so the app
    #             can show "≈ N mg elemental Mg/Li" beside the salt dose.
    #             Mg citrate 0.16, glycinate 0.141, L-threonate 0.083;
    #             Li carbonate 0.188, orotate 0.043.
    #
    # The salt label here MUST match the (already-canonical) label set by
    # fold_salt_families(); apply_salt_metadata() asserts coverage so a typo or a
    # new family without metadata surfaces at build time, not silently.
    _SALT_METADATA: dict[str, dict[str, tuple[int, float]]] = {
        "Magnesium": {
            "Glycinate": (0, 0.141),
            "Citrate": (1, 0.16),
            "L-Threonate": (2, 0.083),
        },
        "Lithium": {
            "Carbonate": (0, 0.188),
            "Orotate": (1, 0.043),
        },
    }

    def fold_salt_families(self) -> dict[str, int]:
        """Fold curated salt variants into a shared parent, tagging each variant's
        dose/duration rows with its `salt_form` label.

        For each family: create the parent if absent, then for every variant
        rewrite its dose/duration/duration-of-action/protocol rows' `salt_form`
        to the label *before* `_merge_into` reassigns them to the parent. The
        variant canonical name survives as a parent alias (protected from the
        chemnoise purge) so "Magnesium Citrate" still searches. The parent
        inherits the max popularity of its variants. Runs after dedup/forced-
        merges/route-collapse and before classify (which sets the parent's final
        display_class). See Specs/salt-forms-and-route-collapse.md (A.2)."""
        folded, families, parents_created = 0, 0, 0
        salt_tables = ("dose_ranges", "durations", "durations_of_action", "protocol_dosing")

        def tag_salt(sid: int, label: str) -> None:
            label = canonical_salt_form(label)
            for table in salt_tables:
                self.cur.execute(
                    f"UPDATE OR IGNORE {table} SET salt_form=? WHERE substance_id=?",
                    (label, sid),
                )

        for parent_name, variants in self._SALT_FAMILIES.items():
            present = {}  # variant id -> (canonical_name, salt label)
            for vname, label in variants:
                r = self.cur.execute(
                    "SELECT id FROM substances WHERE canonical_name=?", (vname,)
                ).fetchone()
                if r:
                    present[r[0]] = (vname, label)
            if not present:
                continue
            families += 1
            parent_norm = normalise(parent_name)

            # normalise() strips some salt suffixes (e.g. "Magnesium Citrate" →
            # "magnesium"), so the parent's normalised key may already be occupied
            # by a *variant* row. Promote that row into the parent rather than
            # creating a colliding duplicate.
            occupant = self.substance_ids.get(parent_norm)
            if occupant is not None:
                cur_name = self.cur.execute(
                    "SELECT canonical_name FROM substances WHERE id=?", (occupant,)
                ).fetchone()[0]
                if cur_name != parent_name and occupant not in present:
                    print(
                        f"  fold_salt_families: {parent_name!r} key occupied by "
                        f"unrelated {cur_name!r}; skipping family",
                        file=sys.stderr,
                    )
                    continue
                parent_id = occupant
                if cur_name != parent_name:
                    # The occupant is a variant — rename it to the bare parent and
                    # tag its own ladder with its salt label, keeping its old name
                    # searchable (protected from the chemnoise purge).
                    vname, label = present[parent_id]
                    self.cur.execute(
                        "UPDATE substances SET canonical_name=? WHERE id=?",
                        (parent_name, parent_id),
                    )
                    tag_salt(parent_id, label)
                    self.salt_alias_protect.add(normalise(vname))
                    self._add_alias(parent_id, vname, "piru-curated")
            else:
                parent_id = self.upsert_substance(parent_name, source_slug="piru-curated")
                if parent_id is None:
                    continue
                parents_created += 1

            max_pop = self.cur.execute(
                "SELECT COALESCE(MAX(popularity), 0) FROM substances WHERE id=?", (parent_id,)
            ).fetchone()[0]
            for vid, (vname, label) in present.items():
                if vid == parent_id:
                    continue
                vpop = self.cur.execute(
                    "SELECT popularity FROM substances WHERE id=?", (vid,)
                ).fetchone()[0]
                max_pop = max(max_pop, vpop or 0)
                tag_salt(vid, label)
                self.salt_alias_protect.add(normalise(vname))
                self._merge_into(parent_id, vid, fold_aliases=True)
                folded += 1
            self.cur.execute("UPDATE substances SET popularity=? WHERE id=?", (max_pop, parent_id))
        return {"families": families, "folded": folded, "parents_created": parents_created}

    def apply_salt_metadata(self) -> dict[str, int]:
        """Stamp curated `salt_rank` + `elemental_fraction` onto the salt-tagged
        dose rows produced by fold_salt_families().

        Data-driven default-salt intent: rank 0 is the form the app should
        pre-select (Magnesium Glycinate, Lithium Carbonate). The loader still
        defaults alphabetically until WS-2b reads this column, so this is
        forward-looking metadata — it changes no current app behaviour or dose
        value. Asserts every salt-tagged dose row got metadata, so a new family
        without an entry fails the build loudly instead of silently shipping
        NULLs. Runs immediately after fold_salt_families()."""
        ranked, with_elemental = 0, 0
        for parent_name, by_salt in self._SALT_METADATA.items():
            prow = self.cur.execute(
                "SELECT id FROM substances WHERE canonical_name=?", (parent_name,)
            ).fetchone()
            if prow is None:
                continue
            pid = prow[0]
            for salt_form, (rank, elemental) in by_salt.items():
                cur = self.cur.execute(
                    "UPDATE dose_ranges SET salt_rank=?, elemental_fraction=? "
                    "WHERE substance_id=? AND salt_form=?",
                    (rank, elemental, pid, salt_form),
                )
                if cur.rowcount:
                    ranked += cur.rowcount
                    with_elemental += cur.rowcount

        # Coverage gate: every salt-tagged dose row must have received a rank.
        uncovered = self.cur.execute(
            "SELECT s.canonical_name, d.salt_form FROM dose_ranges d "
            "JOIN substances s ON s.id=d.substance_id "
            "WHERE d.salt_form IS NOT NULL AND d.salt_rank IS NULL"
        ).fetchall()
        if uncovered:
            raise SystemExit(
                f"apply_salt_metadata: {len(uncovered)} salt-tagged dose rows have "
                f"no curated rank/elemental — add them to _SALT_METADATA: {uncovered}"
            )
        return {"ranked_rows": ranked, "elemental_rows": with_elemental}

    def audit_salt_supplement_durations(self) -> dict[str, int]:
        """Remove the salt-tagged ACUTE duration rows on the Mg/Li supplement
        parents.

        Audit decision (WS-5 #5, Kiri-flagged): Magnesium (a mineral ion) and
        Lithium (a serum-level-titrated maintenance drug) have no perceptible
        acute onset/peak/offset curve — the salt-tagged durations folded in from
        the curated variant files reflect serum Tmax, not a felt effect, and
        drawing a PK timeline for them is the imperceptible-curve problem. Dropping
        them makes those routes fall back to marker rendering. Dose ladders and the
        salt picker are untouched (only `durations` rows go); long-acting depot
        windows (durations_of_action) are unaffected. Runs after apply_salt_metadata."""
        removed = 0
        for parent_name in ("Magnesium", "Lithium"):
            prow = self.cur.execute(
                "SELECT id FROM substances WHERE canonical_name=?", (parent_name,)
            ).fetchone()
            if prow is None:
                continue
            cur = self.cur.execute(
                "DELETE FROM durations WHERE substance_id=? AND salt_form IS NOT NULL",
                (prow[0],),
            )
            removed += cur.rowcount
        return {"removed_duration_rows": removed}

    def flag_dose_less_stubs(self) -> int:
        """Set `substances.is_stub = 1` for every substance with ZERO dose_ranges,
        ZERO durations, and ZERO protocol_dosing rows.

        These are bare catalog entries — overwhelmingly medtap regulatory rows
        that carry a name/indication but nothing dose-trackable. Flagging (rather
        than dropping) lets the app demote/badge them without losing the catalog.
        Distinct from drop_orphan_stubs(), which deletes truly content-less
        wikidata rows; a stub here may still carry indications/mechanism/effects.
        Runs after all dose/duration ingest + folding + the duration audit."""
        cur = self.cur.execute(
            "UPDATE substances SET is_stub = 1 WHERE id NOT IN ("
            "  SELECT substance_id FROM dose_ranges "
            "  UNION SELECT substance_id FROM durations "
            "  UNION SELECT substance_id FROM protocol_dosing)"
        )
        return cur.rowcount

    def dedup_substances(self) -> dict[str, int]:
        """Merge substance records that are the SAME compound under different
        names — typically a brand and its generic that came from different
        sources and never matched (e.g. Vyvanse→Lisdexamfetamine,
        Focalin→Dexmethylphenidate).

        Detection: an edge links substance A and B when A's normalized canonical
        name equals one of B's normalized aliases (B names A explicitly). Linked
        substances form a group via union-find.

        Safety: within a group we only merge a member that is a DATA-POOR STUB
        (no dose/duration/binding/effect of its own — i.e. a brand entry, not an
        independently-characterised compound). This prevents wrongly merging two
        real compounds that happen to share a slang alias (e.g. 'speed'). Stubs
        merge into the richest member; their aliases + clinical text + identifiers
        carry over. Non-stub collisions are logged for manual review, not merged.

        Runs after all ingest + promote_via_tags, before classify_compounds.
        """
        cur = self.cur
        canon_norm = {
            norm: sid for sid, norm in cur.execute("SELECT id, normalized_name FROM substances")
        }
        alias_owners: dict[str, set[int]] = defaultdict(set)
        for sid, anorm in cur.execute("SELECT substance_id, alias_normalized FROM aliases"):
            alias_owners[anorm].add(sid)

        parent: dict[int, int] = {}

        def find(x: int) -> int:
            parent.setdefault(x, x)
            root = x
            while parent[root] != root:
                root = parent[root]
            while parent[x] != root:
                parent[x], x = root, parent[x]
            return root

        def union(a: int, b: int) -> None:
            ra, rb = find(a), find(b)
            if ra != rb:
                parent[ra] = rb

        # Link a substance to another whose canonical name it lists as an alias.
        # Only via SPECIFIC names: if a name is an alias of >3 distinct compounds
        # it's ambiguous slang (e.g. "speed"), not a dup link — skip it so it
        # can't fuse distinct compounds into one mega-group.
        for anorm, owners in alias_owners.items():
            gen = canon_norm.get(anorm)  # substance whose canonical IS this name
            if gen is None:
                continue
            others = owners - {gen}
            if not others or len(others) > 3:
                continue
            for b in others:
                union(gen, b)

        groups: dict[int, set[int]] = defaultdict(set)
        for sid in canon_norm.values():
            if sid in parent:
                groups[find(sid)].add(sid)
        groups = {k: v for k, v in groups.items() if len(v) > 1}
        if not groups:
            return {"groups": 0, "merged": 0}

        # Richness picks the surviving record (the characterised compound); the
        # merged-in members contribute their unique aliases / clinical text /
        # identifiers, and any extra dose rows resolve by source priority later.
        def total_richness(sid: int) -> int:
            n = 0
            for t in (
                "dose_ranges",
                "durations",
                "bindings",
                "effects",
                "subjective_effects",
                "mechanisms_summary",
                "metabolism",
                "pk_routes",
                "indications",
            ):
                n += cur.execute(
                    f"SELECT COUNT(*) FROM {t} WHERE substance_id=?", (sid,)
                ).fetchone()[0]
            return n

        inchikey = dict(cur.execute("SELECT id, inchikey FROM substances"))

        # Stereoisomers (dexmethylphenidate≠methylphenidate, escitalopram≠
        # citalopram, armodafinil≠modafinil, dextroamphetamine≠amphetamine) are
        # distinct compounds that must never merge even though one lists the
        # other as an alias: names equal after stripping a chirality prefix but
        # different before it. Uses the module-level strip_stereo.
        def stereoisomer_pair(a_name: str, b_name: str) -> bool:
            na, nb = normalise(a_name), normalise(b_name)
            sa, sb = strip_stereo(na), strip_stereo(nb)
            return na != nb and sa == sb and bool(sa)

        def mergeable(w: int, o: int) -> bool:
            # SAFE BY DEFAULT: merge only with POSITIVE proof of same molecule —
            # an identical InChIKey connectivity block (first 14 chars: same
            # skeleton, salt/abbreviation-independent) AND not a stereoisomer
            # pair (those share a block but are distinct drugs). Without a
            # structural match we do NOT merge: two different compounds often
            # cross-list each other as aliases (loratadine↔fexofenadine), and a
            # wrong merge is worse than a leftover duplicate. Known brands that
            # lack an InChIKey are handled explicitly in _NAME_REMAP instead.
            if stereoisomer_pair(names[w], names[o]):
                return False
            # Curated do-not-merge guard (#8): distinct compounds whose source
            # InChIKeys collide on the connectivity block must never fuse.
            if frozenset({normalise(names[w]), normalise(names[o])}) in _DO_NOT_MERGE:
                return False
            iw, io = inchikey.get(w), inchikey.get(o)
            return bool(iw) and bool(io) and iw[:14] == io[:14]

        merged, review = 0, []
        for members in groups.values():
            # A very large cluster usually means a bad linking alias fused
            # distinct compounds — don't auto-merge it, surface for review.
            if len(members) > 6:
                names = [
                    cur.execute(
                        "SELECT canonical_name FROM substances WHERE id=?", (m,)
                    ).fetchone()[0]
                    for m in members
                ]
                review.append("cluster:" + "/".join(names))
                continue
            ranked = sorted(members, key=lambda s: (total_richness(s), -s), reverse=True)
            winner = ranked[0]
            names = {
                m: cur.execute("SELECT canonical_name FROM substances WHERE id=?", (m,)).fetchone()[
                    0
                ]
                for m in members
            }
            for loser in ranked[1:]:
                # Merge only with positive structural proof (see mergeable);
                # everything else is surfaced for review, never auto-merged.
                if not mergeable(winner, loser):
                    review.append(f"{names[loser]} ~ {names[winner]}")
                    continue
                self._merge_into(winner, loser)
                merged += 1
        if review:
            print(
                f"  dedup: {len(review)} non-stub collisions NOT merged (manual review): {review[:15]}",
                file=sys.stderr,
            )
        return {"groups": len(groups), "merged": merged, "needs_review": len(review)}

    def _delete_substance(self, sid: int) -> None:
        """Hard-delete a substance and every child row referencing it."""
        for t in self._substance_tables():
            self.cur.execute(f"DELETE FROM {t} WHERE substance_id=?", (sid,))
        row = self.cur.execute(
            "SELECT canonical_name FROM substances WHERE id=?", (sid,)
        ).fetchone()
        self.cur.execute("DELETE FROM substances WHERE id=?", (sid,))
        if row:
            self.substance_ids.pop(normalise(row[0]), None)

    def purge_overbroad_research_chemical_tag(self) -> int:
        """Strip the `research-chemical` tag from substances that are NOT novel/
        obscure research chemicals, so the tag-driven "Research Chemicals" browse
        group (and the detail-card tag label) stays genuine. Sources over-apply
        it: every peptide is sold "for research use" and well-studied classics
        (Psilocin, 5-MeO-DMT) and approved meds (Phenibut) get swept in.

        Remove it when the substance is:
          - a peptide (has a peptide_profile or a Peptide category — it lives in
            the Peptides family, never "RC"), or
          - well-established: curated popularity >= the threshold (the genuine
            obscure RCs all sit at popularity 0; only established compounds clear
            it — psilocin, 5-MeO-DMT, phenibut, the GLP-1/healing peptides).
        Runs after dedup + curated popularity are final."""
        RC_ESTABLISHED_POPULARITY = 0.3
        rows = self.cur.execute(
            """
            SELECT DISTINCT s.id FROM substances s
              JOIN tags t ON t.substance_id = s.id AND t.tag = 'research-chemical'
             WHERE s.popularity >= ?
                OR EXISTS(SELECT 1 FROM peptide_profiles p WHERE p.substance_id = s.id)
                OR EXISTS(SELECT 1 FROM categories c
                           WHERE c.substance_id = s.id AND c.category = 'Peptide')
            """,
            (RC_ESTABLISHED_POPULARITY,),
        ).fetchall()
        n = 0
        for (sid,) in rows:
            cur = self.cur.execute(
                "DELETE FROM tags WHERE substance_id=? AND tag='research-chemical'", (sid,)
            )
            n += cur.rowcount
        return n

    def drop_junk_and_inert(self, protect_norms: set[str] | None = None) -> dict[str, int]:
        """Remove rows that are not consumable substances: explicit non-drug
        entries (``_REMOVE_NAMES``: enzymes, lab reagents, hoaxes) and inert/fake
        compounds (``_INERT_TAGS`` with NO dose data and NO curated file). A dose
        ladder or a curated override always protects a row. Runs after dedup so a
        junk row that was an unmerged duplicate has already folded."""
        protect = protect_norms or set()
        removed_named = removed_inert = 0
        for sid, cname in self.cur.execute("SELECT id, canonical_name FROM substances").fetchall():
            if normalise(cname) in _REMOVE_NAMES and normalise(cname) not in protect:
                self._delete_substance(sid)
                removed_named += 1
        tag_csv = ",".join("?" * len(_INERT_TAGS))
        inert_rows = self.cur.execute(
            f"""
            SELECT s.id, s.canonical_name, s.normalized_name FROM substances s
             WHERE EXISTS(SELECT 1 FROM tags t WHERE t.substance_id=s.id AND t.tag IN ({tag_csv}))
               AND NOT EXISTS(SELECT 1 FROM dose_ranges d WHERE d.substance_id=s.id)
            """,
            tuple(_INERT_TAGS),
        ).fetchall()
        for sid, _cname, norm in inert_rows:
            if norm in protect:
                continue
            self._delete_substance(sid)
            removed_inert += 1
        return {"named": removed_named, "inert": removed_inert}

    def drop_orphan_stubs(self, protect_norms: set[str] | None = None) -> dict[str, int]:
        """Delete content-less wikidata long-tail stubs.

        Wikidata contributes ~500 identifier-only rows for obscure chemistry —
        tryptophan/tryptamine biosynthesis intermediates, peptide-drug
        conjugates, plant alkaloids, even metabolites — that carry a name (and
        maybe a formula) but NOTHING a dose-tracking app can show: no dose,
        effect, mechanism, indication, binding, or duration from ANY source.
        They only pollute search and browse.

        A stub is KEPT when it carries recreational provenance — a category or
        tag asserted by a harm-reduction source (PsychonautWiki / TripSit /
        Erowid PIHKAL+TIHKAL) — OR when it has a hand-curated file
        (``protect_norms``, the normalised names from ingest_curated_substances).
        The latter preserves deliberate override-only records (a file that just
        sets a displayName or popularity for an otherwise content-less compound).
        That keeps recognisable name-only research chemicals (2C-H, DBT, NMT, the
        Shulgin compounds) and every curated entry, while dropping the wikidata
        biochemistry noise. Provenance, not the structural tag name ("tryptamine"
        also tags the junk), is the signal.

        Must run AFTER dedup (so a stub that was really an unmerged duplicate has
        already folded its aliases into the survivor) and AFTER external ingest
        (so pyrls/medtap indications etc. count as content).
        """
        rec_ids = [
            self.source_ids[s]
            for s in ("psychonautwiki", "tripsit", "erowid-pihkal", "erowid-tihkal")
            if s in self.source_ids
        ]
        rec_csv = ",".join(str(i) for i in rec_ids) or "-1"
        # "Content" = any substance-referencing table that isn't pure metadata.
        # Computed from the live schema so new fact tables are covered without
        # editing this list. A substance with metabolism / pk_routes / half-life
        # / contraindication / tolerance etc. is NOT a stub even with no dose
        # curve — that's real, showable information (Serotonin, Dopamine,
        # Chloramphenicol, the meth enantiomers all land here).
        metadata_tables = {"aliases", "categories", "tags", "substance_citations"}
        all_tnames = [
            r[0]
            for r in self.cur.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            ).fetchall()
        ]
        content_tables = []
        for tname in all_tnames:
            if tname in metadata_tables or tname == "substances":
                continue
            cols = [c[1] for c in self.cur.execute(f"PRAGMA table_info({tname})").fetchall()]
            if "substance_id" in cols:
                content_tables.append(tname)
        no_content = " AND ".join(
            f"NOT EXISTS(SELECT 1 FROM {t} x WHERE x.substance_id=s.id)" for t in content_tables
        )
        protect = protect_norms or set()
        drop_ids = [
            (r[0], r[1])
            for r in self.cur.execute(
                f"""
                SELECT s.id, s.canonical_name, s.normalized_name FROM substances s
                WHERE {no_content}
                  AND NOT EXISTS(
                      SELECT 1 FROM categories c
                      WHERE c.substance_id=s.id AND c.source_id IN ({rec_csv}))
                  AND NOT EXISTS(
                      SELECT 1 FROM tags t
                      WHERE t.substance_id=s.id AND t.source_id IN ({rec_csv}))
                """
            ).fetchall()
            if r[2] not in protect
        ]
        if not drop_ids:
            return {"dropped": 0}

        # Every substance-referencing table: content tables plus the metadata
        # ones we excluded from the stub test but must still clean up.
        sub_tables = content_tables + [t for t in metadata_tables if t in all_tnames]
        for sid, cname in drop_ids:
            for t in sub_tables:
                self.cur.execute(f"DELETE FROM {t} WHERE substance_id=?", (sid,))
            self.cur.execute("DELETE FROM substances WHERE id=?", (sid,))
            self.substance_ids.pop(normalise(cname), None)
        sample = sorted(c for _, c in drop_ids)[:12]
        print(f"  drop_orphan_stubs sample: {sample}", file=sys.stderr)
        return {"dropped": len(drop_ids)}

    def classify_compounds(self) -> dict[str, int]:
        """Bake each substance's display_class + duration_implausible from the
        resolved signals. Runs AFTER all ingest + promote_via_tags so category
        and regulatory_status are final. See REC_SOURCE_SLUGS / *_CATEGORIES /
        REC_TAGS / OTC_ALLOWLIST for the vocab and docs/ for the policy."""
        cur = self.cur
        rec_slugs = tuple(REC_SOURCE_SLUGS)
        placeholders = ",".join("?" * len(rec_slugs))
        rec_dose = {
            r[0]
            for r in cur.execute(
                f"""
            SELECT DISTINCT d.substance_id FROM dose_ranges d
              JOIN sources s ON s.id = d.source_id
             WHERE s.slug IN ({placeholders})
               AND (d.threshold IS NOT NULL OR d.light_lower IS NOT NULL
                    OR d.common_lower IS NOT NULL OR d.strong_lower IS NOT NULL
                    OR d.heavy IS NOT NULL)
        """,
                rec_slugs,
            )
        }
        rec_dur = {
            r[0]
            for r in cur.execute(
                f"""
            SELECT DISTINCT du.substance_id FROM durations du
              JOIN sources s ON s.id = du.source_id
             WHERE s.slug IN ({placeholders})
               AND (du.min_minutes IS NOT NULL OR du.max_minutes IS NOT NULL)
        """,
                rec_slugs,
            )
        }
        # Weak signal (drug.community) — recreational only for non-medical compounds.
        weak_slugs = tuple(WEAK_REC_SOURCE_SLUGS)
        weak_ph = ",".join("?" * len(weak_slugs))
        weak_rec = {
            r[0]
            for r in cur.execute(
                f"""
            SELECT DISTINCT substance_id FROM (
                SELECT d.substance_id FROM dose_ranges d JOIN sources s ON s.id = d.source_id
                 WHERE s.slug IN ({weak_ph})
                   AND (d.threshold IS NOT NULL OR d.light_lower IS NOT NULL
                        OR d.common_lower IS NOT NULL OR d.strong_lower IS NOT NULL OR d.heavy IS NOT NULL)
                UNION
                SELECT du.substance_id FROM durations du JOIN sources s ON s.id = du.source_id
                 WHERE s.slug IN ({weak_ph})
                   AND (du.min_minutes IS NOT NULL OR du.max_minutes IS NOT NULL)
            )
        """,
                weak_slugs + weak_slugs,
            )
        }
        cat_by_sid: dict[int, str] = {}
        for r in cur.execute("""
            SELECT substance_id, category FROM (
              SELECT c.substance_id, c.category,
                     ROW_NUMBER() OVER (PARTITION BY c.substance_id
                                        ORDER BY s.default_priority ASC) AS rn
                FROM categories c JOIN sources s ON s.id = c.source_id
            ) WHERE rn = 1
        """):
            cat_by_sid[r[0]] = r[1]
        tags_by_sid: dict[int, set[str]] = defaultdict(set)
        for r in cur.execute("SELECT substance_id, tag FROM tags"):
            tags_by_sid[r[0]].add(r[1])
        total_by_sid: dict[int, float] = {}
        for r in cur.execute(
            "SELECT substance_id, MAX(max_minutes) FROM durations WHERE phase='total' GROUP BY substance_id"
        ):
            total_by_sid[r[0]] = r[1]

        counts: dict[str, int] = defaultdict(int)
        rows = cur.execute(
            "SELECT id, canonical_name, regulatory_status FROM substances"
        ).fetchall()
        for sid, canonical, reg_raw in rows:
            cat = cat_by_sid.get(sid)
            tags = tags_by_sid.get(sid, set())
            reg = (reg_raw or "").lower()
            name = (canonical or "").lower()
            rec_signal = sid in rec_dose or sid in rec_dur  # strong: harm-reduction wikis
            weak_signal = sid in weak_rec  # drug.community (non-medical only)
            is_medical_cat = cat in MEDICAL_CATEGORIES
            is_rec_cat = cat in RECREATIONAL_CATEGORIES
            rec_tag = bool(tags & REC_TAGS)
            is_antibiotic = (cat == "Antimicrobial") or bool(tags & ANTIBIOTIC_TAGS)
            is_supplement = cat == "Supplement"
            is_otc = reg in ("otc", "rx_otc_dependent") or name in OTC_ALLOWLIST

            if strip_stereo(name) in NON_RECREATIONAL_OTC or name in NON_RECREATIONAL_OTC:
                # Pure OTC analgesic/antipyretic: a wiki listing it for overdose
                # safety isn't a recreational signal. Force OTC and drop the
                # aggregator's "common" tag so it leaves the recreational browse.
                cls = "otc"
                cur.execute("DELETE FROM tags WHERE substance_id = ? AND tag = 'common'", (sid,))
            elif rec_signal:
                # Genuine harm-reduction-wiki dose/duration → show it. A medical
                # drug here is dual_use (the literal "if PW has the data" rule).
                cls = "dual_use" if is_medical_cat else "recreational"
            elif is_antibiotic:
                # Antimicrobials are never recreational without a wiki signal —
                # checked before the weak/medical branches so a drug.community
                # clinical dose can't leak an antibiotic into recreational browse.
                cls = "non_recreational"
            elif is_medical_cat:
                # Medical drug with no wiki signal: dose is a prescriber's domain,
                # so medical_rx — even if drug.community lists a clinical dose.
                # OTC drugs (ibuprofen, cetirizine, …) keep their on-package dose.
                cls = "otc" if is_otc else "medical_rx"
            elif weak_signal or is_rec_cat or rec_tag:
                # Non-medical: drug.community dose / recreational category / RC tag.
                cls = "recreational"
            elif is_otc or is_supplement:
                cls = "otc"
            else:
                cls = "medical_rx"

            total = total_by_sid.get(sid)
            implausible = 1 if (total is not None and total > 1440) else 0
            cur.execute(
                "UPDATE substances SET display_class = ?, duration_implausible = ? WHERE id = ?",
                (cls, implausible, sid),
            )
            counts[cls] += 1
        return dict(counts)

    def curate_common_card(self) -> dict[str, int]:
        """Make the Library's "Common" card a curated set, not an aggregator dump.

        Drops every upstream `common` tag and re-asserts it (source = piru-curated)
        for exactly ``COMMON_CARD_ALLOWLIST``. Runs AFTER dedup + classification so
        it acts on the final survivors. Any allowlist name that resolves to no
        substance is returned in ``missing`` (no silent drops — a merge/rename that
        orphans an entry surfaces in the build report)."""
        cur = self.cur
        cur.execute("DELETE FROM tags WHERE tag = 'common'")
        added = 0
        missing: list[str] = []
        for name in sorted(COMMON_CARD_ALLOWLIST):
            sid = self.substance_ids.get(normalise(name))
            if sid is None:
                missing.append(name)
                continue
            self.add_tag(sid, "piru-curated", "common")
            added += 1
        if missing:
            print(f"  curate_common_card MISSING: {missing}", file=sys.stderr)
        return {"common_tagged": added, "missing": len(missing)}

    def ingest_enrichment(self, path: Path) -> None:
        """Deep-pharma enrichment from the agent swarm. source = peer-review-primary
        for per-compound records (they cite primary literature per fact). For PDSP-sourced
        binding rows specifically (heuristic: target listed without further detail), keep
        peer-review-primary — the canonical source-tag system uses the reference, not the
        upstream aggregator. PDSP as a separate source is reserved for direct PDSP-DB pulls."""
        if not path.exists():
            return
        try:
            data = json.loads(path.read_text())
        except json.JSONDecodeError:
            return
        if not isinstance(data, list):
            return
        class_ids: dict[str, int] = {}
        slug = "peer-review-primary"
        for rec in data:
            if not isinstance(rec, dict):
                continue
            if rec.get("is_class_context"):
                cid = self.add_class_context(rec, source_slug=slug)
                if cid:
                    class_ids[rec.get("class_context_id") or rec.get("slug")] = cid
                continue
            name = rec.get("name")
            if not name:
                continue
            sid = self.upsert_substance(
                name,
                aliases=rec.get("aliases_added") or [],
                inchikey=rec.get("inchikey"),
                pubchem_cid=to_int(rec.get("pubchem_cid")),
                cas=rec.get("cas"),
                iupac=rec.get("iupac_name"),
                smiles=rec.get("smiles"),
                source_slug=slug,
            )
            if sid is None:
                continue
            for tag in rec.get("tags_to_add") or []:
                self.add_tag(sid, slug, tag, confidence=rec.get("confidence"))
            pharm = rec.get("pharmacology") or {}
            for b in pharm.get("binding") or []:
                self.add_binding(sid, slug, b)
            for f in pharm.get("functional") or []:
                self.add_functional(sid, slug, f)
            for b in pharm.get("biased_agonism") or []:
                self.add_biased(sid, slug, b)
            for o in pharm.get("receptor_oligomerisation") or []:
                self.add_oligomer(sid, slug, o)
            if pharm.get("downstream_signalling"):
                self.add_downstream(sid, slug, pharm["downstream_signalling"])
            for n in pharm.get("neuroimaging") or []:
                self.add_neuroimaging(sid, slug, n)
            human_pk = rec.get("human_pk") or {}
            for r in human_pk.get("routes") or []:
                self.add_pk_route(sid, slug, r)
            for c in human_pk.get("concentration_effect") or []:
                self.add_conc_effect(sid, slug, c)
            for m in rec.get("metabolism") or []:
                self.add_metabolism(sid, slug, m)
            for d in rec.get("drug_interactions_pk") or []:
                self.add_ddi(sid, slug, d)
            for o in rec.get("off_targets") or []:
                self.add_off_target(sid, slug, o)
            pgx = rec.get("pharmacogenetics") or {}
            for gene in pgx.get("relevant_genes") or []:
                self.add_pgx(
                    sid,
                    slug,
                    gene,
                    pgx.get("phenotype_effects") or "",
                    citation=pgx.get("reference"),
                )
            tol = rec.get("tolerance_and_dependence")
            if isinstance(tol, dict):
                summary_parts = []
                for k in ("receptor_downregulation_half_time", "withdrawal_syndrome"):
                    v = tol.get(k)
                    if v:
                        summary_parts.append(f"{k}: {v}")
                if summary_parts:
                    src = self.source_ids[slug]
                    try:
                        self.cur.execute(
                            "INSERT INTO tolerance(substance_id, source_id, build_rate, notes, citation_id) VALUES (?, ?, ?, ?, ?)",
                            (
                                sid,
                                src,
                                None,
                                " | ".join(summary_parts),
                                self.cite(tol.get("reference")),
                            ),
                        )
                        self.stats["tolerance"] += 1
                    except sqlite3.IntegrityError:
                        pass
            cid_slug = rec.get("class_context_id")
            if cid_slug and cid_slug in class_ids:
                self.link_substance_class(sid, class_ids[cid_slug])

    # ---- manifest ----

    def finalise(
        self,
        content_version: str,
        generator_version: str,
        substance_count: int,
        sources_summary: dict,
    ) -> None:
        for k, v in [
            ("schema_version", "5"),
            ("content_version", content_version),
            ("generated_at", datetime.now(UTC).isoformat()),
            ("generator_version", generator_version),
            ("substance_count", str(substance_count)),
        ]:
            self.cur.execute("INSERT INTO manifest(key, value) VALUES (?, ?)", (k, v))
        self.cur.execute(
            "INSERT INTO manifest(key, value) VALUES (?, ?)",
            ("sources_summary", json.dumps(sources_summary, sort_keys=True)),
        )


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> int:
    OUT_SQLITE.parent.mkdir(parents=True, exist_ok=True)
    if OUT_SQLITE.exists():
        OUT_SQLITE.unlink()

    db = sqlite3.connect(str(OUT_SQLITE))
    db.executescript(SCHEMA_SQL)
    build = Build(db)
    build.seed_sources()
    build.seed_effect_vocab()

    # Curated per-substance files first, so curated chemical identifiers win the
    # COALESCE in upsert_substance and curated names seed the wikidata allowlist.
    curated_names = set(build.ingest_curated_substances(CURATED_DIR))
    print(
        f"After curated ({build.stats.get('curated_files', 0)} files): {build.stats}",
        file=sys.stderr,
    )

    if SOURCED.exists():
        build.ingest_sourced_substances(SOURCED, known_names=curated_names)
        print(f"After sourced (per-record attribution): {build.stats}", file=sys.stderr)
    else:
        print(
            f"WARNING: {SOURCED} not found; falling back to merged JSON with piru-curated attribution.",
            file=sys.stderr,
        )
        build.ingest_bundled_substances(BUNDLED)
        print(f"After bundled (fallback): {build.stats}", file=sys.stderr)

    build.ingest_psychonautwiki_snapshot(PSYCHONAUTWIKI)
    print(f"After psychonautwiki: {build.stats}", file=sys.stderr)

    build.ingest_drug_community(DRUG_COMMUNITY)
    build.ingest_freeodwiki(FREEODWIKI)
    print(f"After drug.community: {build.stats}", file=sys.stderr)

    for f in sorted(ENRICHMENT_DIR.glob("*.json")):
        before = dict(build.stats)
        build.ingest_enrichment(f)
        delta = {
            k: build.stats[k] - before.get(k, 0)
            for k in build.stats
            if build.stats[k] != before.get(k, 0)
        }
        print(f"  + {f.name}: {delta}", file=sys.stderr)

    # External datasource ingest (pyrls/medtap = medical catalog + regulatory +
    # indications/contraindications/mechanism; benzos = diazepam-equivalency;
    # nps = chemical identifiers only). Runs before promote_via_tags so pyrls
    # categories participate in tag-fallback, and before classify_compounds so
    # regulatory_status is final.
    build.ingest_pyrls(PYRLS_EXT)
    print(f"After pyrls: {build.stats}", file=sys.stderr)
    build.ingest_medtap(MEDTAP_EXT)
    print(f"After medtap: {build.stats}", file=sys.stderr)
    build.ingest_benzos_cited(BENZOS_EXT)
    print(
        f"After benzos-cited: diazepam_equivalents={build.stats.get('diazepam_equivalents', 0)}",
        file=sys.stderr,
    )
    build.ingest_nps(NPS_EXT)
    print(
        f"After nps (identifier backfill): {build.stats.get('nps_identifier_matches', 0)} matches",
        file=sys.stderr,
    )

    # Tag-fallback pass: any substance currently in (or resolving to) "Other"
    # whose tags identify a specific class gets an additional piru-curated
    # category row so it leaves the Other bucket. Peptide is the load-bearing
    # case (28+ entries the agents tagged as 'peptide' but with category=Other).
    promoted = build.promote_via_tags()
    print(f"Tag-fallback promotion: {promoted}", file=sys.stderr)

    # Merge brand/generic duplicate records (Vyvanse→Lisdexamfetamine, …) that
    # arrived from different sources and never matched. Must run after all
    # ingest so both members exist, and before classify so the survivor is
    # classified once.
    deduped = build.dedup_substances()
    print(f"Substance dedup: {deduped}", file=sys.stderr)

    # Consolidate verified same-compound clusters the structural dedup leaves
    # split (RC analogues under code names with no/clashing InChIKeys). Runs
    # after dedup so it operates on the survivors.
    forced = build.apply_forced_merges()
    print(f"Forced merges: {forced}", file=sys.stderr)

    # Fold rows hand-tagged `duplicate-of-<X>` by prior enrichment into their
    # target (the structural dedup misses them — stub/clashing InChIKey). Runs
    # after forced merges so it operates on survivors; honours _DO_NOT_MERGE.
    self_dups = build.merge_self_flagged_duplicates(
        protect_norms={normalise(n) for n in curated_names}
    )
    print(f"Self-flagged duplicate merges: {self_dups}", file=sys.stderr)

    # Fold `<base>-<route>` name-suffix variants (Fluticasone-nasal,
    # Hydrocortisone-topical, Beclomethasone-inhaled …) into a single parent
    # `<base>`, moving the route out of the name into the `route` column. Runs
    # after dedup/forced-merges so it operates on survivors, and before
    # classify so the merged parent is classified once from final signals.
    collapsed = build.collapse_route_suffixes()
    print(f"Route-suffix collapse: {collapsed}", file=sys.stderr)

    # Fold curated salt variants (Magnesium Citrate/Glycinate/…, Lithium
    # Carbonate/orotate) into a shared parent, tagging each variant's dose ladder
    # with its `salt_form`. Same placement rationale as route collapse: after
    # dedup (operate on survivors), before classify (parent classified once).
    salts = build.fold_salt_families()
    print(f"Salt-family folding: {salts}", file=sys.stderr)

    # Stamp curated salt_rank (default-salt intent) + elemental_fraction onto the
    # salt-tagged dose rows. Must run right after folding (so the salt_form tags
    # exist) and asserts full coverage. Loader reads salt_rank in WS-2b; until
    # then it's forward-looking metadata that changes no dose value.
    salt_meta = build.apply_salt_metadata()
    print(f"Salt metadata: {salt_meta}", file=sys.stderr)

    # Audit decision (#5): drop the salt-tagged ACUTE durations on the Mg/Li
    # supplement parents — minerals/maintenance ions have no perceptible acute
    # curve, so those routes fall back to marker rendering. Dose ladders untouched.
    dur_audit = build.audit_salt_supplement_durations()
    print(f"Salt-supplement duration audit: {dur_audit}", file=sys.stderr)

    # Remove non-substance junk (enzyme/reagent names, hoaxes) and inert/fake
    # compounds (no dose data, no curated file). Runs after dedup/merges so a
    # junk row that was an unmerged duplicate has already folded.
    junk = build.drop_junk_and_inert(protect_norms={normalise(n) for n in curated_names})
    print(f"Junk/inert removal: {junk}", file=sys.stderr)

    # Drop content-less wikidata long-tail stubs (no dose/effect/mechanism/
    # indication/binding/duration and no recreational provenance). Runs after
    # dedup so unmerged-duplicate stubs have already folded into their survivor,
    # and after external ingest so pyrls/medtap data counts as content.
    dropped = build.drop_orphan_stubs(protect_norms={normalise(n) for n in curated_names})
    print(f"Orphan stub drop: {dropped}", file=sys.stderr)

    # Purge systematic/IUPAC/salt-form chemistry-noise aliases from the FINAL
    # table. Runs AFTER dedup so these still served as merge match keys
    # (e.g. "Lisdexamfetamine dimesylate" linking brand→generic) but never reach
    # the app as alias-subtitle clutter. Chemists get the IUPAC/CID via the
    # detail view's dedicated chemistry fields instead.
    purged = 0
    for rowid, alias in build.cur.execute("SELECT rowid, alias FROM aliases").fetchall():
        if is_chemnoise_alias(alias) and normalise(alias) not in build.salt_alias_protect:
            build.cur.execute("DELETE FROM aliases WHERE rowid=?", (rowid,))
            purged += 1
    print(f"Chemnoise alias purge: {purged}", file=sys.stderr)

    # Capitalise chemical-code aliases for display the same way names are
    # (2cb→2CB, 4-ho-met→4-HO-MET) — chem_caps only touches digit-bearing codes.
    # The display column only; search uses alias_normalized, so findability is
    # untouched. The app further collapses casing/hyphen variants for display.
    capped = 0
    for rowid, alias in build.cur.execute("SELECT rowid, alias FROM aliases").fetchall():
        fixed = chem_caps(alias)
        if fixed != alias:
            build.cur.execute("UPDATE aliases SET alias = ? WHERE rowid = ?", (fixed, rowid))
            capped += 1
    print(f"Alias chem-caps: {capped}", file=sys.stderr)

    # Purge per-substance wrong tags inherited from sources / merged-in stubs
    # (see _TAG_BLOCKLIST). Runs after dedup so it catches tags carried over by
    # the merge, and before classify_compounds (the dropped tags are not the
    # ones establishing these substances' recreational lineage).
    tags_purged = 0
    for sid, cname in build.cur.execute("SELECT id, canonical_name FROM substances").fetchall():
        blocked = _TAG_BLOCKLIST.get(normalise(cname))
        if not blocked:
            continue
        for tag in blocked:
            cur = build.cur.execute("DELETE FROM tags WHERE substance_id=? AND tag=?", (sid, tag))
            tags_purged += cur.rowcount
    print(f"Tag blocklist purge: {tags_purged}", file=sys.stderr)

    # Keep the "Research Chemicals" group genuine: drop the over-applied
    # research-chemical tag from peptides (own family) and well-established
    # compounds (popularity >= 0.3 — psilocin, 5-MeO-DMT, phenibut, GLP-1/healing
    # peptides). Runs after dedup + popularity are final.
    rc_purged = build.purge_overbroad_research_chemical_tag()
    print(f"Research-chemical tag purge: {rc_purged}", file=sys.stderr)

    # Drop the generic PIHKAL/TIHKAL index link where the specific chapter is
    # also cited (the "TIHKAL referenced twice" case). Identifier/database-page
    # citations were already filtered at cite(); this is the per-substance dedup
    # that needs the full reference set.
    book_pruned = build.prune_generic_book_citations()
    print(f"Generic book-citation prune: {book_pruned}", file=sys.stderr)

    # Drop links the validator (pipeline/audit/validate_links.py) confirmed dead
    # so no 404 ships. The committed link-cache.json is the proof of what we
    # checked; rerun the validator after data changes to refresh it.
    dead_dropped = build.drop_dead_citations(LINK_CACHE)
    print(f"Dead-citation drop: {dead_dropped}", file=sys.stderr)

    # Dedup the categories table — upstream merges left duplicate
    # (substance_id, category) pairs (MDMA carried "Empathogen" ×3), which skews
    # any category-count / exemplar logic that joins it.
    cat_dupes = build.cur.execute(
        "DELETE FROM categories WHERE rowid NOT IN "
        "(SELECT MIN(rowid) FROM categories GROUP BY substance_id, category)"
    ).rowcount
    print(f"Duplicate category rows removed: {cat_dupes}", file=sys.stderr)

    _pubchem_props = (
        json.loads(PUBCHEM_PROPERTIES.read_text()) if PUBCHEM_PROPERTIES.exists() else {}
    )
    _pubchem_ik_props = (
        json.loads(PUBCHEM_PROPERTIES_BY_INCHIKEY.read_text())
        if PUBCHEM_PROPERTIES_BY_INCHIKEY.exists()
        else {}
    )

    # Reconcile chemical identifiers against PubChem (snapshot:
    # data/sources/identifier-corrections.json, refresh via
    # reconcile_identifiers_pubchem.py). The catalog's identifiers are corrupt in
    # both directions — LLM-fabricated InChIKeys (enrichment) and wrong-regioisomer
    # SMILES (NPS vendor dump) — so each correction names the field PubChem found
    # wrong. Runs before the CID fill so resolution keys off the corrected key.
    if IDENTIFIER_RECONCILE.exists():
        rec = apply_identifier_reconciliation(
            build.cur.connection, json.loads(IDENTIFIER_RECONCILE.read_text())
        )
        print(
            f"Identifier reconciliation (PubChem): inchikey={rec['inchikey']} smiles={rec['smiles']}",
            file=sys.stderr,
        )
    # Curated manual layer for substances the reconciler couldn't auto-resolve
    # (no PubChem/CAS corroboration). Applied after — manual wins. Keys starting
    # with "_" (e.g. _comment) are metadata, not corrections.
    if IDENTIFIER_RECONCILE_MANUAL.exists():
        manual = {
            k: v
            for k, v in json.loads(IDENTIFIER_RECONCILE_MANUAL.read_text()).items()
            if not k.startswith("_")
        }
        rec_m = apply_identifier_reconciliation(build.cur.connection, manual)
        print(
            f"Identifier reconciliation (manual): inchikey={rec_m['inchikey']} "
            f"smiles={rec_m['smiles']} cas={rec_m['cas']}",
            file=sys.stderr,
        )

    # Fill pubchem_cid for substances that have an InChIKey but no CID, keyed by
    # InChIKey (exact structural match → CID↔InChIKey-consistent by construction).
    # Lifts CID coverage so the free-base correction below — and the property
    # enrichment — reach far more of the catalog. Snapshot:
    # data/sources/pubchem-cids.json (refresh via fetch_pubchem_cids.py).
    if PUBCHEM_CIDS.exists():
        cid_res = apply_pubchem_cids(build.cur.connection, json.loads(PUBCHEM_CIDS.read_text()))
        print(
            f"PubChem CIDs filled from InChIKey: {cid_res['filled']} "
            f"(skipped-unverifiable={cid_res['skipped_unverifiable']}, "
            f"formula-rejected={len(cid_res['rejected'])})",
            file=sys.stderr,
        )
        for r in cid_res["rejected"]:
            print(f"  formula mismatch, CID not filled: {r}", file=sys.stderr)

    # Correct verified-wrong chemical identifiers (wrong PubChem CID / InChIKey)
    # before the free-base override, so the corrected CID drives that lookup.
    id_fixes = apply_identifier_corrections(build.cur.connection, _pubchem_props)
    print(f"Identifier corrections: {len(id_fixes)}", file=sys.stderr)
    for name, change in sorted(id_fixes.items()):
        print(f"  {name}: {change}", file=sys.stderr)

    # Replace salt-form formula/MW with the PubChem free base keyed by CID (the
    # stored CID *is* the free base — DMT 6089 = C12H16N2). Sources hand us salts
    # (DMT·HCl, MDMA·HCl, LSD tartrate, amphetamine sulfate); the displayed doses
    # are free-base-scale, so the salt chemistry was inconsistent. Only verified
    # clean desalts are applied — wrong CIDs are skipped. Snapshot:
    # data/sources/pubchem-properties.json (refresh via fetch_pubchem_properties.py).
    if _pubchem_props:
        fb = apply_pubchem_freebase(build.cur.connection, _pubchem_props)
        print(
            f"PubChem formula: trusted={fb['trusted']} desalted={fb['desalted']} "
            f"unverified-skipped={len(fb['flagged'])} unverified-no-formula={fb['unverified_no_formula']}",
            file=sys.stderr,
        )
        for f in fb["flagged"]:
            print(f"  unverified CID, kept existing: {f}", file=sys.stderr)

        # Computed physicochemical descriptors (logP/TPSA/HBA/HBD) from the same
        # CID-keyed snapshot. Verified CIDs only — PubChem's consistent method
        # supersedes NPS-DataHub here; NPS keeps logD/pKa/LD50/mp/bp.
        pc = apply_pubchem_computed(build.cur.connection, _pubchem_props, _pubchem_ik_props)
        print(
            f"PubChem computed: logp={pc['logp']} tpsa={pc['tpsa']} "
            f"hba={pc['hba']} hbd={pc['hbd']}",
            file=sys.stderr,
        )

    # Display-name overrides, popularity scores, category corrections, CJK search
    # aliases, curated dose overrides, and peptide enrichment are no longer
    # applied here — they live on each compound's own data/curated/substances/
    # file and are ingested by ingest_curated_substances() above (curated runs
    # first, so its category/identifiers win resolution and a folded category
    # override beats a later tag-promotion via the PRIMARY KEY conflict).

    # Scrub chronic/therapeutic durations miscoded as acute curves, and migrate
    # real depot/long-acting windows into durations_of_action. Must run after all
    # ingest and before classify_compounds (which bakes duration_implausible from
    # the remaining durations).
    scrub = build.scrub_durations()
    print(f"Duration scrub: {scrub}", file=sys.stderr)

    # Flag dose-less catalog stubs (zero dose + duration + protocol rows from any
    # source). Runs after ALL dose/duration mutation (folding, audit, scrub) so
    # the count is final; the app can demote/badge these.
    stub_count = build.flag_dose_less_stubs()
    print(f"Dose-less stubs flagged: {stub_count}", file=sys.stderr)

    # Reproducible popularity from the committed Wikipedia-pageviews snapshot
    # (chemical-verified). Authoritative — supersedes hand-set curated values.
    # Before classify (which reads popularity for the RC-established threshold)
    # and keyed by the now-final canonical_names. Refresh with
    # fetch_wikipedia_popularity.py (incremental; the build never fetches).
    if WIKIPEDIA_POPULARITY.exists():
        pop_n = apply_wikipedia_popularity(
            build.cur.connection, json.loads(WIKIPEDIA_POPULARITY.read_text())
        )
        print(f"Wikipedia popularity applied: {pop_n}", file=sys.stderr)

    # Display-policy classification — bakes display_class + duration_implausible
    # from the now-final signals (recreational dose/duration provenance,
    # category, tags, regulatory status). Must run LAST.
    classified = build.classify_compounds()
    print(f"Display classification: {classified}", file=sys.stderr)

    # Curate the Library's "Common" card down to the hand-picked everyday set
    # (drops the ~70 aggregator-flagged RCs/designer compounds). After classify
    # so it owns the final `common` tag; the tag only feeds the Common browse
    # card (not in REC_TAGS), so re-curating it changes no display class.
    common_card = build.curate_common_card()
    print(f"Common card curated: {common_card}", file=sys.stderr)

    # Re-stamp curated displayName overrides onto the final survivors (after all
    # merges/folds settle) so a merge that demoted the curated name to an alias
    # can't drop its display override. See reapply_curated_display_names.
    redisplay = build.reapply_curated_display_names(CURATED_DIR)
    print(f"Curated display_name re-applied: {redisplay}", file=sys.stderr)

    # Effect controlled-vocabulary coverage + curation candidates (no-silent-caps:
    # whitelisted effects with no vocab_id still ship via raw `text`, but surface
    # here so a future vocab entry can be added).
    vocab_linked, vocab_null = db.execute(
        "SELECT COUNT(vocab_id), COUNT(*) - COUNT(vocab_id) FROM effects"
    ).fetchone()
    print(
        f"Effect vocab: {build.stats.get('effect_vocab', 0)} entries; "
        f"{vocab_linked} effect rows linked, {vocab_null} unlinked (raw fallback)",
        file=sys.stderr,
    )
    if build.effect_vocab_unmatched:
        print(
            "  unmatched effect strings (curation candidates): "
            + ", ".join(f"{t!r}×{n}" for t, n in build.effect_vocab_unmatched.most_common(20)),
            file=sys.stderr,
        )

    substance_count = db.execute("SELECT COUNT(*) FROM substances").fetchone()[0]
    content_version = datetime.now(UTC).strftime("%Y-%m-%d.0")
    sources_summary = {
        slug: {
            "dose_ranges": db.execute(
                "SELECT COUNT(*) FROM dose_ranges WHERE source_id = (SELECT id FROM sources WHERE slug = ?)",
                (slug,),
            ).fetchone()[0],
            "bindings": db.execute(
                "SELECT COUNT(*) FROM bindings    WHERE source_id = (SELECT id FROM sources WHERE slug = ?)",
                (slug,),
            ).fetchone()[0],
            "categories": db.execute(
                "SELECT COUNT(*) FROM categories  WHERE source_id = (SELECT id FROM sources WHERE slug = ?)",
                (slug,),
            ).fetchone()[0],
        }
        for slug, *_ in SOURCES
    }
    build.finalise(
        content_version, "build-sqlite-database.py 0.1.0", substance_count, sources_summary
    )
    db.commit()

    # Vacuum + analyze for deterministic, optimised output. The shipped file
    # must be self-contained: a WAL-mode DB opened read-only from the app
    # bundle fails with SQLITE_CANTOPEN unless its -shm/-wal sidecars ship
    # too (they're gitignored, so fresh checkouts would crash at launch).
    db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    db.execute("PRAGMA journal_mode = DELETE")
    db.execute("VACUUM")
    db.execute("ANALYZE")
    db.commit()
    db.close()

    # sha256
    h = hashlib.sha256()
    with OUT_SQLITE.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    sha = h.hexdigest()
    size = OUT_SQLITE.stat().st_size

    manifest = {
        "schema_version": 5,
        "content_version": content_version,
        "generated_at": datetime.now(UTC).isoformat(),
        "generator_version": "pipeline/build/sqlite.py 0.1.0",
        "substance_count": substance_count,
        "sources": sources_summary,
        "sqlite_path": "Piru/Data/piru-substances.sqlite",
        "sqlite_sha256": sha,
        "sqlite_size_bytes": size,
        "release_notes": "Initial SQLite bundled build. Multi-source attribution per field. 18 enrichment batches merged.",
    }
    OUT_MANIFEST.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")

    # Build report
    lines = [
        "# Piru SQLite build report",
        "",
        f"Built {content_version} → `{OUT_SQLITE.relative_to(REPO)}` ({size:,} bytes, sha256 `{sha}`)",
        "",
        "## Row counts",
        "",
        "| Table | Rows |",
        "|---|---|",
    ]
    tables = [
        "substances",
        "aliases",
        "sources",
        "citations",
        "categories",
        "tags",
        "dose_ranges",
        "durations",
        "half_lives",
        "mechanisms_summary",
        "effects",
        "subjective_effects",
        "tolerance",
        "indications",
        "contraindications",
        "diazepam_equivalents",
        "bindings",
        "functional_assays",
        "biased_agonism",
        "receptor_oligomers",
        "downstream_signalling",
        "neuroimaging",
        "pk_routes",
        "concentration_effects",
        "metabolism",
        "drug_interactions_pk",
        "pharmacogenetics",
        "off_targets",
        "class_contexts",
        "substance_classes",
    ]
    db = sqlite3.connect(str(OUT_SQLITE))
    for t in tables:
        n = db.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
        lines.append(f"| {t} | {n:,} |")
    lines.append("")
    lines.append("## Per-source coverage")
    lines.append("")
    lines.append("| Source | Dose ranges | Bindings | Categories | Tags |")
    lines.append("|---|---|---|---|---|")
    coverage_rows = db.execute("""
        SELECT src.slug,
               (SELECT COUNT(*) FROM dose_ranges WHERE source_id = src.id) AS dose_ranges,
               (SELECT COUNT(*) FROM bindings    WHERE source_id = src.id) AS bindings,
               (SELECT COUNT(*) FROM categories  WHERE source_id = src.id) AS categories,
               (SELECT COUNT(*) FROM tags        WHERE source_id = src.id) AS tags
          FROM sources src
         ORDER BY src.default_priority
    """).fetchall()
    coverage_by_slug = {r[0]: r for r in coverage_rows}
    for slug, *_ in SOURCES:
        r = coverage_by_slug.get(slug, (slug, 0, 0, 0, 0))
        lines.append(f"| {slug} | {r[1]:,} | {r[2]:,} | {r[3]:,} | {r[4]:,} |")
    db.close()
    OUT_REPORT.write_text("\n".join(lines))

    print("\nDone:", file=sys.stderr)
    print(f"  {OUT_SQLITE}     ({size:,} bytes, sha256 {sha[:16]}...)", file=sys.stderr)
    print(f"  {OUT_MANIFEST}", file=sys.stderr)
    print(f"  {OUT_REPORT}", file=sys.stderr)
    print(f"  {substance_count:,} substances", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
