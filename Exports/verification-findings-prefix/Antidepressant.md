# Antidepressant — Verification Findings

### Doxepin
- **Route / Field**: oral / dose tier continuity
- **Shown**: threshold 3, light 3–10 mg, common 75–150 mg (gap of 10–75 mg is unrepresented)
- **Expected**: Light should extend toward ~25–50 mg or an intermediate tier should exist; the 65 mg gap between the top of "light" (10 mg) and the bottom of "common" (75 mg) means every dose in the 10–75 mg range is unclassified. A user logging 30 mg sees no tier.
- **Severity**: MAJOR

### Milnacipran
- **Route / Field**: oral / strong and heavy overlap
- **Shown**: strong 200 mg (single point), heavy ≥200 mg — both start at 200 mg, strong has zero width
- **Expected**: strong should span a range below heavy, e.g. strong 150–200 mg, heavy ≥200 mg; or strong 200–250 mg, heavy ≥250 mg. As written, "strong" is a degenerate tier.
- **Severity**: MAJOR

### Desvenlafaxine
- **Route / Field**: oral / heavy threshold
- **Shown**: strong 50–100 mg, heavy ≥400 mg (gap of 100–400 mg is unrepresented)
- **Expected**: heavy should begin where strong ends, ≥100 mg. The 300 mg gap means doses from 100–399 mg show no tier. The FDA-approved dose is 50 mg/day; doses above 100 mg are off-label and should still be classifiable.
- **Severity**: MAJOR

### Fluoxetine
- **Route / Field**: oral / half-life
- **Shown**: 384h (16 days)
- **Expected**: ~96–144h (4–6 days) for the combined parent+norfluoxetine effective half-life as used clinically. 384h is the extreme upper bound of norfluoxetine in ultra-slow CYP2D6 metabolizers; using it as the single stated half-life will cause the app's PK curves and active-substance calculations to show fluoxetine as active for weeks past when it is practically relevant for nearly all users.
- **Severity**: MAJOR

### Tianeptine
- **Route / Field**: oral / common dose
- **Shown**: common 25–50 mg
- **Expected**: common ~12.5–37.5 mg (the standard therapeutic regimen is 12.5 mg three times daily = 37.5 mg/day total). The lower bound of 25 mg is above the standard single dose (12.5 mg) and the upper bound of 50 mg exceeds the standard total daily dose. If the field is per-dose, 25–50 mg is substantially above therapeutic; if per-day, the lower bound should start at 37.5 mg. Either way the range is shifted high relative to the clinical standard.
- **Severity**: MAJOR

### Tianeptine sodium
- **Route / Field**: oral / heavy dose
- **Shown**: heavy ≥100 mg
- **Expected**: ≥75 mg is where opioid-like abuse and dependency risk becomes clinically significant for tianeptine sodium. The standard maximum therapeutic daily dose is 37.5 mg; 100 mg/day represents approximately 2.7× the therapeutic ceiling and is well into abuse/toxicity territory. For harm-reduction purposes, heavy should arguably start at ≥50–75 mg to flag this risk zone sooner.
- **Severity**: MINOR

### Selegiline
- **Route / Field**: oral / strong and heavy overlap
- **Shown**: strong 10 mg (single point), heavy ≥10 mg — identical threshold, zero-width strong tier
- **Expected**: strong should span a range, e.g. strong 10–15 mg; heavy ≥15 mg. Additionally, oral selegiline >10 mg/day loses MAO-B selectivity and becomes a non-selective MAOI, requiring tyramine dietary restriction — this pharmacological threshold at 10 mg makes the zero-width strong tier particularly confusing.
- **Severity**: MAJOR

### Tranylcypromine
- **Route / Field**: oral / strong and heavy overlap
- **Shown**: strong 60 mg (single point), heavy ≥60 mg — identical threshold, zero-width strong tier
- **Expected**: strong should span a range, e.g. strong 60–80 mg, heavy ≥80 mg (max recommended dose is 60 mg/day for maintenance, with some sources citing up to 90 mg under supervision).
- **Severity**: MAJOR
