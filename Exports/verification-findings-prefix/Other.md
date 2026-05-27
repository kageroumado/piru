# Verification Findings — Other

### Aspirin
- **Route / Field**: oral / heavy dose
- **Shown**: heavy ≥1.6 (no unit — implied mg by column context, which would be 1.6 mg)
- **Expected**: ≥1600 mg (≥1.6 g); the value is almost certainly 1.6 g but the unit suffix was dropped, making it read as 1.6 mg — indistinguishable from a trace dose rather than a toxic threshold
- **Severity**: BLOCKER — a user interpreting "≥1.6 mg" as the heavy threshold would massively overdose before reaching what they think is "heavy"; the missing "g" is a unit display bug with serious safety implications

### Naloxone
- **Route / Field**: oral / entire dose + duration profile
- **Shown**: oral common 8–16 mg, onset 5–15 min, peak 1–2 h, afterglow 1–12 h
- **Expected**: Oral naloxone has <2% bioavailability due to near-complete first-pass hepatic extraction. It is deliberately used in combination products (e.g. Suboxone) precisely because it is pharmacologically inert by the oral route. There is no meaningful systemic opioid-antagonist effect from oral naloxone at any dose; showing an onset/peak/offset timeline implies therapeutic activity that does not exist.
- **Severity**: BLOCKER — a user or bystander might attempt oral naloxone for overdose reversal based on this profile, believing it will work within 5–15 minutes, when it will not

### Phenylephrine
- **Route / Field**: intravenous / total duration
- **Shown**: total 5h–20h
- **Expected**: ~15–20 minutes. IV phenylephrine has a plasma half-life of ~2.5 minutes and a clinical pressor duration of 15–20 minutes. This is a ~20–60× overestimate of duration.
- **Severity**: BLOCKER — displaying a 5–20 hour duration for an IV vasopressor that wears off in under 30 minutes could cause someone to delay redosing or monitoring, with hemodynamic consequences

### Theobromine
- **Route / Field**: oral / total duration
- **Shown**: total 30h–40h
- **Expected**: ~6h–10h. Theobromine's half-life in humans is approximately 6–10 hours, producing subjective effects for roughly that window. 30–40 hours is 4–5× too long and would alarm users unnecessarily.
- **Severity**: MAJOR — while not acutely dangerous, a 30–40 hour duration vastly overstates the experience; users would expect effects to still be present well after they have resolved

### Apomorphine
- **Route / Field**: sublingual / full dose range
- **Shown**: threshold 10 mg, light 10–15 mg, common 15–25 mg, strong 25–30 mg, heavy ≥30 mg
- **Expected**: Sublingual apomorphine (Kynmobi) is approved at 10–30 mg with 10 mg as the starting dose and 30 mg as the maximum — so this range is technically within approved bounds. However, the sublingual common dose (15–25 mg) being 3–4× higher than the subcutaneous common dose (2–6 mg) is not pharmacologically inconsistent given the different route bioavailabilities (~60% SL vs ~100% SC) and is within clinical use range. On reflection this is defensible and should not be flagged.
- **Severity**: *(withdrawn — within approved clinical dose range)*

### Naltrexone
- **Route / Field**: oral / half-life
- **Shown**: half-life 4h
- **Expected**: ~4h for parent compound, but the active metabolite 6-β-naltrexol has a half-life of ~13h and drives the sustained 24–72h clinical duration. Displaying 4h would cause the app's PK curve to decay far too rapidly, showing "no drug remaining" many hours before the opioid-blocking effect actually ends. This is clinically meaningful because patients using low-dose naltrexone need to know the true duration of blockade.
- **Severity**: MAJOR — the displayed 4h half-life will produce a PK curve showing near-zero drug by 20–24h, while actual receptor occupancy (via 6-β-naltrexol) persists 48–72h; a patient might incorrectly conclude blockade has ended
