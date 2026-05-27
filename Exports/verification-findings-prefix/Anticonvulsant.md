# Anticonvulsant — Verification Findings

### Epidiolex
- **Route / Field**: oral / all dose tiers
- **Shown**: threshold 2.5, light 2.5–5 mg, common 5–10 mg, strong 10–20 mg, heavy ≥20 mg
- **Expected**: Starting dose ~175 mg/day for a 70 kg adult (2.5 mg/kg/day); maintenance 5–20 mg/kg/day = ~350–1400 mg/day at 70 kg. Common adult clinical dose is 200–600 mg/day. Shown values appear to be per-kg dose figures mistakenly treated as absolute mg totals, making them ~50–100× too low.
- **Severity**: BLOCKER — heavy ≥20 mg is far below even the starting clinical dose; a user tracking doses against these ranges will think any real therapeutic dose is "overdose" territory.

### Fenfluramine
- **Route / Field**: oral / threshold (only dose tier present)
- **Shown**: threshold 0.1 (no range, no other tiers; unit presumably mg)
- **Expected**: Fintepla (fenfluramine for Dravet syndrome) is dosed at 0.1–0.7 mg/kg/day, with a hard cap of 26 mg/day. For a 60–70 kg adult that is ~6–17 mg/day at common therapeutic levels. A threshold of 0.1 mg total is implausibly low; typical minimum meaningful dose is ~2–3 mg. The entry also lacks light/common/strong/heavy tiers entirely, making it nearly useless.
- **Severity**: MAJOR — 0.1 mg threshold is ~20–50× below the lowest practical therapeutic dose; missing tiers prevent any meaningful dose context.

### Levetiracetam
- **Route / Field**: oral / heavy dose
- **Shown**: heavy ≥4000 mg
- **Expected**: Maximum approved dose is 3000 mg/day (1500 mg BID). Values above 3000 mg/day enter the range associated with acute toxicity (somnolence, agitation, respiratory depression in overdose). Heavy should be ≥3000 mg to flag doses at or above the clinical ceiling.
- **Severity**: MAJOR — places the heavy marker 33% above the approved maximum, implying 3000–3999 mg is merely "strong" when it is already at or beyond the safety ceiling.

### Mirogabalin
- **Route / Field**: oral / strong and heavy dose
- **Shown**: strong 30–40 mg, heavy ≥40 mg
- **Expected**: Maximum approved dose (Japan; neuropathic pain) is 30 mg/day (15 mg BID). Any dose above 30 mg/day exceeds the approved maximum. Strong should cap at or near 30 mg; heavy at ≥30 mg.
- **Severity**: MAJOR — strong tier extends into and above the approved maximum without flagging it; heavy ≥40 mg normalises a supratherapeutic dose.

### Perampanel
- **Route / Field**: oral / total duration
- **Shown**: total 96h (4 days)
- **Expected**: Perampanel has a long half-life (~105h) but the subjective effect window of a single dose is not 4 days. Single-dose Tmax is 0.5–2.5h; acute CNS effects (sedation, dizziness) typically resolve within 12–24h after a dose as redistribution occurs. Total subjective duration for a single dose is approximately 12–24h; the 96h figure conflates half-life with subjective experience duration.
- **Severity**: MAJOR — a user could believe effects persist for 4 days per dose and dangerously mistime re-administration or other drug use around it.

### Zonisamide
- **Route / Field**: oral / total duration
- **Shown**: total 48h–96h
- **Expected**: Zonisamide half-life is ~63h, but acute subjective effects from a single dose resolve well within 12–24h. Total subjective duration for a single dose is approximately 12–24h. The 48–96h figure confuses pharmacokinetic half-life with experiential duration.
- **Severity**: MAJOR — same conflation issue as perampanel; a user seeing "effects last 2–4 days" per dose will severely misunderstand dosing behaviour.
