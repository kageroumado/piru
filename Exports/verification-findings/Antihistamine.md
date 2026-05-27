# Antihistamine Verification Findings

### Atropine
- **Route / Field**: oral / common dose
- **Shown**: common 2–5 mg
- **Expected**: ~0.4–1 mg. Therapeutic oral atropine is 0.4–0.6 mg per dose; 2–5 mg is the range associated with frank anticholinergic toxidrome (agitated delirium, hyperthermia, urinary retention, tachycardia). Listing this as *common* could cause users to self-administer at toxic levels.
- **Severity**: BLOCKER

### Ibotenic acid
- **Route / Field**: oral / common dose
- **Shown**: common 50–100 mg (isolated compound)
- **Expected**: ~5–15 mg at most for isolated ibotenic acid. Community psychonautic use of Amanita muscaria involves grams of dried mushroom with variable ibotenic acid content (~0.1–0.5% by dry weight); extrapolating to isolated ibotenic acid, 50–100 mg is a severe overdose range with excitotoxic neurotoxicity risk. Erowid and PsychonautWiki do not have human dose data at this level because it is not safely used as an isolated compound at these quantities.
- **Severity**: MAJOR

### Nizatidine
- **Route / Field**: oral / strong vs heavy boundary
- **Shown**: strong 300 mg, heavy ≥300 mg (identical cutoff)
- **Expected**: strong and heavy should have distinct thresholds. With nizatidine's maximum clinical dose being 300 mg/day, a reasonable split might be strong 300 mg / heavy ≥450–600 mg, or the strong upper bound should be below 300 mg. As-is, a dose of exactly 300 mg is simultaneously "strong" and "heavy," which is a logic error in the dose tier schema.
- **Severity**: MINOR

### Diphenhydramine
- **Route / Field**: oral / heavy threshold
- **Shown**: heavy ≥300 mg
- **Expected**: ≥500–700 mg. TripSit lists heavy at ≥500 mg and "strong" at 200–500 mg. PsychonautWiki places heavy at ≥700 mg. At 300 mg many users are at the lower recreational threshold, not a "heavy" dose by community consensus. This could cause under-caution in users redosing.
- **Severity**: MAJOR
