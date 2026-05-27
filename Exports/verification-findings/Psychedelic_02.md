# Pharmacological Review — Psychedelic_02

### 2C-T (2,5-dimethoxy-4-(methylthio)phenethylamine)
- **Route / Field**: oral / peak duration
- **Shown**: peak 30m–1.91667h (≈ 30m–115min)
- **Expected**: peak ~2h–4h; total 4h–6h is plausible but the fractional "1.91667h" is a floating-point artefact (115/60), not a real data value — indicates a raw-minutes field was divided by 60 without rounding
- **Severity**: MINOR (display artefact, not a dose safety issue, but will confuse users)

### 2C-N
- **Route / Field**: oral / light and common dose
- **Shown**: light 100 mg, common 100–125 mg
- **Expected**: light dose should be below common; a light value equal to the bottom of common is internally inconsistent — typical 2C-N light is ~50–75 mg per community reports
- **Severity**: MAJOR (light = common lower bound makes the tier meaningless and could mislead a first-time user into starting at an already-common dose)

### 4-Aco-Det (4-AcO-DET)
- **Route / Field**: inhalation / total duration
- **Shown**: total 30m–1.5h
- **Expected**: 4-AcO-DET vaporized/smoked is short-acting but community reports consistently place total duration at 1.5h–4h; 30 minutes at the low end is implausibly brief for a tryptamine ester — even DMT vaped lasts 15–30 min; the acetylated tryptamine would be longer
- **Severity**: MAJOR (understating duration could lead a user to redose prematurely)

### 4-HO-DMT / Psilocin (listed as "4-HO-DMT / 4-HO-DMT PHOSPHATE ESTER")
- **Route / Field**: oral / common dose
- **Shown**: common 10–20 mg
- **Expected**: 10–20 mg is correct for pure 4-AcO-DMT or psilocin; however this entry is labelled the phosphate ester (psilocybin). Psilocybin is ~1.4× the MW of psilocin, so the same molar dose is ~14–28 mg. If this entry actually represents the free base (psilocin/4-HO-DMT), 10–20 mg is accurate. The naming ambiguity could lead to a 40% underdose or overdose depending on which form is actually being logged. The slash naming conflating two different molecular forms is the core issue.
- **Severity**: MAJOR (two chemically distinct compounds with meaningfully different dosing collapsed into one entry — could cause systematic dosing errors)

### 2C-P-NBOMe / sublingual
- **Route / Field**: sublingual / common dose
- **Shown**: common 250–600 µg
- **Expected**: 2C-P-NBOMe sublingual community data is extremely thin and the compound is poorly characterised; however the range 250–600 µg spans 2.4× — an unusually wide common range. More importantly, 600 µg sublingual for any NBOMe compound approaches territory where cardiovascular toxicity (hypertensive crisis, seizures) has been reported for well-studied analogues (25I-NBOMe). Given 2C-P's own high potency and long duration (10–20h oral), the NBOMe derivative at 600 µg could be dangerous.
- **Severity**: BLOCKER (upper bound of "common" for an NBOMe of an already-potent, long-duration compound — insufficient safety margin; upper common should probably be flagged as "strong" at minimum)
