# Changelog

## 2.0 — pending TestFlight

### TL;DR for testers

This is the largest update since launch. The substance library now ships as a
bundled, multi-source database with ~1,800 entries instead of fetching at
launch — the app starts instantly, the Library tab is responsive, and you can
choose which sources to trust. Two new categories (**Peptide**,
**Anticonvulsant**) plus 218 newly-curated substances (antipsychotics, the
common cannabinoids, GLP-1 agonists, classical antidepressants, the supplements
nootropic users actually take, the top US prescription drugs that are
psychoactive). Fixes the build-11 colour-picker crash and several silent data
bugs that mis-categorised classical psychedelics, beta-blockers, and
gabapentinoids.

### Added

- **Multi-source substance database, bundled in the app.** ~1,800 substances
  with per-field source attribution. Sources include TripSit, drug.community,
  PsychonautWiki, Wikidata + PubChem, Erowid (PIHKAL/TIHKAL), peer-reviewed
  pharmacology references, and a hand-curated overlay. Every dose, duration,
  half-life, mechanism, and category row records which source it came from.
- **User-controllable source priority** (Settings → Sources). Reorder the
  sources you trust most; the app resolves conflicting facts in your chosen
  order. Disable a source entirely if you don't want its data.
- **User profile tiers**: Casual / Harm Reduction / Pharma Nerd. Each tier
  changes how much of the substance detail screen you see — mechanism summary,
  binding constants, biased agonism, and primary-literature receptor data are
  progressively disclosed.
- **Advanced search** for pharma nerds: query receptor bindings by target,
  affinity (Ki ≤ X nM), and substance-name fragment.
- **Substance database updates** without an App Store release. Opt-in updater
  in Settings; manifest checked once a day, downloads + SHA-256 verifies before
  applying, rollback on failure.
- **Two new categories**: **Peptide** (28 entries — semaglutide, tirzepatide,
  BPC-157, TB-500, sermorelin, ipamorelin, GHK-Cu, PT-141, etc.) and
  **Anticonvulsant** (17 — lithium, valproate, lamotrigine, levetiracetam,
  topiramate, gabapentin's seizure variants).
- **218 newly-curated substances** with FDA-label-grade dosing:
  - **22 antipsychotics** (was 1) — haloperidol, risperidone, olanzapine,
    quetiapine, aripiprazole, clozapine, cariprazine, lurasidone,
    pimavanserin, ...
  - **31 antihistamines** (was 9) — cetirizine, loratadine, diphenhydramine,
    hydroxyzine, promethazine, the H2 blockers, ...
  - **48 antidepressants** (was 4) — every common SSRI, SNRI, TCA, MAOI,
    bupropion, mirtazapine, trazodone, tianeptine (flagged as habit-forming
    μ-opioid agonist).
  - **45 cannabinoids** (was 11) — THC, CBD, CBN, CBG, CBC, CBDV, THCV,
    Δ-8-THC, Δ-10-THC, HHC, HHCP, THCP, dronabinol, nabilone, the synthetic
    SCRAs flagged as high-risk.
  - **52 supplements** — NAC, ALA, ALCAR, CoQ10, magnesium variants,
    ashwagandha, lion's mane, methylfolate, 5-HTP (flagged serotonin-syndrome
    risk), the full B-vitamin panel.
  - **12 cardiovascular** — propranolol, atenolol, metoprolol, clonidine,
    prazosin — the ones used off-label for anxiety / PTSD / performance.
- **Dysdelic icon** (was a broken SF Symbol that silently crashed the
  category list on some devices).

### Improved

- **Cold launch.** Substance library no longer fetches from three different
  APIs at startup — the bundled SQLite is opened directly. App is usable on
  the first frame.
- **Library tab responsiveness.** Resolving all ~1,800 substances dropped
  from ~21,000 SQL queries to ~12 using a single batch load with window
  functions. The list now appears immediately instead of after a 1–2 second
  hitch.
- **Localization** (zh-Hans, zh-Hant):
  - Duration row labels and chart overlap legend now translate.
  - Relative-time and duration suffixes (h / m / d) localised.
  - Substance category picker in the custom-substance sheet translates.
  - ~30 other previously-unlocalised strings now appear in the user's
    language.
- **Categorisation.** Drug.community's 200+ free-form category strings
  ("Antidepressant (NaSSA: noradrenergic and specific serotonergic)",
  "µ-opioid receptor agonist") now collapse to the canonical 27 categories
  the app actually displays.
- **Capitalisation.** 131 substance names that arrived all-lowercase
  ("indopan", "dextroamphetamine") are now title-cased; acronyms like
  LSD/MDMA/THC/CBD/DXM stay uppercase; chemical naming like 5-MeO-DMT and
  BPC-157 is preserved.
- **Default route for benzos and other prescription drugs.** Diazepam,
  lorazepam, midazolam, and other substances with multiple ROAs no longer
  default to Intravenous — they default to the most common route (oral)
  as a typical user would expect.
- **Detail-view source attribution.** Each dose, duration, half-life, and
  mechanism row shows which source supplied it (full source name, not slug).

### Fixed

- **Crash when picking a colour for a new substance** (build 11 — TestFlight
  feedback). The picker built a `[hex → substance]` dictionary that crashed
  whenever two substances shared a colour. With ~1,800 substances and ~30
  preset colours, sharing is unavoidable. The picker now allows colour
  sharing (still shows "also used by X" as info) and no longer crashes.
- **Drug.community dose parser** silently truncated values in three ways:
  - `"1,000 mg"` parsed as `1.0` (comma read as decimal). Aniracetam's
    common-dose was off by 1000×.
  - `"1 200 µg"` parsed as `1.0` (regular space as digit terminator). 25I
    series, Agmatine, Chloral Hydrate were similarly corrupted.
  - `"1.0–1.5 mg"` in a µg row stored `1.0 µg` instead of converting
    to µg. 2C-T-7-NBOMe oral dose was 1000× too low.
  - `"5 mg - 15 mg"` returned nothing (regex failed on inline unit
    between bound and dash). ~100 ranges silently dropped — 4B-MAR,
    9-Me-BC, others now have correct ladders.
- **Psilocybin, Psilocin, Ayahuasca** were misclassified. Psilocybin had no
  source category except Wikidata's "Other"; Psilocin and Ayahuasca were
  tagged Empathogen by TripSit. All three are now correctly Psychedelic.
- **2C-B** was Empathogen → Psychedelic (its 5-HT2A agonism is the
  primary mechanism).
- **2C-F** was Other → Psychedelic. **Isotonitazepyne** was Other →
  Opioid (nitazene class). **Pregabalin** and **Gabapentin** were
  Anticonvulsant → GABAergic (they're α2δ ligands first).
- **29 IUPAC chemistry-noise entries** that bled into the library from
  Wikidata (`(+/-)-noradrenaline`, `(R)-N-trans-feruloyloctopamine`,
  `(E,E)-bastadin 19`) are now filtered at build time.
- **Calendar nil-ID collision in AdherenceView** (pre-merge fix from main).

### Removed

- **Runtime API fetches** for TripSit / PsychonautWiki / DailyMed at app
  launch. All substance data is now bundled. Network is only used for opt-in
  database updates.

### Internal / engineering

- New `SubstanceStore` (GRDB-backed) replaces the old `SubstanceLibrary`
  in-memory dictionary. Per-field source resolution, deterministic priority
  ordering.
- `Tools/SubstanceCollector` Swift CLI assembles the bundled JSON from
  TripSit, Wikidata + PubChem, Erowid PIHKAL/TIHKAL, and the hand-curated
  overlay.
- `Exports/build-sqlite-database.py` builds the bundled SQLite. New passes:
  `is_chemistry_noise`, `smart_title_case`, `normalize_category`,
  `promote_via_tags`.
- `Exports/test_build_sqlite_database.py` pins all of the data-quality
  fixes above as unit tests + end-to-end SQLite invariants.
- `Exports/dump-substance-library.py` emits one `.txt` per resolved
  category for visual review.
- `Exports/build-sqlite-database.py` ingest gate now drops dose rows that
  violate per-class magnitude ceilings (fentanyl-class & nitazene ≤2 mg,
  benzodiazepine ≤300 mg, lysergamide ≤5 mg) — catches single-tier rows
  that pass structural checks but are physically inconsistent with the
  substance class (e.g. TripSit's bare "Valerylfentanyl 50 mg oral").
- `Exports/compare_to_pw.py` audits the resolved DB against
  PsychonautWiki on dose, duration, and half-life. Used this build to
  align piru-curated entries with PW for popular substances, leaving
  only a handful of deliberate overrides (Gaboxadol, Pentedrone,
  Mirtazapine, Adrafinil — each with a documented reason).
- Test suite grew from ~470 to 499 tests across 47 suites.

---

## 1.2 (build 11) — previous TestFlight release

Reference baseline — what's in the App Store / TestFlight today.

- Per-source substance attribution (initial cut)
- Centralised navigation (`AppNavigator` + deep links)
- Chinese (Simplified + Traditional) localisation
- drug.community added as a fourth runtime data source
