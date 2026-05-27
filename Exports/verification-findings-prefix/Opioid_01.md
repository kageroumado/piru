# Opioid_01 Verification Findings

### 4-Methoxybutyrfentanyl
- **Route / Field**: insufflation / total duration
- **Shown**: 30h–90h
- **Expected**: ~1–3h; 4-methoxybutyrfentanyl is a short-acting fentanyl analog with typical recreational duration of 1–2 hours; 30–90 hours matches a long-acting opioid like methadone, not a fentanyl analog
- **Severity**: BLOCKER

- **Route / Field**: intravenous / total duration
- **Shown**: 20h–60h
- **Expected**: ~30m–2h; same rationale — IV fentanyl analogs are short-acting; 20–60 h is ~10–30× too long
- **Severity**: BLOCKER

- **Route / Field**: oral / total duration
- **Shown**: 30h–120h
- **Expected**: 1–4h; oral fentanyl analogs have longer duration than IV but not 30–120 hours; this magnitude belongs to methadone or buprenorphine
- **Severity**: BLOCKER

### 6-Monoacetylmorphine (6-MAM)
- **Route / Field**: inhalation / total duration
- **Shown**: 120h–240h
- **Expected**: 3–5h; 6-MAM (heroin's active metabolite) has a half-life of ~38 minutes and a typical effect duration of 3–5 hours; 120–240 hours (5–10 days) is ~30–50× too long
- **Severity**: BLOCKER

- **Route / Field**: insufflation / total duration
- **Shown**: 120h–240h
- **Expected**: 3–6h; same rationale as above
- **Severity**: BLOCKER

- **Route / Field**: intravenous / total duration
- **Shown**: 90h–180h
- **Expected**: 2–4h; IV 6-MAM has rapid onset and short duration matching heroin; 90–180 hours is implausible
- **Severity**: BLOCKER

### Alfentanil
- **Route / Field**: intravenous / total duration
- **Shown**: 30h–60h
- **Expected**: 30–60 minutes; alfentanil is an ultra-short-acting fentanyl analog used in anesthesia with a plasma half-life of ~90 minutes and clinical duration of 30–60 min; 30–60 hours is ~60× too long
- **Severity**: BLOCKER

### Butyrfentanyl
- **Route / Field**: oral / light–strong doses
- **Shown**: light 400–800 mg, common 800–1500 mg, strong 1.5–3 mg
- **Expected**: light ~100–400 µg, common ~400–1000 µg, strong ~1–2 mg (i.e., microgram range throughout); the light and common values are reported in mg but are ~1000× too high for a fentanyl analog — consistent with a µg→mg unit error; the "strong 1.5–3 mg" value is already in mg and is plausible, making the light/common values internally inconsistent by 3 orders of magnitude
- **Severity**: BLOCKER

### Fentanyl
- **Route / Field**: intravenous / heavy threshold
- **Shown**: heavy ≥100 (drug.community) — displayed without unit context but the preceding values are in mg (0.025–0.1 mg range), so ≥100 mg IV is the implied value
- **Expected**: heavy ≥0.1–0.2 mg (100–200 µg); ≥100 mg IV fentanyl would be a lethal dose many hundreds of times over; almost certainly a unit error (µg vs mg confusion: 100 µg = 0.1 mg)
- **Severity**: BLOCKER

- **Route / Field**: oral / heavy threshold
- **Shown**: heavy ≥200 (drug.community) — same unit context issue; if mg, this is ≥200 mg oral fentanyl
- **Expected**: heavy ≥0.2–0.5 mg (200–500 µg); ≥200 mg oral fentanyl is a massively lethal dose; unit error consistent with IV finding above
- **Severity**: BLOCKER

### Furanylfentanyl
- **Route / Field**: insufflation / common dose
- **Shown**: 400–800 µg (tripsit) [winning source]
- **Expected**: 75–200 µg; the drug.community alternative source listed as [also:] gives 75–200 µg which aligns with community reports and the compound's ~8× potency vs morphine; 400–800 µg is 2–4× higher than documented harm-reduction guidelines and overlaps with doses associated with overdose
- **Severity**: MAJOR

### Lofentanil
- **Route / Field**: intravenous / total duration
- **Shown**: 240h–720h (10–30 days)
- **Expected**: 1–8h; lofentanil is an extremely potent fentanyl analog (~6000× morphine) with a long half-life (~7h) but subjective effect duration of ~2–8 hours; 240–720 hours would mean an IV dose produces effects lasting weeks, which has no clinical or pharmacological basis
- **Severity**: BLOCKER

### Morphine
- **Route / Field**: oral / common dose
- **Shown**: 15–20 mg
- **Expected**: 15–30 mg; this is borderline — the common oral morphine dose for opioid-naive patients is 15–30 mg; the shown range cuts off at 20 mg which under-represents the upper end. The strong dose picks up at 20 mg so there is no gap, but the common range is unusually narrow and low for experienced users. Not a safety-critical error given the adjacent strong range.
- **Severity**: MINOR
