# Known Limitations — `feat/multi-source-substance-db`

Documented gaps the branch ships with. None of these block merge or harm
users; they're listed so future work has a clear backlog and so verification
agents understand the scope of the source-attribution claim.

## Citation density is uneven across tables

Per-row citation IDs are populated for **bindings only** (PDSP / primary
literature). The other fact tables (`dose_ranges`, `durations`, `categories`,
`half_lives`, `mechanisms_summary`) carry a `source_id` so the user can see
*which* source contributed a fact, but not a specific PMID/DOI for the fact
itself — the source slug is "tripsit" or "drug.community" not
"https://doi.org/...".

**Implication for verification agents:** binding rows can be checked against
primary literature directly (PMID → PubMed → assay conditions). Non-binding
rows require checking the *source's* dataset (e.g. TripSit's factsheet) at
the time of the build to confirm the value the build script imported. The
manifest's `generated_at` timestamp anchors which snapshot to verify against.

**Path to fix:** add `citation_id` populations in the Python build script
for non-binding tables when the source provides a versioned URL or commit
hash. TripSit's GitHub repo has commit-pinned files; DailyMed has SPL
revision IDs.

## `interaction_rules` table is empty

The bundled SQLite ships an `interaction_rules` table per the schema, but no
rows have been populated. The Swift-side `InteractionChecker` falls back to
in-code class-pair rules in `Piru/Data/Interactions.swift`. Both the TripSit
combo-data path and the parsed-FDA-label path were removed when their
runtime API fetches went away with the SQLite migration.

**Implication:** users see warnings for the curated class-pair rules
(opioid+benzo, MAOI+SSRI, etc.) but no substance-pair-specific warnings from
TripSit combos.

**Path to fix:** extend `Exports/build-sqlite-database.py` to ingest the
TripSit combo matrix into `interaction_rules`, then add a SQLite-backed
fallback layer in `InteractionChecker.check(_:against:)`.

## `HalfLifeDatabase` and `MechanismOfActionDatabase` are still load-bearing

The bundled SQLite has half-life data for ~46 substances (peer-reviewed
literature only) and 0 rows in `mechanisms_summary`. The Swift-side
in-code databases (`HalfLifeDatabase` with ~1,100 entries,
`MechanismOfActionDatabase` with category-level fallbacks) are the only
source for the vast majority of substances. Removing them would break the
half-life calculator, PK timeline, recovery guide, and mechanism summary on
the detail view.

**Implication:** these aren't dead code despite the SQLite migration —
they're the fallback layer. Code paths in `ActiveSubstanceCalculator`,
`PDFReportGenerator`, `InteractionTimelineView`, `HalfLifeCalculatorView`,
`DoseSuggestionCard`, and `SubstanceLibraryView` all consult them.

**Path to fix:** migrate the in-code data into the SQLite (per-substance
`half_lives` rows, per-substance `mechanisms_summary` rows). Once the SQLite
has full coverage, the Swift databases can be deleted and the call sites
updated to read from `Substance.halfLifeMinutes` / `Substance.mechanismOfAction`
exclusively.

## Combo machinery deleted, not migrated

The `loadTripSitCombos` + `comboLookup` machinery in `InteractionChecker` was
deleted because it was dormant at runtime (the network API that fed it was
removed earlier). The plan was to back the combo lookup with SQLite —
deferred to the same `interaction_rules` migration above.

## Tests not covering the full download/install path

`SubstanceDBUpdaterTests` covers:
- Manifest Codable round-trip + version comparison
- URL arithmetic (`sqliteURL(manifestURL:manifest:)`)
- SHA-256 known vectors + bundled-hash matches bundled-manifest
- `revertToBundled` file cleanup
- `SubstanceStore.resolveSubstancesDBURL` preference logic

NOT covered:
- The actual `URLSession.download` call (would require network mocking)
- `fetchRemoteManifest` HTTP error paths
- `installDownloadedDB` atomicity under crash conditions
- Schema-version rejection of a future manifest

These are integration-test territory; the unit-level coverage that exists is
the safety-critical math (URL construction, hash computation, file-resolution
order).

## Update mechanism's hardcoded manifest URL

`SubstanceDBUpdater.manifestURL` falls back to
`https://raw.githubusercontent.com/kageroumado/piru/main/Piru/Data/manifest.json`.
This URL doesn't exist until the branch is merged to `main` and the file
becomes reachable via GitHub's raw mirror.

**First-launch update checks will land in `.error` state until the merge
lands.** Acceptable for an unmerged branch; worth verifying on the day of
merge that the URL serves a valid manifest.

Override via Info.plist key `PiruManifestURL` for staging or forks.
