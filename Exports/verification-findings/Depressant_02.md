# Depressant_02 Verification Findings

### Phenobarbital
- **Route / Field**: oral / total duration
- **Shown**: total 4h–6h
- **Expected**: ~10h–16h (or listed as "long/days-long"). Phenobarbital has a half-life of 80–120 hours and a pharmacodynamic duration of 8–16+ hours at sedative doses. A 4–6h total duration is inconsistent with any published source and is internally contradicted by the offset field (12h–24h) shown in the same entry.
- **Severity**: BLOCKER — a user seeing "4–6h total" will severely underestimate residual sedation and may redose dangerously.

### Tizanidine
- **Route / Field**: oral / heavy dose
- **Shown**: heavy ≥36 mg
- **Expected**: heavy ≥12–16 mg. Tizanidine's prescribing maximum is 36 mg/day in divided doses (typically 3×12 mg). Presenting 36 mg as a single recreational "heavy" threshold implies a single 36 mg dose is the floor for heavy use, which is a lethal-range single dose — reports of severe toxicity and fatalities exist at doses of 25–40 mg taken at once.
- **Severity**: BLOCKER — conflates a daily maximum with a single-dose threshold; could lead a user to take a day's worth in one sitting.

### Zolpidem
- **Route / Field**: oral / common dose
- **Shown**: common 20–30 mg
- **Expected**: common 5–10 mg. The therapeutic/recreational sweet spot is 5–10 mg; 10 mg is the approved maximum single dose. 20–30 mg is a strong-to-overdose range associated with anterograde amnesia, complex sleep behaviors, and respiratory depression especially with alcohol. Two alternative sources (TripSit, drug.community) both agree on 5–10 mg common.
- **Severity**: BLOCKER — common dose is 2–6× above the clinically accepted range and the consensus of both alternative sources.

### Secobarbital
- **Route / Field**: oral / peak duration
- **Shown**: peak 4h–8h
- **Expected**: peak 1h–3h. Secobarbital is a short-acting barbiturate with total duration typically 4–6h. A peak of 4–8h would extend beyond or equal the total duration, which is pharmacologically impossible. Clinical references place peak effect at 1–3h after oral dosing.
- **Severity**: MAJOR — internally inconsistent (peak cannot exceed or equal total) and misrepresents the drug's time course.

### Nicotine
- **Route / Field**: oral / total duration
- **Shown**: total 5h–7h
- **Expected**: 1h–3h for a single oral dose (e.g., nicotine gum/lozenge). The 5–7h figure appears to reflect patch-like transdermal kinetics, not oral tablet/gum kinetics. Nicotine oral bioavailability is low (~20–35%) with Tmax ~1h; effects at typical doses last 1–2h. 5–7h would only apply to very slow-release formulations not covered by the dose range shown.
- **Severity**: MAJOR — off by ~3× for conventional oral nicotine formats.

### Thiopental
- **Route / Field**: intravenous / total duration
- **Shown**: total 5h–15h
- **Expected**: 5–15 minutes for induction dose (2–5 mg/kg IV bolus). Thiopental is an ultra-short-acting barbiturate; single IV induction doses produce unconsciousness for 5–15 minutes due to rapid redistribution, not 5–15 hours. The 5–15h figure reflects elimination half-life, not duration of effect — these are frequently confused for thiopental specifically.
- **Severity**: BLOCKER — a user reading "5–15h duration" would dramatically underestimate how quickly thiopental wears off and the risk of redosing.
