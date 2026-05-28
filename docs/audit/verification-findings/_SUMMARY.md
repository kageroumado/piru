# Substance DB Verification — Summary

41 Sonnet agents reviewed 1,158 substances across 41 category chunks.

## Bugs found and fixed during verification

### 1. Route fragmentation (fixed)
PsychonautWiki classified inhaled doses as `smoked`, TripSit as `inhalation`, others as `vaped`/`nasal`/`intranasal`/etc. The resolver only matched the user's chosen route string, so PsychonautWiki's correct Cannabis inhalation data (common 2–4 mg) was invisible and TripSit's 20–60 mg won. Fix: `Exports/build-sqlite-database.py` `_ROUTE_ALIASES` now collapses smoking/vaping/nebulising to canonical `inhalation`, and nasal/intranasal to `insufflation`.

### 2. drug.community duration unit bug (fixed)
`build-sqlite-database.py:1377` hardcoded ×60 on every drug.community duration, assuming hours. The source actually labels each curve with explicit units — 698 in hours, 43 in minutes, 3 in days. Minute-denominated entries got inflated 60× (e.g. **6-MAM IV total 90 min → 5400 min = 90 h**, which would tell a user heroin's active metabolite lasts ~4 days). Fix: respect the `units` field. After the fix, Opioid_01 BLOCKERs dropped from 11 → 3, Cannabinoid from 7 → 2.

## Verification findings (post-fix)

- ~140 BLOCKER mentions (severity counter, but rationale prose also matches), spread across 39 of 41 categories
- ~176 MAJOR
- ~46 MINOR

All findings are in `Exports/verification-findings/*.md`. Aggregated dump at `_ALL.md`.

## Remaining critical themes

### Heavy-threshold unit ambiguity
Many substances have light/common/strong in µg or mg but `heavy ≥X` shown bare without unit context. Examples:
- **Fentanyl IV**: light 25–50 µg shown as 0.025–0.05 mg, but `heavy ≥100` would read as ≥100 mg (lethal hundreds of times over) instead of the intended ≥100 µg = 0.1 mg. Same issue oral (≥200).
- **AMB-CHMICA inhalation**: `threshold 100` with no unit label, while the dose range that follows is in µg.

This is a **display bug** (how the resolved value renders), not just data. The renderer needs to either always show the unit on `heavy`/`threshold`, or store all tier values in the same unit as the dose range and never drop precision.

### Mixed units within a single row
**Butyrfentanyl oral**: `light 400–800 mg, common 800–1500 mg, strong 1.5–3 mg` — the first two are in µg-as-mg (off by 1000×), strong jumps back to mg. Single-row ingestion bug in whichever source contributed this; agent confirms it's instantly lethal at the displayed values.

### Half-life vs duration confusion (a few)
**Nabilone oral half-life: 2h shown, ~35h actual** (Cesamet prescribing info). Off by 17×. Likely confused with duration of subjective effect.

### Onset = 0s
**IV heroin/morphine onset min = 0s**. Physiologically impossible — BBB transit is ≥5s minimum. Agents flagged as MINOR; not a harm issue but a data quality signal.

### Cannabis (worth knowing)
Post-fix, Cannabis inhalation now shows **PsychonautWiki common 2–4 mg THC** — matches the user's "2 mg" recollection from the old data. The verification agent flagged this as MAJOR with the opposite concern ("should be 5–25 mg"). Both are defensible; PsychonautWiki's number is closer to the *minimum noticeable* THC dose while popular consumption is in the 5–25 mg range. Worth deciding what tier semantics the app intends — "common" as the typical user dose, or "common" as the start of meaningful effect.

## Files

- `Exports/verification-dump/` — 41 input chunks (1,158 substances)
- `Exports/verification-findings/` — 41 finding files + `_ALL.md` (aggregated) + `_SUMMARY.md` (this file)
- `Exports/verification-findings-prefix/` — pre-fix snapshot for reference

## Top files to review by BLOCKER count

| File | BLOCKER mentions |
|------|---:|
| Supplement_01 | 4 |
| Opioid_02 | 4 |
| Depressant_02 | 4 |
| Psychedelic_05 | 3 |
| Psychedelic_04 | 3 |
| Psychedelic_01 | 3 |
| Other | 3 |
| Opioid_01 | 3 (was 11 pre-fix) |
| Gastrointestinal | 3 |
| Dissociative_01 | 3 |
| Benzodiazepine_01 | 3 |
