# Antidepressant — Verification Findings

### Isocarboxazid
- **oral / half-life**
- **Shown**: 2.5h
- **Expected**: ~36h — isocarboxazid's plasma elimination half-life is reported as approximately 36h in clinical pharmacokinetic studies; 2.5h is closer to the half-life of phenelzine or tranylcypromine and appears to be a cross-substance data error
- **Severity**: BLOCKER

### Desvenlafaxine
- **oral / heavy**
- **Shown**: ≥400 mg
- **Expected**: ≥150 mg — the maximum recommended daily dose is 100 mg; doses above 100 mg confer no additional antidepressant benefit and increase adverse effects; 400 mg as the heavy threshold is 4× the clinical ceiling
- **Severity**: MAJOR

### Tianeptine
- **oral / common**
- **Shown**: 25–50 mg
- **Expected**: 12–25 mg — the therapeutic regimen is 12.5 mg three times daily (37.5 mg total daily); a single-dose common of 25–50 mg exceeds the full daily therapeutic dose; PsychonautWiki (12–35 mg) and TripSit (12.5 mg) both corroborate the lower range
- **Severity**: MAJOR

### Fluoxetine
- **oral / half-life**
- **Shown**: 384h (16 days)
- **Expected**: 96–288h (4–12 days) — parent fluoxetine half-life is 1–4 days; active metabolite norfluoxetine is 4–16 days; citing 384h represents the absolute upper bound of the metabolite range and overstates the effective half-life that most references cite as 1–2 weeks (168–336h)
- **Severity**: MINOR

### Milnacipran
- **oral / strong and heavy**
- **Shown**: strong 200 mg, heavy ≥200 mg
- **Expected**: strong threshold below 200 mg (e.g., 150–200 mg), heavy ≥200 mg — strong and heavy share an identical boundary at 200 mg, making the strong tier a zero-width range at its upper bound; maximum approved dose is 200 mg/day, so the heavy anchor is correct but strong needs a lower ceiling
- **Severity**: MINOR

### Tranylcypromine
- **oral / half-life**
- **Shown**: 2.16667h
- **Expected**: 2.5h — the value 2.16667 = 130 ÷ 60, indicating 130 minutes was entered and divided by 60 rather than using the published half-life of ~2.5h; pharmacologically close but the fractional artifact signals a unit-conversion error in data entry
- **Severity**: MINOR
