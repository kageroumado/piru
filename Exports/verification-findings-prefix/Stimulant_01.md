# Stimulant_01 Verification Findings

### 4-Methylaminorex (4-MAX / "U4Euh")
- **Route / Field**: oral / common dose
- **Shown**: common 5–10 mg (tripsit)
- **Expected**: common 10–25 mg — community reports and PsychonautWiki consistently place common oral doses in the 10–25 mg range; the tripsit value reflects a conservative/threshold tier, not the typical recreational dose. The `[also: drug.community: common 10–25 mg]` alternate confirms the winning value is an underestimate.
- **Severity**: MAJOR

### 4-Fluoromethylphenidate (4F-MPH)
- **Route / Field**: oral / afterglow duration
- **Shown**: afterglow 5h–10h
- **Expected**: afterglow 1h–3h — afterglow of 5–10 h for a methylphenidate analogue is anomalously long. Standard MPH and its fluorinated analogues produce afterglow lasting roughly 1–3 h. A 5–10 h afterglow would be consistent with the *total* duration, not the afterglow phase, suggesting a data entry confusion.
- **Severity**: MAJOR

### 2-DPMP (Desoxypipradrol)
- **Route / Field**: insufflation / total duration
- **Shown**: total 16h–72h (tripsit)
- **Expected**: total 16h–36h — the upper bound of 72 h is plausible only for extreme doses; community harm-reduction documentation (PsychonautWiki, Erowid trip reports) consistently reports 24–36 h as the typical upper bound for a single dose. A 72 h total is not impossible at high doses, but presenting it as a routine range without a strong-dose qualifier is misleading and may cause users to underestimate duration and redose dangerously. NOTE: this is an edge call — the half-life of 18 h makes a very long duration biologically plausible. Flagging MINOR only.
- **Severity**: MINOR

### 4-CMC (Clephedrone)
- **Route / Field**: oral / common dose
- **Shown**: common 50 mg (single value, no range) (tripsit)
- **Expected**: common 50–100 mg — a point value with no range is almost certainly a truncated or incomplete entry. Community and TripSit data for cathinones in this potency class consistently give a range. A single value of "50 mg" with no upper bound is functionally useless and suggests data corruption or truncation.
- **Severity**: MINOR
