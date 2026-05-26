#!/usr/bin/env python3
"""Build Piru/Data/piru-substances.sqlite from every JSON source we ship.

Inputs (all already in the repo):
  Piru/Data/substances-bundled.json       — SubstanceCollector merge output
  Piru/Data/drug-community-data.json      — drug.community snapshot
  Tools/SubstanceCollector/curated-overlay.json — hand-curated overlay
  Exports/enrichment/*.json               — deep-pharma enrichment swarm output
  Exports/enrichment-class-context.json   — class-context summaries

Outputs:
  Piru/Data/piru-substances.sqlite        — bundled read-only database
  Piru/Data/manifest.json                 — version + sha256 + release notes
  Exports/sqlite-build-report.md          — build statistics

Run from the repo root:
    python3 Exports/build-sqlite-database.py
"""

from __future__ import annotations

import csv
import glob
import hashlib
import json
import os
import re
import sqlite3
import sys
import unicodedata
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUT_SQLITE   = REPO / "Piru/Data/piru-substances.sqlite"
OUT_MANIFEST = REPO / "Piru/Data/manifest.json"
OUT_REPORT   = REPO / "Exports/sqlite-build-report.md"

SOURCED       = REPO / "Piru/Data/sourced-substances.json"
BUNDLED       = REPO / "Piru/Data/substances-bundled.json"
DRUG_COMMUNITY = REPO / "Piru/Data/drug-community-data.json"
CURATED       = REPO / "Tools/SubstanceCollector/curated-overlay.json"
ENRICHMENT_DIR = REPO / "Exports/enrichment"

# Default source priority. Lower number = higher priority. User can override.
SOURCES = [
    ("piru-curated",       "Piru hand-curated overlay",          "Curated by the Piru maintainers, prioritised for accuracy on harm-reduction-critical compounds."),
    ("peer-review-primary","Primary peer-reviewed literature",   "Cited DOI/PMID from primary journal articles. Deep-pharma enrichment swarm output."),
    ("psychonautwiki",     "PsychonautWiki",                     "Community harm-reduction wiki."),
    ("tripsit",            "TripSit factsheets",                 "Community harm-reduction factsheets and combo matrix."),
    ("drug.community",     "drug.community",                     "Curated long-tail research-chemical dataset."),
    ("dailymed",           "FDA DailyMed",                       "FDA-approved prescribing labels."),
    ("erowid-pihkal",      "Erowid PIHKAL Part 2",               "Shulgin phenethylamine compendium, Erowid Part 2 only (non-commercial redistribution permitted)."),
    ("erowid-tihkal",      "Erowid TIHKAL Part 2",               "Shulgin tryptamine compendium, Erowid Part 2 only."),
    ("pdsp",               "UNC PDSP Ki database",               "Canonical receptor affinity database (Roth lab)."),
    ("pubchem",            "PubChem",                            "NIH chemical compound identifiers."),
    ("wikidata",           "Wikidata",                           "CC0 structured data; identifier-only for long-tail compounds."),
    ("dea-orange-book",    "DEA Orange Book",                    "US controlled-substance scheduling."),
]


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
    normalized_name TEXT NOT NULL,
    inchikey        TEXT,
    pubchem_cid     INTEGER,
    cas             TEXT,
    iupac_name      TEXT,
    smiles          TEXT,
    formula         TEXT,
    molecular_weight REAL
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
    citation_id   INTEGER REFERENCES citations(id),
    UNIQUE (substance_id, route, source_id)
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
    citation_id   INTEGER REFERENCES citations(id),
    UNIQUE (substance_id, route, source_id, phase)
);
CREATE INDEX idx_durations_substance_route ON durations(substance_id, route);

CREATE TABLE half_lives (
    substance_id      INTEGER NOT NULL REFERENCES substances(id),
    source_id         INTEGER NOT NULL REFERENCES sources(id),
    half_life_minutes REAL NOT NULL,
    notes             TEXT,
    citation_id       INTEGER REFERENCES citations(id),
    PRIMARY KEY (substance_id, source_id)
);

CREATE TABLE mechanisms_summary (
    substance_id INTEGER NOT NULL REFERENCES substances(id),
    source_id    INTEGER NOT NULL REFERENCES sources(id),
    summary      TEXT NOT NULL,
    description  TEXT,
    citation_id  INTEGER REFERENCES citations(id),
    PRIMARY KEY (substance_id, source_id)
);

CREATE TABLE effects (
    id           INTEGER PRIMARY KEY,
    substance_id INTEGER NOT NULL REFERENCES substances(id),
    source_id    INTEGER NOT NULL REFERENCES sources(id),
    text         TEXT NOT NULL,
    kind         TEXT,
    citation_id  INTEGER REFERENCES citations(id)
);
CREATE INDEX idx_effects_substance ON effects(substance_id);

CREATE TABLE subjective_effects (
    id           INTEGER PRIMARY KEY,
    substance_id INTEGER NOT NULL REFERENCES substances(id),
    source_id    INTEGER NOT NULL REFERENCES sources(id),
    name         TEXT NOT NULL,
    description  TEXT,
    citation_id  INTEGER REFERENCES citations(id)
);
CREATE INDEX idx_subjective_substance ON subjective_effects(substance_id);

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

CREATE TABLE manifest (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
"""


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def normalise(s: str) -> str:
    s = unicodedata.normalize("NFKD", s or "").lower().strip()
    s = re.sub(r"^\(\s*[+\-±rs]\s*\)\s*-?\s*", "", s)
    s = re.sub(r"\s*[·.]?\s*(hcl|hydrochloride|sulfate|sulphate|fumarate|tartrate|maleate|mesylate|citrate|hbr|hydrobromide)\s*$", "", s)
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


# Three-letter+ acronyms that should be ALL CAPS even after title-casing.
# Used by `smart_title_case` to handle entries that arrived all-lowercase
# from drug.community / TripSit but represent acronyms (lsd, mdma, gbl).
_ACRONYMS = {
    "lsd", "mdma", "mda", "mde", "dmt", "dxm", "pcp", "mxe", "thc", "cbd",
    "cbn", "cbg", "cbc", "cbdv", "thcv", "thcp", "hhc", "gbl", "ghb",
    "gaba", "maoi", "ssri", "snri", "ndri", "sari", "lsa", "lsh", "amt",
    "aet", "dpt", "dipt", "mipt", "dmd", "nbome", "nboh", "nbmd", "nbf",
    "pmma", "pma", "mbdb", "tfmpp", "mcpp", "5-meo", "4-aco", "4-ho", "5-ho",
    "5-ht", "4-fa", "4-ma", "2c", "25i", "25c", "25b", "25h", "25n",
    "iv", "im", "po", "sl", "br", "us", "uk", "eu",
}


def smart_title_case(name: str) -> str:
    """Title-case a substance name when the source supplied it all-lowercase.
    Preserves chemical naming conventions: known acronyms (LSD, MDMA, GBL)
    stay uppercase; words with embedded digits/hyphens get their first letter
    of each alpha run capitalised.

    Names already containing any uppercase letter are returned unchanged —
    the source's casing is presumed intentional (preserves "MDMA", "5-MeO-DMT",
    etc.).
    """
    if not name or any(c.isupper() for c in name):
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


def is_chemistry_noise(name: str) -> bool:
    """True if the substance name looks like a IUPAC chemistry artefact rather
    than a substance someone would log in a harm-reduction tracker."""
    n = (name or "").strip()
    return not n or bool(_CHEM_NOISE_PREFIX.search(n)) or bool(_CHEM_NOISE_BODY.search(n))


# Canonical category enum (mirrors SubstanceCategory in Swift). Keep in sync
# with Piru/Models/Substance.swift `SubstanceCategory` rawValue strings.
_CATEGORY_ENUM = {
    "Stimulant", "Psychedelic", "Dissociative", "Dysdelic", "Opioid",
    "Benzodiazepine", "GABAergic", "Empathogen", "Cannabinoid", "Nootropic",
    "AMPAkine", "Eugeroic", "Depressant", "Antidepressant", "Antipsychotic",
    "Analgesic", "Antihistamine", "Cardiovascular", "Antimicrobial",
    "Gastrointestinal", "Respiratory", "Endocrine", "Immunological",
    "Supplement", "Peptide", "Anticonvulsant", "Other",
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
    (re.compile(r"\b(peptide|peptide[\s-]?mimetic|GLP[\s-]?1[\s-]?agonist|GIP[\s-]?agonist|GHRH[\s-]?analogue|GH[\s-]?secretagogue|healing[\s-]?peptide|nootropic[\s-]?peptide|melanocortin[\s-]?agonist)\b", re.I), "Peptide"),
    # Anticonvulsant / mood-stabilizer covers antiseizure meds AND lithium.
    # Mood stabilizers used psychiatrically (lamotrigine, valproate, lithium)
    # land here rather than Antidepressant — they aren't antidepressants.
    (re.compile(r"\b(anticonvulsant|antiepileptic|mood[\s-]?(stabiliser|stabilizer)|antiseizure)\b", re.I), "Anticonvulsant"),
    (re.compile(r"\b(antipsychotic|neuroleptic|atypical antipsychotic)\b", re.I), "Antipsychotic"),
    (re.compile(r"\b(antihistamine|H[12][\s-]?antagonist|H[12][\s-]?blocker)\b", re.I), "Antihistamine"),
    (re.compile(r"\b(SSRI|SNRI|MAOI|NDRI|SARI|NaSSA|TCA|tricyclic|tetracyclic|monoamine[\s-]?oxidase[\s-]?inhibitor)\b", re.I), "Antidepressant"),
    (re.compile(r"\bantidepressant\b", re.I), "Antidepressant"),
    # --- Cannabinoid & opioid (chemistry-defined, take precedence) ---
    (re.compile(r"\bcannabinoid\b|\bCB[12][\s-]?agonist\b|\bphytocannabinoid\b", re.I), "Cannabinoid"),
    (re.compile(r"\b(μ[\s-]?opioid|µ[\s-]?opioid|mu[\s-]?opioid|opioid|opiate|narcotic|nitazene|fentanyl|fentanyl[\s-]?class)\b", re.I), "Opioid"),
    # --- Dissociative beats psychedelic (NMDA mechanism) ---
    (re.compile(r"\bdissociative\b|\bNMDA[\s-]?(receptor[\s-]?)?antagonist\b|\bPCP[\s-]?(site|analogue|class)\b|\bketamine[\s-]?class\b", re.I), "Dissociative"),
    # --- Dysdelic (κ-opioid hallucinogens) ---
    (re.compile(r"\bdysdelic\b|\b(κ|kappa)[\s-]?opioid\b|\bsalvinorin\b", re.I), "Dysdelic"),
    # --- Psychedelic beats empathogen + stimulant ---
    (re.compile(r"\bpsychedelic\b|\bhallucinogen\b|\b5[\s-]?HT2A[\s-]?(agonist|partial[\s-]?agonist)\b|\bDOx\b|\b2C[\s-]?[xX]?\b", re.I), "Psychedelic"),
    # --- Empathogen / entactogen ---
    (re.compile(r"\b(empathogen|entactogen)\b", re.I), "Empathogen"),
    # --- GABAergic & benzodiazepine ---
    (re.compile(r"\bbenzodiazepine\b", re.I), "Benzodiazepine"),
    (re.compile(r"\b(gabapentinoid|gabaergic|alpha[\s-]?2[\s-]?delta|α2δ)\b", re.I), "GABAergic"),
    # --- Eugeroic before generic stimulant ---
    (re.compile(r"\b(eugeroic|wakefulness[\s-]?promoting|afinil)\b", re.I), "Eugeroic"),
    # --- AMPAkine (ampakine, AMPA PAM) ---
    (re.compile(r"\b(AMPAkine|ampakine|AMPA[\s-]?(receptor[\s-]?)?(positive[\s-]?)?modulator|AMPA[\s-]?PAM)\b", re.I), "AMPAkine"),
    # --- Nootropic ---
    (re.compile(r"\b(nootropic|racetam)\b", re.I), "Nootropic"),
    # --- Antimicrobial ---
    (re.compile(r"\b(antimicrobial|antibiotic|antifungal|antiviral|antimalarial|antiparasitic)\b", re.I), "Antimicrobial"),
    # --- Cardiovascular ---
    (re.compile(r"\b(cardiovascular|beta[\s-]?blocker|β[\s-]?blocker|antihypertensive|alpha[\s-]?(1|2)[\s-]?(agonist|blocker)|calcium[\s-]?channel[\s-]?blocker|ACE[\s-]?inhibitor|ARB|statin|diuretic|antiarrhythmic|vasodilator)\b", re.I), "Cardiovascular"),
    # --- Gastrointestinal / antiemetic ---
    (re.compile(r"\b(antiemetic|antidiarrhe[ai]l|laxative|proton[\s-]?pump[\s-]?inhibitor|PPI|prokinetic)\b", re.I), "Gastrointestinal"),
    # --- Respiratory ---
    (re.compile(r"\b(bronchodilator|β2[\s-]?agonist|mucolytic|antitussive|expectorant)\b", re.I), "Respiratory"),
    # --- Endocrine ---
    (re.compile(r"\b(estrogen|androgen|progestin|insulin|thyroid|GLP[\s-]?1|GIP|aromatase|hormone|steroid|corticosteroid)\b", re.I), "Endocrine"),
    # --- Analgesic (non-opioid) ---
    (re.compile(r"\b(NSAID|paracetamol|acetaminophen|analgesic)\b", re.I), "Analgesic"),
    # --- Supplement / vitamin ---
    (re.compile(r"\b(supplement|vitamin|mineral|adaptogen|amino[\s-]?acid|herbal|nutraceutical)\b", re.I), "Supplement"),
    # --- Stimulant (after all higher-priority classes) ---
    (re.compile(r"\b(stimulant|sympathomimetic|monoamine[\s-]?releaser|DA[\s-]?releaser|NDRI[\s-]?stimulant|amphetamine|cathinone|piperazine[\s-]?stimulant|psychostimulant)\b", re.I), "Stimulant"),
    # --- Depressant (catch-all for sedative-hypnotics not benzo/GABAergic) ---
    (re.compile(r"\b(depressant|sedative|hypnotic|anxiolytic|barbiturate|GHB|GABA[\s-]?A[\s-]?(positive[\s-]?)?(allosteric[\s-]?)?modulator|GABAA[\s-]?PAM)\b", re.I), "Depressant"),
    # --- Deliriant → Antihistamine bucket (deliriants are anticholinergic; bucket with antihistamines) ---
    (re.compile(r"\b(deliriant|anticholinergic|muscarinic[\s-]?antagonist)\b", re.I), "Antihistamine"),
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


def parse_reference(ref: str | None) -> tuple[str | None, int | None, str | None]:
    """Parse a 'doi:10.x/y' | 'pmid:12345' | 'https://...' reference string."""
    if not ref:
        return (None, None, None)
    s = str(ref).strip()
    if not s:
        return (None, None, None)
    low = s.lower()
    if low.startswith("doi:"):
        return (s[4:].strip().lower(), None, None)
    if low.startswith("pmid:"):
        try:
            return (None, int(s[5:].strip()), None)
        except ValueError:
            return (None, None, s)
    if low.startswith("https://") or low.startswith("http://"):
        # Try to extract DOI from URL
        m = re.search(r"10\.\d{4,9}/[^\s]+", s)
        if m:
            return (m.group(0).lower(), None, s)
        m = re.search(r"/(\d{6,9})(?:/|$)", s)
        if m and "pubmed" in low:
            try:
                return (None, int(m.group(1)), s)
            except ValueError:
                pass
        return (None, None, s)
    if re.match(r"^10\.\d{4,9}/", s):
        return (s.lower(), None, None)
    return (None, None, s)


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
_ROUTE_ALIASES = {
    "insufflated":     "insufflation",
    "snorted":         "insufflation",
    "snorting":        "insufflation",
    "inhaled":         "inhalation",
    "vaporized":       "inhalation",
    "vaporised":       "inhalation",
    "smoke":           "smoked",
    "iv":              "intravenous",
    "im":              "intramuscular",
    "sc":              "subcutaneous",
    "subq":            "subcutaneous",
    "sublingually":    "sublingual",
    "buccally":        "buccal",
    "rectally":        "rectal",
    "po":              "oral",
    "by mouth":        "oral",
}


def normalise_route(route: str) -> str:
    r = (route or "").strip().lower()
    return _ROUTE_ALIASES.get(r, r)


# ---------------------------------------------------------------------------
# Build pipeline
# ---------------------------------------------------------------------------

class Build:
    def __init__(self, db: sqlite3.Connection):
        self.db = db
        self.cur = db.cursor()
        self.source_ids: dict[str, int] = {}
        self.substance_ids: dict[str, int] = {}  # normalised_name -> id
        self.citation_cache: dict[tuple[str | None, int | None, str | None], int] = {}
        self.stats: dict[str, int] = defaultdict(int)

    # ---- seeds ----

    def seed_sources(self) -> None:
        for prio, (slug, name, desc) in enumerate(SOURCES, start=1):
            self.cur.execute(
                "INSERT INTO sources(slug, display_name, description, default_priority, default_enabled) VALUES (?, ?, ?, ?, 1)",
                (slug, name, desc, prio),
            )
            self.source_ids[slug] = self.cur.lastrowid

    # ---- citations ----

    def cite(self, ref: str | None) -> int | None:
        if not ref:
            return None
        key = parse_reference(ref)
        if key == (None, None, None):
            return None
        if key in self.citation_cache:
            return self.citation_cache[key]
        doi, pmid, url = key
        try:
            self.cur.execute(
                "INSERT INTO citations(doi, pmid, url) VALUES (?, ?, ?)",
                (doi, pmid, url),
            )
            cid = self.cur.lastrowid
        except sqlite3.IntegrityError:
            row = self.cur.execute(
                "SELECT id FROM citations WHERE doi IS ? AND pmid IS ? AND url IS ?",
                (doi, pmid, url),
            ).fetchone()
            cid = row[0]
        self.citation_cache[key] = cid
        return cid

    # ---- substances ----

    def upsert_substance(self, name: str, *, aliases: list[str] | None = None,
                         inchikey: str | None = None, pubchem_cid: int | None = None,
                         cas: str | None = None, iupac: str | None = None,
                         smiles: str | None = None, source_slug: str | None = None) -> int | None:
        name = (name or "").strip()
        if not name:
            return None
        # Single choke-point for blocking IUPAC chemistry noise from any
        # ingester (wikidata SPARQL, drug.community, enrichment).
        if is_chemistry_noise(name):
            return None
        name = smart_title_case(name)
        norm = normalise(name)
        if norm in self.substance_ids:
            sid = self.substance_ids[norm]
            # Backfill identifier columns if we now have something better
            self.cur.execute(
                "UPDATE substances SET inchikey = COALESCE(inchikey, ?), pubchem_cid = COALESCE(pubchem_cid, ?), cas = COALESCE(cas, ?), iupac_name = COALESCE(iupac_name, ?), smiles = COALESCE(smiles, ?) WHERE id = ?",
                (inchikey, pubchem_cid, cas, iupac, smiles, sid),
            )
        else:
            try:
                self.cur.execute(
                    "INSERT INTO substances(canonical_name, normalized_name, inchikey, pubchem_cid, cas, iupac_name, smiles) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    (name, norm, inchikey, pubchem_cid, cas, iupac, smiles),
                )
                sid = self.cur.lastrowid
            except sqlite3.IntegrityError:
                # Race on canonical_name — happens when name normalises to existing entry
                row = self.cur.execute("SELECT id FROM substances WHERE canonical_name = ?", (name,)).fetchone()
                if not row:
                    return None
                sid = row[0]
            self.substance_ids[norm] = sid
            self.stats["substances"] += 1

        for alias in (aliases or []):
            self._add_alias(sid, alias, source_slug)
        return sid

    def _add_alias(self, sid: int, alias: str, source_slug: str | None) -> None:
        alias = (alias or "").strip()
        if not alias:
            return
        source_id = self.source_ids.get(source_slug) if source_slug else None
        try:
            self.cur.execute(
                "INSERT INTO aliases(substance_id, alias, alias_normalized, source_id) VALUES (?, ?, ?, ?)",
                (sid, alias, normalise(alias), source_id),
            )
            self.stats["aliases"] += 1
        except sqlite3.IntegrityError:
            pass  # already present

    # ---- per-source field inserters ----

    def add_category(self, sid: int, source_slug: str, category: str, confidence: str | None = None) -> None:
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
        if not tag:
            return
        src = self.source_ids[source_slug]
        try:
            self.cur.execute(
                "INSERT INTO tags(substance_id, tag, source_id, confidence) VALUES (?, ?, ?, ?)",
                (sid, tag, src, confidence),
            )
            self.stats["tags"] += 1
        except sqlite3.IntegrityError:
            pass

    def add_dose(self, sid: int, source_slug: str, route: str, unit: str,
                 *, threshold=None, light=None, common=None, strong=None, heavy=None,
                 notes: str | None = None, citation: str | None = None) -> None:
        if not route:
            return
        src = self.source_ids[source_slug]
        ll, lu = (None, None) if not light else (to_float(light.get("lower")), to_float(light.get("upper")))
        cl, cu = (None, None) if not common else (to_float(common.get("lower")), to_float(common.get("upper")))
        sl, su = (None, None) if not strong else (to_float(strong.get("lower")), to_float(strong.get("upper")))
        try:
            self.cur.execute(
                "INSERT INTO dose_ranges(substance_id, route, source_id, unit, threshold, light_lower, light_upper, common_lower, common_upper, strong_lower, strong_upper, heavy, notes, citation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (sid, normalise_route(route), src, unit or "mg",
                 to_float(threshold), ll, lu, cl, cu, sl, su, to_float(heavy),
                 notes, self.cite(citation)),
            )
            self.stats["dose_ranges"] += 1
        except sqlite3.IntegrityError:
            pass

    def add_duration_profile(self, sid: int, source_slug: str, route: str,
                             profile: dict, citation: str | None = None) -> None:
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
                    "INSERT INTO durations(substance_id, route, source_id, phase, min_minutes, max_minutes, citation_id) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    (sid, normalise_route(route), src, phase, mn, mx, self.cite(citation)),
                )
                self.stats["durations"] += 1
            except sqlite3.IntegrityError:
                pass

    def add_half_life(self, sid: int, source_slug: str, minutes: float, citation: str | None = None) -> None:
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

    def add_mechanism_summary(self, sid: int, source_slug: str, summary: str,
                              description: str | None = None, citation: str | None = None) -> None:
        if not summary:
            return
        src = self.source_ids[source_slug]
        try:
            self.cur.execute(
                "INSERT INTO mechanisms_summary(substance_id, source_id, summary, description, citation_id) VALUES (?, ?, ?, ?, ?)",
                (sid, src, summary, description, self.cite(citation)),
            )
            self.stats["mechanisms_summary"] += 1
        except sqlite3.IntegrityError:
            pass

    def add_effect(self, sid: int, source_slug: str, text: str, kind: str | None = None) -> None:
        if not text:
            return
        src = self.source_ids[source_slug]
        self.cur.execute(
            "INSERT INTO effects(substance_id, source_id, text, kind) VALUES (?, ?, ?, ?)",
            (sid, src, text, kind),
        )
        self.stats["effects"] += 1

    def add_subjective_effect(self, sid: int, source_slug: str, name: str, description: str | None = None) -> None:
        if not name:
            return
        src = self.source_ids[source_slug]
        self.cur.execute(
            "INSERT INTO subjective_effects(substance_id, source_id, name, description) VALUES (?, ?, ?, ?)",
            (sid, src, name, description),
        )
        self.stats["subjective_effects"] += 1

    def add_tolerance(self, sid: int, source_slug: str, t: dict) -> None:
        if not t:
            return
        src = self.source_ids[source_slug]
        try:
            self.cur.execute(
                "INSERT INTO tolerance(substance_id, source_id, half_life_days, full_reset_days, build_rate, notes) VALUES (?, ?, ?, ?, ?, ?)",
                (sid, src, to_float(t.get("halfLife") or t.get("half_life_days")),
                 to_float(t.get("fullResetDays") or t.get("full_reset_days")),
                 t.get("buildRate") or t.get("build_rate"),
                 t.get("notes")),
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
            (sid, b.get("target"), b.get("action") or "modulator",
             to_float(b.get("ki_nm")), to_float(ki_ci[0]) if isinstance(ki_ci, list) and len(ki_ci) > 0 else None,
             to_float(ki_ci[1]) if isinstance(ki_ci, list) and len(ki_ci) > 1 else None,
             to_float(b.get("kd_nm")), to_float(b.get("ec50_nm")), to_float(b.get("ic50_nm")),
             to_float(b.get("emax_pct")), to_float(b.get("intrinsic_activity_pct")),
             b.get("reference_agonist"), b.get("species"), b.get("tissue_or_cell"),
             b.get("radioligand_or_probe") or b.get("radioligand"),
             b.get("assay_buffer_notes") or b.get("assay_notes"),
             src, self.cite(b.get("reference")), 1 if b.get("is_review") else 0,
             b.get("notes")),
        )
        self.stats["bindings"] += 1

    def add_functional(self, sid: int, source_slug: str, f: dict) -> None:
        if not isinstance(f, dict) or not f.get("target"):
            return
        src = self.source_ids[source_slug]
        self.cur.execute(
            "INSERT INTO functional_assays(substance_id, target, readout, ec50_nm, ic50_nm, emax_pct, reference_agonist, species, cell_system, source_id, citation_id, notes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (sid, f.get("target"), f.get("readout") or "unspecified",
             to_float(f.get("ec50_nm")), to_float(f.get("ic50_nm")), to_float(f.get("emax_pct")),
             f.get("reference_agonist"), f.get("species"), f.get("cell_system"),
             src, self.cite(f.get("reference")), f.get("notes")),
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
            (sid, b.get("target"), pathways, to_float(b.get("bias_factor_log")),
             b.get("bias_reference_compound"), b.get("interpretation"),
             src, self.cite(b.get("reference"))),
        )
        self.stats["biased_agonism"] += 1

    def add_oligomer(self, sid: int, source_slug: str, o: dict) -> None:
        if not isinstance(o, dict) or not o.get("complex"):
            return
        src = self.source_ids[source_slug]
        self.cur.execute(
            "INSERT INTO receptor_oligomers(substance_id, complex_description, evidence_type, functional_consequence, source_id, citation_id) VALUES (?, ?, ?, ?, ?, ?)",
            (sid, o.get("complex"), o.get("evidence"), o.get("functional_consequence"),
             src, self.cite(o.get("reference"))),
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
            (sid, n.get("modality"), n.get("finding") or "",
             src, self.cite(n.get("reference"))),
        )
        self.stats["neuroimaging"] += 1

    def add_pk_route(self, sid: int, source_slug: str, r: dict) -> None:
        if not isinstance(r, dict) or not r.get("route"):
            return
        src = self.source_ids[source_slug]
        self.cur.execute(
            "INSERT INTO pk_routes(substance_id, route, source_id, bioavailability_pct, cmax_ng_per_ml, tmax_min, auc_0_inf_ng_h_per_ml, half_life_min, vd_l_per_kg, clearance_ml_per_min_per_kg, protein_binding_pct, dose_in_study_mg, subject_n, demographics, citation_id, notes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (sid, normalise_route(r.get("route", "")), src,
             to_float(r.get("bioavailability_pct")), to_float(r.get("cmax_ng_per_ml")),
             to_float(r.get("tmax_min")), to_float(r.get("auc_0_inf_ng_h_per_ml")),
             to_float(r.get("half_life_min")), to_float(r.get("vd_l_per_kg")),
             to_float(r.get("clearance_ml_per_min_per_kg")), to_float(r.get("protein_binding_pct")),
             to_float(r.get("dose_in_study_mg")), to_int(r.get("subject_n")),
             r.get("subject_demographics") or r.get("demographics"),
             self.cite(r.get("reference")), r.get("notes")),
        )
        self.stats["pk_routes"] += 1

    def add_conc_effect(self, sid: int, source_slug: str, c: dict) -> None:
        if not isinstance(c, dict) or not c.get("effect"):
            return
        src = self.source_ids[source_slug]
        self.cur.execute(
            "INSERT INTO concentration_effects(substance_id, source_id, effect, concentration_unit, threshold, peak_effect, citation_id) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (sid, src, c.get("effect"), c.get("concentration_unit") or "ng/mL",
             to_float(c.get("threshold")), to_float(c.get("peak_effect")),
             self.cite(c.get("reference"))),
        )
        self.stats["concentration_effects"] += 1

    def add_metabolism(self, sid: int, source_slug: str, m: dict) -> None:
        if not isinstance(m, dict) or not m.get("enzyme"):
            return
        src = self.source_ids[source_slug]
        self.cur.execute(
            "INSERT INTO metabolism(substance_id, source_id, enzyme, fraction_of_clearance_pct, metabolite_name, metabolite_active, metabolite_potency_vs_parent_pct, citation_id, notes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (sid, src, m.get("enzyme"),
             to_float(m.get("fraction_of_clearance_pct")),
             m.get("metabolite_name"),
             1 if m.get("metabolite_active") else (0 if m.get("metabolite_active") is False else None),
             to_float(m.get("metabolite_potency_vs_parent_pct")),
             self.cite(m.get("reference")), m.get("notes")),
        )
        self.stats["metabolism"] += 1

    def add_ddi(self, sid: int, source_slug: str, d: dict) -> None:
        if not isinstance(d, dict) or not d.get("with"):
            return
        src = self.source_ids[source_slug]
        self.cur.execute(
            "INSERT INTO drug_interactions_pk(substance_id, with_substance, mechanism, ki_um, clinical_effect, source_id, citation_id) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (sid, d.get("with"), d.get("mechanism"), to_float(d.get("ki_um")),
             d.get("clinical_effect"), src, self.cite(d.get("reference"))),
        )
        self.stats["drug_interactions_pk"] += 1

    def add_pgx(self, sid: int, source_slug: str, gene: str, phenotype: str, citation: str | None = None) -> None:
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
            (sid, o.get("target"), to_float(o.get("ki_or_ic50_nm")),
             o.get("concern_level"), o.get("clinical_consequence"),
             src, self.cite(o.get("reference"))),
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
                (slug, name, ctx.get("shared_mechanism"), ctx.get("shared_pk_summary") or ctx.get("shared_pk"),
                 ctx.get("shared_safety"), ctx.get("sar_summary"), src),
            )
            cid = self.cur.lastrowid
        except sqlite3.IntegrityError:
            row = self.cur.execute("SELECT id FROM class_contexts WHERE slug = ?", (slug,)).fetchone()
            cid = row[0] if row else None
        if cid:
            for ref in (ctx.get("key_references") or []):
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

    def _ingest_substance_record(self, s: dict, slug: str, *,
                                  inchikey: str | None = None,
                                  pubchem_cid: int | None = None,
                                  cas: str | None = None) -> int | None:
        """Insert all facts from one BundledSubstance dict, attributing every
        row to the given source slug. Shared body for the merged-JSON and
        sourced-JSON ingesters.

        Records with chemistry-noise names ("(R)-...", "(+/-)-..." etc.) are
        skipped at the source — they're IUPAC artefacts, not substances anyone
        would log in a harm-reduction tracker.
        """
        if is_chemistry_noise(s.get("name") or ""):
            return None
        sid = self.upsert_substance(
            s.get("name"),
            aliases=s.get("aliases") or [],
            inchikey=inchikey, pubchem_cid=pubchem_cid, cas=cas,
            source_slug=slug,
        )
        if sid is None:
            return None
        if s.get("category"):
            self.add_category(sid, slug, s["category"])
        for tag in (s.get("tags") or []):
            self.add_tag(sid, slug, tag)
        for r in (s.get("routes") or []):
            if not isinstance(r, dict):
                continue
            doses = r.get("doses") or {}
            self.add_dose(sid, slug, r.get("route", ""), r.get("unit", "mg"),
                          threshold=doses.get("threshold"),
                          light=doses.get("light"),
                          common=doses.get("common"),
                          strong=doses.get("strong"),
                          heavy=doses.get("heavy"))
            if r.get("duration"):
                self.add_duration_profile(sid, slug, r.get("route", ""), r["duration"])
        if s.get("halfLifeMinutes") is not None:
            self.add_half_life(sid, slug, float(s["halfLifeMinutes"]))
        if s.get("mechanismOfAction"):
            moa = s["mechanismOfAction"]
            self.add_mechanism_summary(sid, slug, moa.get("summary") or moa.get("description") or "",
                                       description=moa.get("description"))
            for b in (moa.get("bindings") or []):
                self.add_binding(sid, slug, {
                    "target": b.get("target"),
                    "action": b.get("action") or "modulator",
                    "intrinsic_activity_pct": None,
                })
        for e in (s.get("effects") or []):
            self.add_effect(sid, slug, e)
        for se in (s.get("subjectiveEffects") or []):
            if isinstance(se, dict):
                self.add_subjective_effect(sid, slug, se.get("name"), se.get("description"))
            elif isinstance(se, str):
                self.add_subjective_effect(sid, slug, se)
        if s.get("toleranceInfo"):
            self.add_tolerance(sid, slug, s["toleranceInfo"])
        return sid

    def ingest_sourced_substances(self, path: Path) -> None:
        """SubstanceCollector's per-record sourced output. Each record carries
        its provenance (mapped 1:1 to sources.slug) so every fact gets
        attributed correctly without merge-time information loss.

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
        # skip the wikidata-only noise rows.
        non_wikidata_names: set[str] = set()
        for rec in data:
            substance = rec.get("substance")
            slug = rec.get("provenance")
            if isinstance(substance, dict) and slug and slug != "wikidata":
                name = (substance.get("name") or "").strip()
                if name:
                    non_wikidata_names.add(normalise(name))

        records = sorted(
            data,
            key=lambda r: (r.get("provenance", ""), (r.get("substance") or {}).get("name", "").lower()),
        )
        for rec in records:
            substance = rec.get("substance")
            slug = rec.get("provenance")
            if not isinstance(substance, dict) or not slug:
                continue
            if slug == "wikidata":
                name = (substance.get("name") or "").strip()
                if is_chemistry_noise(name) and normalise(name) not in non_wikidata_names:
                    continue
            if slug not in self.source_ids:
                slug = "piru-curated"
            self._ingest_substance_record(
                substance, slug,
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
            if s.get("psychoactive_class"):
                self.add_category(sid, slug, s["psychoactive_class"])
            elif s.get("categories"):
                cats = s["categories"]
                if cats:
                    self.add_category(sid, slug, cats[0] if isinstance(cats, list) else str(cats))
            if s.get("chemical_class"):
                self.add_tag(sid, slug, f"class:{s['chemical_class']}")
            dosages = (s.get("dosages") or {}).get("routes_of_administration") or []
            for r in dosages:
                dr = r.get("dose_ranges") or {}
                row_unit = r.get("units") or "mg"
                threshold = self._parse_dc_scalar(dr.get("threshold"), row_unit)
                light = self._parse_dc_range(dr.get("light"), row_unit)
                common = self._parse_dc_range(dr.get("common"), row_unit)
                strong = self._parse_dc_range(dr.get("strong"), row_unit)
                heavy = self._parse_dc_scalar(dr.get("heavy"), row_unit)
                self.add_dose(sid, slug, r.get("route", ""), row_unit,
                              threshold=threshold,
                              light=light, common=common, strong=strong,
                              heavy=heavy,
                              notes=r.get("notes"))
            for dc in (s.get("duration_curves") or []):
                curve = dc.get("duration_curve")
                if not isinstance(curve, dict):
                    continue
                route = (dc.get("method") or "oral").lower()
                profile = {}
                for k in ("onset", "peak", "offset", "after_effects", "total_duration"):
                    phase = curve.get(k)
                    if isinstance(phase, dict) and phase.get("min") is not None and phase.get("max") is not None:
                        # drug.community emits durations in hours; convert to minutes
                        profile[self._DC_PHASE_KEY.get(k, k)] = {"min": float(phase["min"]) * 60, "max": float(phase["max"]) * 60}
                if profile:
                    self.add_duration_profile(sid, slug, route, profile)
            for se in (s.get("subjective_effects") or []):
                if isinstance(se, str):
                    self.add_subjective_effect(sid, slug, se)

    # drug.community phase-key aliases: source key → profile dict key.
    _DC_PHASE_KEY = {"after_effects": "afterglow", "total_duration": "total"}

    # Unit-to-mg conversion factors. Anything not here keeps its row unit.
    _DC_UNIT_FACTORS = {
        "g": 1000.0, "mg": 1.0, "µg": 0.001, "ug": 0.001,
        "mcg": 0.001, "ng": 1e-6, "ml": 1.0, "l": 1000.0,
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

    @classmethod
    def _dc_unit_factor(cls, cleaned: str, row_unit: str) -> float:
        """If the value string contains an explicit unit that differs from the
        row's declared unit, return the conversion factor so the value can be
        rescaled into `row_unit`. Otherwise 1.0.

        drug.community occasionally switches units inside a single dose row
        (e.g. row unit "µg" but strong="1.0–1.5 mg"). Without this, the parser
        would record 1.0 µg where the source meant 1000 µg.
        """
        m = re.search(r"\d\s*(g|mg|µg|ug|mcg|ng|ml|l)\b", cleaned, re.IGNORECASE)
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
            ({"anticonvulsant", "antiepileptic", "mood-stabilizer", "mood-stabiliser"}, "Anticonvulsant"),
            ({"antipsychotic", "atypical-antipsychotic", "typical-antipsychotic"}, "Antipsychotic"),
            ({"antidepressant", "SSRI", "SNRI", "TCA", "MAOI", "NDRI", "SARI", "NaSSA"}, "Antidepressant"),
            ({"antihistamine", "H1-antagonist", "H2-antagonist", "deliriant"}, "Antihistamine"),
            ({"cannabinoid", "phytocannabinoid", "synthetic-cannabinoid", "semi-synthetic-cannabinoid", "CB1-agonist", "CB1-partial-agonist"}, "Cannabinoid"),
            ({"opioid", "mu-opioid-agonist", "designer-opioid", "nitazene", "fentanyl-class-potency"}, "Opioid"),
            ({"dissociative", "NMDA-antagonist"}, "Dissociative"),
            ({"benzodiazepine"}, "Benzodiazepine"),
            ({"eugeroic", "wakefulness-promoting"}, "Eugeroic"),
            ({"AMPAkine", "ampakine", "AMPA-PAM"}, "AMPAkine"),
            ({"nootropic", "racetam", "nootropic-peptide"}, "Nootropic"),
            ({"beta-blocker", "antihypertensive", "alpha2-agonist", "alpha1-blocker", "calcium-channel-blocker"}, "Cardiovascular"),
            ({"supplement", "vitamin", "mineral", "adaptogen", "amino-acid", "herbal"}, "Supplement"),
            ({"antiemetic"}, "Gastrointestinal"),
            ({"stimulant", "psychostimulant", "amphetamine", "cathinone-derivative"}, "Stimulant"),
            # Both `5HT2A-agonist` and `5-HT2A-agonist` (with hyphen) appear
            # depending on source — accept both. `tryptamine-not-phenethylamine`
            # is the peer-review-primary tag for classical tryptamine psychedelics.
            ({"psychedelic", "5HT2A-agonist", "5-HT2A-agonist",
              "phenethylamine-psychedelic", "tryptamine-not-phenethylamine",
              "psilocybe-mushroom", "DMT-containing",
              "PIHKAL", "TIHKAL"}, "Psychedelic"),
            ({"empathogen", "entactogen"}, "Empathogen"),
            ({"muscle-relaxant", "Z-drug", "orexin-antagonist", "sedative-hypnotic", "barbiturate"}, "Depressant"),
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
            sid = self.upsert_substance(name, aliases=rec.get("aliases_added") or [],
                                        inchikey=rec.get("inchikey"),
                                        pubchem_cid=to_int(rec.get("pubchem_cid")),
                                        cas=rec.get("cas"),
                                        iupac=rec.get("iupac_name"),
                                        smiles=rec.get("smiles"),
                                        source_slug=slug)
            if sid is None:
                continue
            for tag in (rec.get("tags_to_add") or []):
                self.add_tag(sid, slug, tag, confidence=rec.get("confidence"))
            pharm = rec.get("pharmacology") or {}
            for b in (pharm.get("binding") or []):
                self.add_binding(sid, slug, b)
            for f in (pharm.get("functional") or []):
                self.add_functional(sid, slug, f)
            for b in (pharm.get("biased_agonism") or []):
                self.add_biased(sid, slug, b)
            for o in (pharm.get("receptor_oligomerisation") or []):
                self.add_oligomer(sid, slug, o)
            if pharm.get("downstream_signalling"):
                self.add_downstream(sid, slug, pharm["downstream_signalling"])
            for n in (pharm.get("neuroimaging") or []):
                self.add_neuroimaging(sid, slug, n)
            human_pk = rec.get("human_pk") or {}
            for r in (human_pk.get("routes") or []):
                self.add_pk_route(sid, slug, r)
            for c in (human_pk.get("concentration_effect") or []):
                self.add_conc_effect(sid, slug, c)
            for m in (rec.get("metabolism") or []):
                self.add_metabolism(sid, slug, m)
            for d in (rec.get("drug_interactions_pk") or []):
                self.add_ddi(sid, slug, d)
            for o in (rec.get("off_targets") or []):
                self.add_off_target(sid, slug, o)
            pgx = rec.get("pharmacogenetics") or {}
            for gene in (pgx.get("relevant_genes") or []):
                self.add_pgx(sid, slug, gene, pgx.get("phenotype_effects") or "", citation=pgx.get("reference"))
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
                            (sid, src, None, " | ".join(summary_parts), self.cite(tol.get("reference"))),
                        )
                        self.stats["tolerance"] += 1
                    except sqlite3.IntegrityError:
                        pass
            cid_slug = rec.get("class_context_id")
            if cid_slug and cid_slug in class_ids:
                self.link_substance_class(sid, class_ids[cid_slug])

    # ---- manifest ----

    def finalise(self, content_version: str, generator_version: str, substance_count: int, sources_summary: dict) -> None:
        for k, v in [
            ("schema_version",    "1"),
            ("content_version",   content_version),
            ("generated_at",      datetime.now(timezone.utc).isoformat()),
            ("generator_version", generator_version),
            ("substance_count",   str(substance_count)),
        ]:
            self.cur.execute("INSERT INTO manifest(key, value) VALUES (?, ?)", (k, v))
        self.cur.execute("INSERT INTO manifest(key, value) VALUES (?, ?)", ("sources_summary", json.dumps(sources_summary, sort_keys=True)))


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

    if SOURCED.exists():
        build.ingest_sourced_substances(SOURCED)
        print(f"After sourced (per-record attribution): {build.stats}", file=sys.stderr)
    else:
        print(f"WARNING: {SOURCED} not found; falling back to merged JSON with piru-curated attribution.", file=sys.stderr)
        build.ingest_bundled_substances(BUNDLED)
        print(f"After bundled (fallback): {build.stats}", file=sys.stderr)

    build.ingest_drug_community(DRUG_COMMUNITY)
    print(f"After drug.community: {build.stats}", file=sys.stderr)

    for f in sorted(ENRICHMENT_DIR.glob("*.json")):
        before = dict(build.stats)
        build.ingest_enrichment(f)
        delta = {k: build.stats[k] - before.get(k, 0) for k in build.stats if build.stats[k] != before.get(k, 0)}
        print(f"  + {f.name}: {delta}", file=sys.stderr)

    # Tag-fallback pass: any substance currently in (or resolving to) "Other"
    # whose tags identify a specific class gets an additional piru-curated
    # category row so it leaves the Other bucket. Peptide is the load-bearing
    # case (28+ entries the agents tagged as 'peptide' but with category=Other).
    promoted = build.promote_via_tags()
    print(f"Tag-fallback promotion: {promoted}", file=sys.stderr)

    substance_count = db.execute("SELECT COUNT(*) FROM substances").fetchone()[0]
    content_version = datetime.now(timezone.utc).strftime("%Y-%m-%d.0")
    sources_summary = {
        slug: {
            "dose_ranges": db.execute("SELECT COUNT(*) FROM dose_ranges WHERE source_id = (SELECT id FROM sources WHERE slug = ?)", (slug,)).fetchone()[0],
            "bindings":    db.execute("SELECT COUNT(*) FROM bindings    WHERE source_id = (SELECT id FROM sources WHERE slug = ?)", (slug,)).fetchone()[0],
            "categories":  db.execute("SELECT COUNT(*) FROM categories  WHERE source_id = (SELECT id FROM sources WHERE slug = ?)", (slug,)).fetchone()[0],
        }
        for slug, *_ in SOURCES
    }
    build.finalise(content_version, "build-sqlite-database.py 0.1.0", substance_count, sources_summary)
    db.commit()

    # Vacuum + analyze for deterministic, optimised output
    db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
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
        "schema_version": 1,
        "content_version": content_version,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "generator_version": "build-sqlite-database.py 0.1.0",
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
        f"# Piru SQLite build report",
        f"",
        f"Built {content_version} → `{OUT_SQLITE}` ({size:,} bytes, sha256 `{sha}`)",
        f"",
        f"## Row counts",
        f"",
        f"| Table | Rows |",
        f"|---|---|",
    ]
    tables = [
        "substances", "aliases", "sources", "citations", "categories", "tags",
        "dose_ranges", "durations", "half_lives", "mechanisms_summary",
        "effects", "subjective_effects", "tolerance",
        "bindings", "functional_assays", "biased_agonism", "receptor_oligomers",
        "downstream_signalling", "neuroimaging",
        "pk_routes", "concentration_effects", "metabolism", "drug_interactions_pk",
        "pharmacogenetics", "off_targets",
        "class_contexts", "substance_classes",
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

    print(f"\nDone:", file=sys.stderr)
    print(f"  {OUT_SQLITE}     ({size:,} bytes, sha256 {sha[:16]}...)", file=sys.stderr)
    print(f"  {OUT_MANIFEST}", file=sys.stderr)
    print(f"  {OUT_REPORT}", file=sys.stderr)
    print(f"  {substance_count:,} substances", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
