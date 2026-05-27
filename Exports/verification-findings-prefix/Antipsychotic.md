# Antipsychotic Verification Findings

### Aripiprazole
- **Route / Field**: intramuscular / threshold vs light dose ordering
- **Shown**: threshold 400 mg, light 300–400 mg
- **Expected**: threshold should be below the light range floor; here threshold (400) equals or exceeds the top of the light range (400) while the light range bottom (300) is below threshold — the dose tiers are inverted. For the Abilify Maintena depot, 400 mg is the standard dose and 300 mg is the lower approved dose; threshold should be ≤300 mg or the light range should start at 400 mg.
- **Severity**: MAJOR

### Cariprazine
- **Route / Field**: half-life
- **Shown**: 1200h (~50 days)
- **Expected**: ~91–504h (4–21 days). Cariprazine's primary active metabolite DDCAR has a half-life of approximately 1–3 weeks (168–504h). 1200h (50 days) is 2–3× too long and not supported by the prescribing information or published PK studies.
- **Severity**: MAJOR

### Quetiapine
- **Route / Field**: oral / common dose
- **Shown**: 150–750 mg
- **Expected**: common dose range of 150–400 mg (antipsychotic indication) or 50–150 mg (sedation/augmentation, which is the predominant recreational/tracking use case). A 5× span (150–750 mg) spanning from low therapeutic to near-maximum daily dose makes "common" meaningless and conflates multiple distinct indications. The PsychonautWiki value (50–150 mg) and TripSit value (50 mg) both flag this discrepancy.
- **Severity**: MAJOR

### Quetiapine
- **Route / Field**: oral / strong and heavy dose
- **Shown**: strong 750–800 mg, heavy ≥800 mg
- **Expected**: strong ≥400–600 mg, heavy ≥800 mg. Since common extends to 750 mg, the "strong" band is only 50 mg wide (750–800). This leaves effectively no daylight between common and heavy, making the strong tier pharmacologically uninformative.
- **Severity**: MINOR

### Pimavanserin
- **Route / Field**: oral / strong and heavy dose
- **Shown**: strong 34 mg, heavy ≥34 mg
- **Expected**: Pimavanserin is a fixed-dose drug (34 mg/day is the sole approved dose). Having strong = 34 mg and heavy = ≥34 mg means the standard therapeutic dose is simultaneously labeled "strong" and the floor of "heavy." Users seeing their prescribed dose flagged as heavy/strong could be alarmed without cause, or conversely could misinterpret the label. There is no meaningful supertherapeutic range to distinguish strong from heavy here; at minimum heavy should be ≥68 mg (2× standard dose).
- **Severity**: MINOR

### Paliperidone
- **Route / Field**: oral / total duration
- **Shown**: 96–192h (4–8 days)
- **Expected**: ~24–36h. Oral paliperidone (Invega) is a once-daily formulation with a half-life of ~23h. Per-dose duration should be approximately 24h. 4–8 days reflects steady-state accumulation over a dosing regimen, not the duration of effect of a single oral dose, and would mislead users about how long a single dose lasts.
- **Severity**: MAJOR
