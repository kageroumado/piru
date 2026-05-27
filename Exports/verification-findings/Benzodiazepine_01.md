### Brotizolam
- **Route / Field**: oral / threshold
- **Shown**: threshold 80 (units shown as µg in context, so 80 µg)
- **Expected**: ~125–250 µg threshold; the listing of "light 100 µg" with "threshold 80" is internally inconsistent — threshold must be ≤ light dose lower bound, and 80 µg is plausible but barely. The real issue is the light dose: "light 100 µg" is a single point rather than a range, which is atypical formatting and suspicious. However the common dose of 200–400 µg is consistent with TripSit and the [also: drug.community: common 0.125–0.25 mg] aligns. The threshold/light formatting looks malformed (light should be a range).
- **Severity**: MINOR

### Cloniprazepam
- **Route / Field**: oral / dose range ordering
- **Shown**: light 1–5 mg, common 1–2 mg
- **Expected**: Light range (1–5 mg) overlaps and exceeds the common range (1–2 mg), which is pharmacologically inverted — common should be ≥ light lower bound and the upper bound of common should not be lower than the upper bound of light. The light upper bound of 5 mg is almost certainly the strong or heavy threshold for this potent nitro-benzodiazepine analogue. Literature suggests cloniprazepam is highly potent; common recreational doses around 1–2 mg and light starting around 0.5–1 mg.
- **Severity**: MAJOR

### Deschloroetizolam
- **Route / Field**: oral / common dose (piru-curated winning value)
- **Shown**: common 4–8 mg
- **Expected**: ~1–2 mg; drug.community lists common 1–2 mg (shown as [also:]). Deschloroetizolam is a thienodiazepine close in potency to etizolam. Etizolam common is 1–2 mg. A common dose of 4–8 mg for deschloroetizolam would be 2–4× the etizolam-equivalent, which is implausibly high given their structural similarity and community reports consistently clustering around 1–4 mg total. 8 mg as common upper bound approaches heavy territory and respiratory depression risk.
- **Severity**: BLOCKER

### Flubromazepam
- **Route / Field**: oral / common dose (piru-curated winning value)
- **Shown**: common 4–8 mg
- **Expected**: ~2–4 mg; drug.community lists common 1–4 mg (shown as [also:]). Flubromazepam is a long-acting (half-life ~106 h) benzodiazepine with significant potency. PsychonautWiki and community reports place common around 2–8 mg, but the lower end of that is more representative for naive users given the extreme half-life and accumulation risk. 8 mg as common upper bound is at the high end and with 106 h half-life creates serious accumulation risk if users treat it as a regular common dose. The [also: drug.community: common 1–4 mg] is the more conservative and appropriate anchor.
- **Severity**: MAJOR

### Flunitrazolam
- **Route / Field**: oral / common dose
- **Shown**: common 0.2–0.3 mg (psychonautwiki)
- **Expected**: ~80–250 µg (0.08–0.25 mg); TripSit lists common 80–150 µg. Flunitrazolam is an extremely potent fluorinated nitro-triazolobenzodiazepine — one of the most potent in this class, with activity at sub-100 µg doses. A common upper bound of 0.3 mg (300 µg) is 2–4× what harm-reduction sources consider common and approaches heavy/blackout territory for most users.
- **Severity**: BLOCKER

### Midazolam
- **Route / Field**: insufflation / total duration
- **Shown**: total 4h–8h
- **Expected**: ~45m–2h; midazolam has a half-life of 1–4 hours and is specifically noted for its ultra-short duration of action (used clinically for procedural sedation precisely because it wears off in 1–2 hours). Intranasal bioavailability is high (~80%) and onset is fast, but total duration of 4–8 hours is 2–4× the expected window and could lead users to redose prematurely when the drug is still significantly active.
- **Severity**: MAJOR

### Midazolam
- **Route / Field**: intramuscular / total duration
- **Shown**: total 4h–8h
- **Expected**: ~1–3h; same reasoning as insufflation — midazolam IM onset is 5–15 min, duration is typically 1–2 hours clinically. 4–8 h is grossly overestimated.
- **Severity**: MAJOR

### Nifoxipam
- **Route / Field**: oral / total duration
- **Shown**: total 10h–75h
- **Expected**: 10–20h upper bound is plausible given nifoxipam's reported half-life (~25–40 h), but 75 hours as the upper total duration bound is extreme and likely represents residual impairment/afterglow being conflated with the primary effect window. A 75-hour duration listed as "total" without qualification as afterglow could mislead users into thinking subjective effects last over 3 days.
- **Severity**: MAJOR

### Norflurazepam
- **Route / Field**: oral / common dose
- **Shown**: common 4–8 mg
- **Expected**: ~1–3 mg; norflurazepam is the active metabolite of flurazepam and has a half-life of ~75 hours (confirmed in the data). It is pharmacologically active at 1–2 mg. A common dose of 4–8 mg with this half-life creates serious accumulation risk over repeated dosing and 8 mg approaches heavy territory.
- **Severity**: BLOCKER
