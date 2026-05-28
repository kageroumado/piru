# Cannabinoid Verification Findings

### 4F-Neb
- **Route / Field**: Insufflation — common dose; Oral — common dose
- **Shown**: Insufflation common 75–150 mg; Oral common 100–150 mg (tripsit)
- **Expected**: Sub-milligram to low-milligram range, consistent with all other synthetic cannabinoids in this list (next-highest common inhaled doses are ~1–5 mg)
- **Severity**: BLOCKER — 75–300 mg is 50–300× higher than any comparable SC; if this is a synthetic cannabinoid these doses would be acutely life-threatening; likely a data entry error in TripSit conflating a different compound or using wrong units

### CBN-O
- **Route / Field**: Inhalation — onset duration
- **Shown**: onset 5m–20m (piru-curated)
- **Expected**: 1m–5m; CBN-O is cannabinol acetate ester, not a prodrug requiring hepatic deacetylation the way THC-O does — inhalation should produce near-immediate absorption; 5–20 min onset is inconsistent with pulmonary pharmacokinetics for a lipophilic cannabinoid
- **Severity**: MAJOR

### JWH-073
- **Route / Field**: Inhalation — offset duration
- **Shown**: offset 5m–10m (psychonautwiki)
- **Expected**: 30m–60m minimum; offset of 5–10 min is irreconcilable with the listed total of 1h–2h (onset 5–10 min + peak 1h–1.5h + offset 5–10 min far exceeds the stated total); likely a data entry error in PsychonautWiki (possibly comedown mislabeled as offset)
- **Severity**: MAJOR

### 5F-Pb-22
- **Route / Field**: Oral — all dose tiers
- **Shown**: threshold 1 mg, light 1–3 mg, common 3–5 mg, strong 5–8 mg, heavy ≥8 mg (psychonautwiki) — identical to inhalation doses
- **Expected**: Oral doses should be higher than inhalation doses; synthetic cannabinoids have substantially lower oral bioavailability vs inhalation; identical ranges suggest the oral entry is a copy of the inhalation entry
- **Severity**: MAJOR

### Nabilone
- **Route / Field**: Half-life
- **Shown**: 35h (piru-curated)
- **Expected**: ~2h for parent compound (per FDA label and published PK studies); active metabolites extend to ~35h, but storing the metabolite half-life as the compound half-life will cause the app to massively overestimate how long nabilone remains active; should be labeled as effective/metabolite half-life or corrected to ~2h parent + note
- **Severity**: MAJOR

### THC
- **Route / Field**: Inhalation — light/common dose gap
- **Shown**: light 2–5 mg, common 10–25 mg (piru-curated)
- **Expected**: No gap between tiers; light top (5 mg) and common bottom (10 mg) leave an uncharacterized 5–10 mg band; minor compared to other findings but atypical formatting — common lower bound should be ~5 mg to be contiguous with light
- **Severity**: MINOR
