### PMA (para-Methoxyamphetamine)
- **Route / Field**: oral / common dose
- **Shown**: common 40–60 mg
- **Expected**: common dose should not exceed ~50 mg max with strong caution; the LD50 in humans is estimated around 60–100 mg, with confirmed fatalities at doses as low as 50 mg. Displaying 40–60 mg as "common" normalises a dose that sits at or within the lethal range.
- **Severity**: BLOCKER (lethal dose overlap — PMA has an extremely narrow therapeutic margin; "common 60 mg" is within the reported fatal dose range)

### PMMA (para-Methoxymethamphetamine)
- **Route / Field**: oral / common dose
- **Shown**: common 100–120 mg
- **Expected**: PMMA is significantly more toxic than MDMA with a very narrow safety margin. Reported fatalities occur in the 100–150 mg range. Displaying 100–120 mg as "common" normalises a dose within the known lethal range. No "light" or "threshold" tier is shown, which further removes harm-reduction context.
- **Severity**: BLOCKER (doses in the displayed "common" range have caused deaths; no lower tiers shown to anchor context)

### MDMA
- **Route / Field**: insufflation / onset duration
- **Shown**: onset 20m–1.16667h
- **Expected**: onset 20m–60m (i.e., 1h). The value "1.16667h" is a floating-point artefact (70 minutes expressed as 70/60 hours). It should be rendered as "1h 10m" or clamped to "1h". The raw float leaks into the displayed value.
- **Severity**: MAJOR (display artefact; the fractional hour value is nonsensical in a user-facing context and undermines trust in the data)

### MDPV (Methylenedioxypyrovalerone)
- **Route / Field**: oral / peak duration
- **Shown**: peak 1h–4h
- **Expected**: peak ~30m–1.5h. MDPV is a potent cathinone with a notably short, intense peak. Community reports and case literature consistently describe the peak as under 2 hours orally. A 4-hour upper bound for peak (distinct from total duration) is implausibly long.
- **Severity**: MAJOR (overstates peak duration ~2–3×, which may give users a false sense of safety regarding redosing timing)

### Mephedrone
- **Route / Field**: oral / peak duration
- **Shown**: peak 2h–4h
- **Expected**: peak ~1h–2h. Clinical reports and harm-reduction literature (including the EMCDDA mephedrone assessment) describe the oral peak as approximately 1–2 hours, not 4 hours. A 4-hour upper bound is 2× the commonly reported maximum.
- **Severity**: MAJOR (overstates peak duration; could mislead users on redosing interval)
