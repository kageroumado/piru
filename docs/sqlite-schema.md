# Piru Substance Database — SQLite Schema

This is the schema for the **bundled, read-only** substance database that ships with the Piru app, plus the **user-writable preferences** database that lives alongside it. The bundled DB carries every datum with explicit source attribution so the display layer can resolve values according to user-controlled priority.

## Two databases

| | Bundled (read-only) | User (writable) |
|---|---|---|
| Path | `Bundle.main/piru-substances.sqlite` | `Documents/piru-user-prefs.sqlite` |
| Lifetime | Replaced atomically on opt-in update | Persists across updates |
| Contents | Every fact, every source | Source priority, profile, field overrides |
| Migration | Schema is forward-additive (new tables/columns OK; never reshape existing) | Same |

## Design principles

1. **Source attribution is first-class.** Every fact-bearing row carries a `source_id`. Display layer joins through `source_preferences` to find the highest-priority enabled source.
2. **One source can disagree with another.** TripSit might say `heavy = 100 mg` while PsychonautWiki says `heavy = 150 mg`. Both rows exist. The user picks who they trust via priority.
3. **References are central.** A `references` table stores DOI/PMID/URL once; every binding constant or PK number points back via `reference_id`. No string duplication.
4. **Advanced search is indexed-SQL native.** Indexes on `(target, ki_nm)`, `(tag)`, `(category)`, `(substance_id, target)` make filter-by-binding-constant a single fast query.
5. **Class context is deduplicated.** "All arylcyclohexylamines share these properties" lives once and many substances link to it via `substance_classes`.
6. **No nullable cascade.** Tables don't FK-cascade on delete because the bundled DB never deletes — it replaces wholesale via atomic file swap.

---

## Core entity tables

```sql
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
    molecular_weight REAL,
    -- Physicochemical / forensic properties (schema v5, Workstream 1). NULL =
    -- unknown. Predicted/computed (logP/pKa often PubChem XLogP) or rodent-assay
    -- (LD50) — NOT clinical; the app badges them forensic and never as a "safe
    -- dose". Columns added in Stage 0; extractors populate them in Stage 1.
    logp                  REAL,    -- octanol/water partition coefficient
    logd                  REAL,    -- distribution coefficient at physiological pH
    pka                   REAL,    -- acid dissociation constant (primary)
    tpsa                  REAL,    -- topological polar surface area (Å²)
    hba                   INTEGER, -- H-bond acceptor count
    hbd                   INTEGER, -- H-bond donor count
    ld50_oral_mg_per_kg   REAL,    -- rodent oral LD50 (order-of-magnitude)
    ld50_dermal_mg_per_kg REAL,    -- rodent dermal LD50 (order-of-magnitude)
    melting_point_c       REAL,    -- melting point (°C)
    boiling_point_c       REAL     -- boiling point (°C)
);
CREATE INDEX idx_substances_normalized   ON substances(normalized_name);
CREATE INDEX idx_substances_inchikey     ON substances(inchikey) WHERE inchikey IS NOT NULL;
CREATE INDEX idx_substances_pubchem_cid  ON substances(pubchem_cid) WHERE pubchem_cid IS NOT NULL;
CREATE INDEX idx_substances_cas          ON substances(cas) WHERE cas IS NOT NULL;

CREATE TABLE aliases (
    substance_id     INTEGER NOT NULL REFERENCES substances(id),
    alias            TEXT NOT NULL,
    alias_normalized TEXT NOT NULL,
    source_id        INTEGER REFERENCES sources(id),
    PRIMARY KEY (substance_id, alias)
);
CREATE INDEX idx_aliases_normalized ON aliases(alias_normalized);
```

## Source registry

```sql
CREATE TABLE sources (
    id                INTEGER PRIMARY KEY,
    slug              TEXT NOT NULL UNIQUE,         -- 'psychonautwiki', 'tripsit', 'piru-curated'
    display_name      TEXT NOT NULL,                 -- 'PsychonautWiki', 'TripSit factsheets'
    description       TEXT,
    homepage_url      TEXT,
    default_priority  INTEGER NOT NULL,              -- 1 = highest. App seeds user prefs from this.
    default_enabled   INTEGER NOT NULL DEFAULT 1,
    last_retrieved_at TEXT                            -- ISO8601 when the build pulled this source
);
```

Seeded sources (default priority order):

| priority | slug | display |
|---|---|---|
| 1 | `piru-curated` | Piru hand-curated overlay |
| 2 | `peer-review-primary` | Primary peer-reviewed literature (PubMed) |
| 3 | `psychonautwiki` | PsychonautWiki |
| 4 | `tripsit` | TripSit factsheets |
| 5 | `drug.community` | drug.community |
| 6 | `dailymed` | FDA DailyMed prescribing labels |
| 7 | `erowid-pihkal` | Erowid PIHKAL Part 2 |
| 8 | `erowid-tihkal` | Erowid TIHKAL Part 2 |
| 9 | `pdsp` | UNC PDSP Ki database |
| 10 | `pubchem` | PubChem |
| 11 | `wikidata` | Wikidata |
| 12 | `dea-orange-book` | DEA Orange Book (scheduling only) |

## Classification (per-source)

```sql
CREATE TABLE categories (
    substance_id INTEGER NOT NULL REFERENCES substances(id),
    source_id    INTEGER NOT NULL REFERENCES sources(id),
    category     TEXT NOT NULL,    -- 'Stimulant', 'Psychedelic', 'Dysdelic', etc.
    confidence   TEXT,             -- 'high' | 'medium' | 'low'
    PRIMARY KEY (substance_id, source_id)
);
CREATE INDEX idx_categories_category ON categories(category);

CREATE TABLE tags (
    substance_id INTEGER NOT NULL REFERENCES substances(id),
    tag          TEXT NOT NULL,    -- 'cathinone', 'DAT-inhibitor', 'no-human-data', etc.
    source_id    INTEGER NOT NULL REFERENCES sources(id),
    confidence   TEXT,
    PRIMARY KEY (substance_id, tag, source_id)
);
CREATE INDEX idx_tags_tag      ON tags(tag);
CREATE INDEX idx_tags_substance ON tags(substance_id);
```

## Dose and duration (per substance × route × source)

```sql
CREATE TABLE dose_ranges (
    id            INTEGER PRIMARY KEY,
    substance_id  INTEGER NOT NULL REFERENCES substances(id),
    route         TEXT NOT NULL,        -- 'oral', 'insufflation', 'inhalation', ...
    source_id     INTEGER NOT NULL REFERENCES sources(id),
    unit          TEXT NOT NULL,        -- 'mg', 'µg', 'g', 'mL', 'IU'
    threshold     REAL,
    light_lower   REAL,
    light_upper   REAL,
    common_lower  REAL,
    common_upper  REAL,
    strong_lower  REAL,
    strong_upper  REAL,
    heavy         REAL,
    notes         TEXT,
    reference_id  INTEGER REFERENCES references(id),
    UNIQUE (substance_id, route, source_id)
);
CREATE INDEX idx_dose_substance_route ON dose_ranges(substance_id, route);

CREATE TABLE durations (
    id           INTEGER PRIMARY KEY,
    substance_id INTEGER NOT NULL REFERENCES substances(id),
    route        TEXT NOT NULL,
    source_id    INTEGER NOT NULL REFERENCES sources(id),
    phase        TEXT NOT NULL,   -- 'onset', 'comeup', 'peak', 'offset', 'afterglow', 'total'
    min_minutes  REAL NOT NULL,
    max_minutes  REAL NOT NULL,
    reference_id INTEGER REFERENCES references(id),
    UNIQUE (substance_id, route, source_id, phase)
);
CREATE INDEX idx_durations_substance_route ON durations(substance_id, route);
```

## Basic pharmacology (per-source)

```sql
CREATE TABLE half_lives (
    substance_id     INTEGER NOT NULL REFERENCES substances(id),
    source_id        INTEGER NOT NULL REFERENCES sources(id),
    half_life_minutes REAL NOT NULL,
    notes            TEXT,
    reference_id     INTEGER REFERENCES references(id),
    PRIMARY KEY (substance_id, source_id)
);

CREATE TABLE mechanisms_summary (
    substance_id INTEGER NOT NULL REFERENCES substances(id),
    source_id    INTEGER NOT NULL REFERENCES sources(id),
    summary      TEXT NOT NULL,        -- one-sentence
    description  TEXT,                  -- 2-4 sentences
    reference_id INTEGER REFERENCES references(id),
    PRIMARY KEY (substance_id, source_id)
);
```

## Effects and tolerance

```sql
-- Controlled effect vocabulary (schema v5, localization Track 1). One canonical
-- effect per concept, translated once, referenced by effects.vocab_id — so a zh
-- user sees localized effects even on English-only-source substances. Kept as
-- DATA (not a Swift enum) so adding an effect ships in the DB. Tables added in
-- Stage 0 (empty); seeded from the PW SEI + FreeODwiki 药效 in Stage 2.
CREATE TABLE effect_vocab (
    vocab_id  TEXT PRIMARY KEY,         -- stable slug, e.g. 'anxiety'
    category  TEXT                      -- PsychonautWiki/SEI grouping
);
CREATE TABLE effect_vocab_labels (
    vocab_id           TEXT NOT NULL REFERENCES effect_vocab(vocab_id),
    language           TEXT NOT NULL,   -- 'en' | 'zh-Hans' | 'zh-Hant' | 'und'
    label              TEXT NOT NULL,
    machine_translated INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (vocab_id, language)
);

CREATE TABLE effects (
    id           INTEGER PRIMARY KEY,
    substance_id INTEGER NOT NULL REFERENCES substances(id),
    source_id    INTEGER NOT NULL REFERENCES sources(id),
    text         TEXT NOT NULL,
    kind         TEXT,                  -- 'positive' | 'neutral' | 'negative' | 'warning'
    -- Canonical-vocabulary reference (schema v5). NULL when no fuzzy match
    -- clears threshold; `text` is the raw fallback. Populated in Stage 2.
    vocab_id     TEXT REFERENCES effect_vocab(vocab_id),
    reference_id INTEGER REFERENCES references(id)
);
CREATE INDEX idx_effects_substance ON effects(substance_id);
CREATE INDEX idx_effects_vocab     ON effects(vocab_id) WHERE vocab_id IS NOT NULL;

CREATE TABLE subjective_effects (
    id           INTEGER PRIMARY KEY,
    substance_id INTEGER NOT NULL REFERENCES substances(id),
    source_id    INTEGER NOT NULL REFERENCES sources(id),
    name         TEXT NOT NULL,
    description  TEXT,
    reference_id INTEGER REFERENCES references(id)
);

CREATE TABLE tolerance (
    substance_id    INTEGER NOT NULL REFERENCES substances(id),
    source_id       INTEGER NOT NULL REFERENCES sources(id),
    half_life_days  REAL,
    full_reset_days REAL,
    build_rate      TEXT,               -- 'rapid' | 'moderate' | 'slow'
    notes           TEXT,
    reference_id    INTEGER REFERENCES references(id),
    PRIMARY KEY (substance_id, source_id)
);
```

## Deep pharmacology — receptor binding

```sql
CREATE TABLE bindings (
    id                   INTEGER PRIMARY KEY,
    substance_id         INTEGER NOT NULL REFERENCES substances(id),
    target               TEXT NOT NULL,        -- '5-HT2A', 'DAT', 'NMDA', 'μ-opioid', ...
    action               TEXT NOT NULL,        -- 'agonist' | 'partialAgonist' | 'antagonist' | 'inverseAgonist' | 'positiveAllostericModulator' | 'negativeAllostericModulator' | 'reuptakeInhibitor' | 'releasingAgent' | 'enzymeInhibitor' | 'channelBlocker' | 'modulator'
    ki_nm                REAL,
    ki_ci_lower_nm       REAL,
    ki_ci_upper_nm       REAL,
    kd_nm                REAL,
    ec50_nm              REAL,
    ic50_nm              REAL,
    emax_pct             REAL,
    intrinsic_activity_pct REAL,
    reference_agonist    TEXT,                  -- '5-HT', 'DAMGO', 'DOI'
    species              TEXT,                  -- 'human' | 'rat' | 'mouse' | 'rhesus' | 'other'
    tissue_or_cell       TEXT,                  -- 'HEK293 stably expressing human 5-HT2A'
    radioligand          TEXT,                  -- '[3H]-ketanserin'
    assay_notes          TEXT,
    source_id            INTEGER NOT NULL REFERENCES sources(id),
    reference_id         INTEGER REFERENCES references(id),
    is_review            INTEGER DEFAULT 0,
    notes                TEXT
);
CREATE INDEX idx_bindings_target            ON bindings(target);
CREATE INDEX idx_bindings_target_ki         ON bindings(target, ki_nm);
CREATE INDEX idx_bindings_substance_target  ON bindings(substance_id, target);
CREATE INDEX idx_bindings_substance         ON bindings(substance_id);

CREATE TABLE functional_assays (
    id                INTEGER PRIMARY KEY,
    substance_id      INTEGER NOT NULL REFERENCES substances(id),
    target            TEXT NOT NULL,
    readout           TEXT NOT NULL,         -- 'PIP2 hydrolysis' | 'cAMP' | 'β-arrestin recruitment' | 'ERK1/2' | 'GTPγS' | 'calcium flux' | 'electrophysiology'
    ec50_nm           REAL,
    ic50_nm           REAL,
    emax_pct          REAL,
    reference_agonist TEXT,
    species           TEXT,
    cell_system       TEXT,
    source_id         INTEGER NOT NULL REFERENCES sources(id),
    reference_id      INTEGER REFERENCES references(id),
    notes             TEXT
);
CREATE INDEX idx_functional_target       ON functional_assays(target);
CREATE INDEX idx_functional_substance    ON functional_assays(substance_id);

CREATE TABLE biased_agonism (
    id                       INTEGER PRIMARY KEY,
    substance_id             INTEGER NOT NULL REFERENCES substances(id),
    target                   TEXT NOT NULL,
    pathways_compared        TEXT NOT NULL,        -- 'Gαq,β-arrestin-2'  (comma-joined for query simplicity)
    bias_factor_log          REAL,
    bias_reference_compound  TEXT,
    interpretation           TEXT,
    source_id                INTEGER NOT NULL REFERENCES sources(id),
    reference_id             INTEGER REFERENCES references(id)
);
CREATE INDEX idx_biased_target    ON biased_agonism(target);
CREATE INDEX idx_biased_substance ON biased_agonism(substance_id);

CREATE TABLE receptor_oligomers (
    id                      INTEGER PRIMARY KEY,
    substance_id            INTEGER NOT NULL REFERENCES substances(id),
    complex_description     TEXT NOT NULL,        -- '5-HT2A/mGluR2 heteromer'
    evidence_type           TEXT,                 -- 'BRET' | 'FRET' | 'coIP' | 'proximity ligation'
    functional_consequence  TEXT,
    source_id               INTEGER NOT NULL REFERENCES sources(id),
    reference_id            INTEGER REFERENCES references(id)
);

CREATE TABLE downstream_signalling (
    substance_id INTEGER NOT NULL REFERENCES substances(id),
    source_id    INTEGER NOT NULL REFERENCES sources(id),
    summary      TEXT NOT NULL,
    reference_id INTEGER REFERENCES references(id),
    PRIMARY KEY (substance_id, source_id)
);

CREATE TABLE neuroimaging (
    id            INTEGER PRIMARY KEY,
    substance_id  INTEGER NOT NULL REFERENCES substances(id),
    modality      TEXT NOT NULL,        -- 'fMRI BOLD' | 'EEG' | 'MEG' | 'PET' | 'SPECT'
    finding       TEXT NOT NULL,
    source_id     INTEGER NOT NULL REFERENCES sources(id),
    reference_id  INTEGER REFERENCES references(id)
);
```

## Human pharmacokinetics

```sql
CREATE TABLE pk_routes (
    id                       INTEGER PRIMARY KEY,
    substance_id             INTEGER NOT NULL REFERENCES substances(id),
    route                    TEXT NOT NULL,
    source_id                INTEGER NOT NULL REFERENCES sources(id),
    bioavailability_pct      REAL,
    cmax_ng_per_ml           REAL,
    tmax_min                 REAL,
    auc_0_inf_ng_h_per_ml    REAL,
    half_life_min            REAL,
    vd_l_per_kg              REAL,
    clearance_ml_per_min_per_kg REAL,
    protein_binding_pct      REAL,
    dose_in_study_mg         REAL,
    subject_n                INTEGER,
    demographics             TEXT,
    reference_id             INTEGER REFERENCES references(id),
    notes                    TEXT
);
CREATE INDEX idx_pk_substance_route ON pk_routes(substance_id, route);

CREATE TABLE concentration_effects (
    id                  INTEGER PRIMARY KEY,
    substance_id        INTEGER NOT NULL REFERENCES substances(id),
    source_id           INTEGER NOT NULL REFERENCES sources(id),
    effect              TEXT NOT NULL,    -- 'subjective intensity 0-10' | 'systolic BP' | 'HR' | 'EEG alpha' | 'pupil diameter'
    concentration_unit  TEXT NOT NULL,    -- 'ng/mL' | 'nM' | 'µM'
    threshold           REAL,
    peak_effect         REAL,
    reference_id        INTEGER REFERENCES references(id)
);

CREATE TABLE metabolism (
    id                              INTEGER PRIMARY KEY,
    substance_id                    INTEGER NOT NULL REFERENCES substances(id),
    source_id                       INTEGER NOT NULL REFERENCES sources(id),
    enzyme                          TEXT NOT NULL,        -- 'CYP3A4' | 'CYP2D6' | 'UGT2B7' | 'CES1A1'
    fraction_of_clearance_pct       REAL,
    metabolite_name                 TEXT,
    metabolite_active               INTEGER,
    metabolite_potency_vs_parent_pct REAL,
    reference_id                    INTEGER REFERENCES references(id),
    notes                           TEXT
);
CREATE INDEX idx_metabolism_enzyme    ON metabolism(enzyme);
CREATE INDEX idx_metabolism_substance ON metabolism(substance_id);

CREATE TABLE drug_interactions_pk (
    id                INTEGER PRIMARY KEY,
    substance_id      INTEGER NOT NULL REFERENCES substances(id),
    with_substance    TEXT NOT NULL,        -- free text: 'fluoxetine', 'grapefruit', 'itraconazole'
    mechanism         TEXT,                  -- 'CYP3A4 inhibition' | 'CYP2D6 inhibition' | 'OATP inhibition' | 'UGT inhibition'
    ki_um             REAL,
    clinical_effect   TEXT,
    source_id         INTEGER NOT NULL REFERENCES sources(id),
    reference_id      INTEGER REFERENCES references(id)
);

CREATE TABLE pharmacogenetics (
    id                 INTEGER PRIMARY KEY,
    substance_id       INTEGER NOT NULL REFERENCES substances(id),
    gene               TEXT NOT NULL,    -- 'CYP2D6' | 'OPRM1' | 'COMT' | '5-HTTLPR' | 'HLA-B*15:02'
    phenotype_effects  TEXT NOT NULL,
    source_id          INTEGER NOT NULL REFERENCES sources(id),
    reference_id       INTEGER REFERENCES references(id)
);
CREATE INDEX idx_pgx_gene ON pharmacogenetics(gene);

CREATE TABLE off_targets (
    id                    INTEGER PRIMARY KEY,
    substance_id          INTEGER NOT NULL REFERENCES substances(id),
    target                TEXT NOT NULL,    -- 'hERG' | 'σ1' | 'TAAR1' | 'NET'
    ki_or_ic50_nm         REAL,
    concern_level         TEXT,             -- 'low' | 'moderate' | 'high'
    clinical_consequence  TEXT,
    source_id             INTEGER NOT NULL REFERENCES sources(id),
    reference_id          INTEGER REFERENCES references(id)
);
CREATE INDEX idx_offtargets_target ON off_targets(target);
```

## Class context

```sql
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

CREATE TABLE class_references (
    class_context_id INTEGER NOT NULL REFERENCES class_contexts(id),
    reference_id     INTEGER NOT NULL REFERENCES references(id),
    PRIMARY KEY (class_context_id, reference_id)
);
```

## Class-level interaction rules

```sql
CREATE TABLE interaction_rules (
    id            INTEGER PRIMARY KEY,
    class_a       TEXT NOT NULL,        -- 'opioid', 'benzodiazepine', 'stimulant', ...
    class_b       TEXT NOT NULL,
    severity      TEXT NOT NULL,        -- 'low' | 'caution' | 'unsafe' | 'dangerous'
    note          TEXT NOT NULL,
    source_id     INTEGER REFERENCES sources(id),
    reference_id  INTEGER REFERENCES references(id),
    UNIQUE (class_a, class_b)            -- normalised so (a, b) is alphabetical
);
```

## References (central)

```sql
CREATE TABLE references (
    id        INTEGER PRIMARY KEY,
    doi       TEXT,
    pmid      INTEGER,
    url       TEXT,
    title     TEXT,
    year      INTEGER,
    authors   TEXT,
    is_review INTEGER DEFAULT 0
);
CREATE INDEX idx_references_doi  ON references(doi)  WHERE doi  IS NOT NULL;
CREATE INDEX idx_references_pmid ON references(pmid) WHERE pmid IS NOT NULL;
```

## Manifest

```sql
CREATE TABLE manifest (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
-- Rows seeded by the build tool:
--   ('schema_version',     '5')          -- v5: physicochemical cols + effect_vocab
--   ('content_version',    '2026-05-25.0')         -- semver-like; bumped per build
--   ('generator_version',  'SubstanceCollector 0.1.0')
--   ('build_timestamp',    '2026-05-25T15:00:00Z')
--   ('substance_count',    '1614')
```

---

## User-writable preferences DB

Separate file at `Documents/piru-user-prefs.sqlite`. Survives bundled-DB updates.

```sql
CREATE TABLE source_preferences (
    source_slug TEXT PRIMARY KEY,    -- matches sources.slug from bundled DB
    priority    INTEGER NOT NULL,    -- 1 = highest; user-controlled, re-orderable
    enabled     INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE user_profile (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
-- Rows:
--   ('expansion_level', 'casual' | 'harm_reduction' | 'pharma_nerd')
--   ('seen_update_v',   '2026-05-25.0')   -- last content version user dismissed update banner for

CREATE TABLE field_overrides (
    id              INTEGER PRIMARY KEY,
    substance_name  TEXT NOT NULL,    -- by name, not id; survives substance_id changes across updates
    field_path      TEXT NOT NULL,    -- 'dose_ranges.insufflation.heavy' | 'half_lives' | etc.
    override_value  TEXT NOT NULL,    -- JSON
    note            TEXT,
    created_at      TEXT NOT NULL
);
CREATE INDEX idx_overrides_substance ON field_overrides(substance_name);
```

---

## Display layer query pattern

For "give me the dose ladder for ketamine insufflation," the app runs:

```sql
SELECT d.*
FROM dose_ranges d
JOIN substances s        ON s.id = d.substance_id
JOIN source_preferences p ON p.source_slug = (SELECT slug FROM sources WHERE id = d.source_id)
WHERE s.canonical_name = :name
  AND d.route          = :route
  AND p.enabled = 1
ORDER BY p.priority ASC
LIMIT 1;
```

`source_preferences` lives in the user DB, attached via `ATTACH DATABASE 'piru-user-prefs.sqlite' AS user;`. The query is a single indexed lookup → ~ms.

## Advanced search query pattern

For "find every compound with Ki < 100 nM at 5-HT2C from peer-reviewed sources":

```sql
SELECT s.canonical_name, b.ki_nm, b.species, r.doi
FROM bindings b
JOIN substances s ON s.id = b.substance_id
JOIN sources    src ON src.id = b.source_id
LEFT JOIN references r ON r.id = b.reference_id
WHERE b.target = '5-HT2C'
  AND b.ki_nm  < 100
  AND src.slug IN ('peer-review-primary', 'pdsp')
ORDER BY b.ki_nm ASC;
```

Backed by `idx_bindings_target_ki` — also ~ms even at 100k+ binding rows.

## Compare-across-class query pattern

For "compare cathinone DAT EC50s":

```sql
SELECT s.canonical_name, f.ec50_nm, f.species
FROM functional_assays f
JOIN substances s     ON s.id = f.substance_id
JOIN tags t           ON t.substance_id = s.id
WHERE f.target = 'DAT'
  AND f.readout = 'reuptake-inhibition'
  AND t.tag    = 'cathinone'
ORDER BY f.ec50_nm ASC;
```

---

## Update manifest format

Lives at the repo root as `Piru/Data/manifest.json` so any iOS client can fetch via:

```
https://raw.githubusercontent.com/<owner>/piru/main/Piru/Data/manifest.json
```

Schema:

```json
{
  "schema_version": 5,
  "content_version": "2026-05-25.0",
  "generated_at": "2026-05-25T15:00:00Z",
  "generator_version": "SubstanceCollector 0.1.0",
  "substance_count": 1614,
  "sources": {
    "tripsit":          { "snapshot_at": "2026-05-24T00:00:00Z", "row_count": 554 },
    "psychonautwiki":   { "snapshot_at": "2026-05-22T00:00:00Z", "row_count": 612 },
    "piru-curated":     { "version": "2026-05-25.0",             "row_count": 271 },
    "drug.community":   { "snapshot_at": "2026-05-25T00:00:00Z", "row_count": 422 }
  },
  "sqlite_url":  "https://raw.githubusercontent.com/<owner>/piru/main/Piru/Data/piru-substances.sqlite",
  "sqlite_sha256": "abc123...",
  "sqlite_size_bytes": 9876543,
  "release_notes": "Added 12 new nitazenes, updated ketamine PK from Holze 2024, fixed BTCP tag (DAT not NMDA)."
}
```

Client logic on cold launch:
1. Fetch manifest. If network fails → stop, use bundled.
2. Compare `content_version` to `manifest.content_version` row in bundled DB.
3. If remote newer AND user hasn't dismissed this version → show banner with `release_notes`.
4. User taps → download `sqlite_url` to `Documents/piru-substances-pending.sqlite`, verify sha256, atomic rename to `piru-substances.sqlite`. On next launch, the app prefers `Documents/` over bundled.
5. `user-prefs.sqlite` never touched.

---

## Schema migration policy

- **Forward additive only.** New tables and new nullable columns are safe. Never reshape an existing column or rename. Existing user-prefs survives.
- **`schema_version` bump rules:**
  - Bumped on any structural change.
  - Client checks `schema_version` before merging an update. If remote schema_version > client schema_version → block update, prompt user to update the app from App Store.
  - This means schema bumps need to land in an app release before content updates that rely on them.
- **References table is append-only**, ids never re-used. Override JSON can safely cite reference ids across DB updates.
