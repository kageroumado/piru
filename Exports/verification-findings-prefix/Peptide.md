# Peptide — Verification Findings

### DSIP
- **Route / Field**: subcutaneous / half-life
- **Shown**: 4 minutes
- **Expected**: ~20–30 minutes — DSIP (delta sleep-inducing peptide) is a small nonapeptide that is rapidly cleared, but published pharmacokinetic data in humans put the terminal half-life at approximately 20–30 min following i.v. administration; 4 min would be more consistent with a distribution half-life (alpha phase), not the terminal half-life typically reported.
- **Severity**: MAJOR

### Epitalon
- **Route / Field**: subcutaneous / duration — offset and total
- **Shown**: offset 48h–168h, total 72h–168h
- **Expected**: offset ~4h–24h, total ~8h–48h — Epitalon (Ala-Glu-Asp-Gly) is a tetrapeptide with a half-life of ~30 min (correctly listed). A 48–168 h offset window is physiologically inconsistent with a peptide that is essentially cleared within a few hours. The extended offset likely conflates downstream biological effects (e.g., telomerase induction) with pharmacodynamic duration, which is inappropriate for a dose-tracking context where offset should reflect subjective/observable effects waning.
- **Severity**: MAJOR

### Semaglutide (oral)
- **Route / Field**: oral / common dose
- **Shown**: 7–14 mg
- **Expected**: 7–14 mg is correct for the Rybelsus (oral semaglutide) approved maintenance dose range. No flag.

### Semaglutide (oral)
- **Route / Field**: oral / strong and heavy doses
- **Shown**: strong 14–25 mg, heavy ≥25 mg
- **Expected**: Max approved oral dose is 14 mg/day (Rybelsus). Doses above 14 mg oral have not been studied for safety/efficacy; 25 mg+ is suprapharmacological and there is no published human data supporting these as a "strong" recreational/therapeutic tier. For a harm-reduction app, listing ≥25 mg as merely "heavy" without a blocker flag understates risk.
- **Severity**: BLOCKER

### Retatrutide
- **Route / Field**: subcutaneous / common dose
- **Shown**: 4–8 mg
- **Expected**: ~2–4 mg — Phase 2 trials used weekly doses of 1 mg, 4 mg, 8 mg, and 12 mg; the 4 mg weekly dose was the lower mid-range exploratory arm. Listing 4–8 mg as "common" implies this is a typical starting/maintenance range, but most participants began at 1–2 mg with titration. A "common" dose for a weekly GLP-1/GIP/glucagon triple agonist in clinical context is closer to 2–4 mg; 8 mg is near the high end of studied doses.
- **Severity**: MINOR

### Tesamorelin
- **Route / Field**: subcutaneous / strong and heavy doses
- **Shown**: strong 2 mg, heavy ≥2 mg
- **Expected**: The FDA-approved dose of tesamorelin (Egrifta) is 2 mg/day subcutaneous — this is the single approved dose. Listing it simultaneously as both "strong" and the threshold for "heavy" means the clinically standard dose is classified as strong/heavy, which is misleading and may discourage appropriate use or encourage users to under-dose to stay in a "light" tier. Light should be 1 mg, common 2 mg, strong/heavy would be speculative above 2 mg.
- **Severity**: MAJOR

### Melanotan II
- **Route / Field**: subcutaneous / heavy dose threshold
- **Shown**: heavy ≥2 mg
- **Expected**: ≥1.5 mg — Community harm-reduction sources (e.g., Eroids, Reddit peptide communities) consistently note that doses above 1–1.5 mg produce pronounced nausea, facial flushing, spontaneous erections, and cardiovascular effects in most users. Setting "heavy" at ≥2 mg may normalize doses that carry meaningful adverse effect burden for most individuals. Some sources put 1 mg as already a strong/borderline dose for naive users.
- **Severity**: MINOR

### CJC-1295
- **Route / Field**: subcutaneous / half-life
- **Shown**: 168 hours (7 days)
- **Expected**: CJC-1295 with DAC (drug affinity complex): ~6–8 days half-life is correct. CJC-1295 without DAC: ~30 minutes. The entry does not specify DAC vs. no-DAC, but 168h corresponds to the DAC formulation. If this entry covers both forms, the half-life should clarify the distinction, since the two are not interchangeable in dosing interval. As a data accuracy flag: 168h is only correct for the DAC form.
- **Severity**: MINOR
