# Stimulant_04 Verification Findings

### Phentermine
- **Route / Field**: oral / onset duration
- **Shown**: onset 4h–6h
- **Expected**: onset 30m–2h. Phentermine is a well-studied prescription anorectic; clinical pharmacology data (FDA label, Adipex-P PI) documents Tmax ~3–4h for absorption but subjective stimulant onset occurs within 30–60 minutes of absorption beginning, and "onset" as used in harm-reduction contexts refers to when effects are first felt, not Tmax. A 4–6h onset is implausible for an oral stimulant with rapid GI absorption.
- **Severity**: MAJOR

### Pseudoephedrine
- **Route / Field**: oral / total duration
- **Shown**: total 2h–12h
- **Expected**: total 4h–8h (IR formulation). Standard IR pseudoephedrine has a half-life of ~5–8h and documented effect duration of 4–6h. The lower bound of 2h is implausibly short; the upper bound of 12h is plausible only for extended-release (12h ER tablets) but the range spanning 2h–12h conflates IR and ER kinetics into a single incoherent range.
- **Severity**: MAJOR

### Troparil
- **Route / Field**: oral / total duration
- **Shown**: total 45m–1.16667h
- **Expected**: total 1h–3h. Troparil (WIN 35,065-2) is a phenyltropane dopamine reuptake inhibitor. The "1.16667h" value is a raw floating-point artifact (70 minutes expressed as a fraction) that should be rendered as "1h 10m" or "~1.2h". Additionally, 45 minutes to ~70 minutes is on the short end; community reports suggest 1–2h duration, though literature is thin. The formatting issue is definitive.
- **Severity**: MAJOR (rendering bug producing "1.16667h" is a display error that will confuse users)

### Vyvanse
- **Route / Field**: oral / strong dose
- **Shown**: strong 50–100 mg
- **Expected**: strong 50–70 mg; heavy ≥70 mg. Vyvanse (lisdexamfetamine) FDA-approved maximum dose is 70 mg/day. Classifying 70–100 mg as merely "strong" without a "heavy" ceiling normalizes supratherapeutic dosing that significantly elevates cardiovascular risk. The range should cap strong at 70 mg and flag ≥70 mg as heavy.
- **Severity**: BLOCKER (100 mg lisdexamfetamine is ~2.9× the maximum approved dose; presenting it as "strong" without heavy designation understates risk)
