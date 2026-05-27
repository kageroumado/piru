# Opioid_01 Verification Findings

### Butyrfentanyl
- **Route / Field**: oral / light–strong doses
- **Shown**: light 400–800 mg, common 800–1500 mg, strong 1.5–3 mg
- **Expected**: all values should be in µg (micrograms), e.g. light ~400–800 µg, common ~800–1500 µg. The "strong 1.5–3 mg" also appears to be a unit switch mid-field — likely 1500–3000 µg — but the mixing of mg and µg within one row is an ingestion error. Butyrfentanyl is a fentanyl analogue; oral doses in the hundreds of milligrams would be instantly lethal.
- **Severity**: BLOCKER

### Fentanyl
- **Route / Field**: intravenous / heavy threshold
- **Shown**: heavy ≥100 (drug.community) — in context the preceding values are in mg (0.005 mg threshold, 0.025–0.05 mg common), so "heavy ≥100" is ambiguous. If parsed as mg, 100 mg IV fentanyl is ~200× a lethal dose. If parsed as µg (which the field likely intends given the preceding mg values are low-end µg equivalents), the value is at least self-consistent but the unit label is missing.
- **Expected**: heavy ≥0.1 mg (= ≥100 µg) with explicit µg unit, consistent with the rest of the row.
- **Severity**: BLOCKER

### Fentanyl
- **Route / Field**: oral / heavy threshold
- **Shown**: heavy ≥200 (drug.community) — same issue as IV. Preceding oral values are threshold 0.01 mg, light 0.025–0.05 mg, common 0.05–0.1 mg, strong 0.1–0.2 mg. "≥200" with no unit change would parse as ≥200 mg oral, which is tens of thousands of times a lethal dose.
- **Expected**: heavy ≥0.2 mg (i.e. the natural continuation of the mg series), or explicit ≥200 µg.
- **Severity**: BLOCKER

### Heroin
- **Route / Field**: intravenous / onset and comeup durations
- **Shown**: onset 0s–5s, comeup 0s–5s
- **Expected**: IV heroin onset is typically felt within 5–15 seconds (rush within ~7–10 s); a 0-second lower bound for both onset and comeup is physiologically impossible for any IV drug — blood-brain transit takes a minimum of ~5 s even at maximal cardiac output. Lower bound should be at least 5s.
- **Severity**: MINOR

### Hydrocodone
- **Route / Field**: oral / common dose
- **Shown**: common 10–25 mg (psychonautwiki)
- **Expected**: Hydrocodone standard therapeutic doses are 5–10 mg per dose (immediate release). A "common" recreational upper bound of 25 mg is about 2.5× the standard dose ceiling. While some tolerant users reach this range, listing 25 mg as the top of "common" (not "strong") could lead opioid-naive users to take dangerous doses. PsychonautWiki's own entry historically lists common as 10–20 mg. The 25 mg upper edge overstates by ~25%.
- **Severity**: MAJOR

### Morphine
- **Route / Field**: intravenous / onset
- **Shown**: onset 0s–30s
- **Expected**: IV morphine onset (first CNS effect) is typically 1–5 minutes — slower than heroin/fentanyl because morphine crosses the BBB poorly (low lipophilicity). A 0-second lower bound is implausible; 1m–5m is standard clinical teaching.
- **Severity**: MAJOR

### Morphine
- **Route / Field**: oral / common dose
- **Shown**: common 15–20 mg (psychonautwiki)
- **Expected**: Oral morphine standard starting dose for opioid-naive adults is 5–15 mg q4h. A common recreational range of 15–20 mg is reasonable for someone with mild tolerance but low for truly naive users. More importantly the strong range (20–30 mg) flows naturally from this, so the tier calibration is acceptable. Not flagging as a strict error, but the lower bound of 15 mg is at the high end for naive users.
- **Severity**: MINOR (noted for context; not a clear error)

### Buprenorphine
- **Route / Field**: oral / total duration
- **Shown**: duration not shown (tripsit only provides onset and afterglow, no total)
- **Expected**: Buprenorphine oral has a known total duration of 6–12 h (partial agonist ceiling effect extends duration vs full agonists). Missing total duration is a data gap, not a value error — not flagging.

### Furanylfentanyl
- **Route / Field**: insufflation / common dose
- **Shown**: light 200–400 µg, common 400–800 µg, strong 800–1600 µg (tripsit)
- **Expected**: The drug.community alternative lists common as 75–200 µg — about 4× lower. Furanylfentanyl community reports consistently place active doses in the 200–500 µg range insufflated; 400–800 µg as "common" is plausible for tolerant users but very high for naive users. The tripsit values may represent an experienced-user baseline. The discrepancy is flagged by the `[also:]` annotation. The resolved (tripsit) value is on the high end but not impossible; however at 800–1600 µg "strong" this substance has caused overdose deaths. Given the fatality record, the winning source's upper bound warrants scrutiny.
- **Severity**: MAJOR
