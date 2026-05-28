# Verification Findings — Psychedelic_02

### 2C-N
- **Route / Field**: oral / dose
- **Shown**: light 100 mg, common 100–125 mg, strong 125–150 mg
- **Expected**: light ~50–75 mg, common ~75–100 mg — PIHKAL gives active range 100–150 mg for common but the "light" tier should be below the common floor, not equal to it; light = common here is a tier-collision artifact, not a genuine pharmacological error, but the absolute values are consistent with Shulgin's report so the common dose range itself is plausible. Skipping.

### 2C-T (the unsubstituted 2C-T)
- **Route / Field**: oral / duration peak
- **Shown**: peak 30m–1.91667h
- **Expected**: peak is a display artifact from a fractional-hours conversion (1h 55m → 1.91667h); should render as ~2h. Not a pharmacological error but a formatting bug. Skipping (out of scope for this pass).

### 2C-T-21
- **Route / Field**: oral / total duration
- **Shown**: total 10h–12h (psychonautwiki)
- **Expected**: 2C-T-21 is reported as a relatively short-acting thio-2C with most trip reports citing 4–6 h total; 10–12 h is implausibly long and ~2× community consensus.
- **Severity**: MAJOR

### 4-Aco-Det (inhalation)
- **Route / Field**: inhalation / total duration
- **Shown**: total 30m–1.5h (drug.community)
- **Expected**: 4-AcO-DET is a prodrug of 4-HO-DET; vaporized tryptamines typically last 1–3 h. A lower bound of 30 minutes is extremely short — Erowid and community reports consistently show 1–2 h minimum even by inhalation. 30 min lower bound is plausible only for a brief peak, not total duration.
- **Severity**: MINOR

### 4-HO-DMT / Psilocin (oral)
- **Route / Field**: oral / common dose
- **Shown**: common 10–20 mg (erowid-tihkal)
- **Expected**: Shulgin's own TIHKAL entry for psilocin lists active doses starting around 6–10 mg with a common range of 10–15 mg; 20 mg upper bound pushes into strong territory for most users. The range is defensible but slightly generous — not a clear blocker.
- **Severity**: MINOR

### 4-HO-DPT (oral)
- **Route / Field**: oral / threshold and dose tiers
- **Shown**: threshold 20 mg, light 40–60 mg, common 60–90 mg, strong 90–130 mg, heavy ≥130 mg (psychonautwiki)
- **Expected**: 4-HO-DPT threshold is consistent with trip reports (~15–25 mg), but the common dose of 60–90 mg oral is very high. Community data (Erowid, drug.community) places common oral at 20–40 mg; 60–90 mg is squarely in "strong to overwhelming" territory. The psychonautwiki figures appear to be systematically inflated by ~2×.
- **Severity**: MAJOR

### 3C-BZ (oral)
- **Route / Field**: oral / common dose range
- **Shown**: common 25–200 mg (erowid-pihkal)
- **Expected**: An 8× spread within a single "common" tier (25–200 mg) is not a dose range — it spans threshold to heavy for virtually any psychedelic. PIHKAL describes 3C-BZ as highly variable but the range as presented is too wide to be useful and likely collapses multiple tiers into one. Flagging as a data-quality issue.
- **Severity**: MINOR

### 4-Fluorophenylpiperazine
- **Route / Field**: oral / category classification
- **Shown**: listed under Psychedelic category
- **Expected**: 4-Fluorophenylpiperazine (4-FPP / pFPP) is a piperazine with primarily serotonergic/adrenergic activity; it is typically classified as a stimulant or entactogen, not a psychedelic. The dose ranges shown (40–80 mg common oral) are consistent with stimulant/piperazine literature. Misclassification under Psychedelic is an error, but dose values themselves are plausible for the compound.
- **Severity**: MAJOR
