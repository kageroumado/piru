

================================================================================
# AMPAkine
================================================================================

No findings.

================================================================================
# Analgesic
================================================================================

No findings.


================================================================================
# Anticonvulsant
================================================================================

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


================================================================================
# Antidepressant
================================================================================

# Antidepressant — Verification Findings

### Doxepin
- **Route / Field**: oral / dose tier continuity
- **Shown**: threshold 3, light 3–10 mg, common 75–150 mg (gap of 10–75 mg is unrepresented)
- **Expected**: Light should extend toward ~25–50 mg or an intermediate tier should exist; the 65 mg gap between the top of "light" (10 mg) and the bottom of "common" (75 mg) means every dose in the 10–75 mg range is unclassified. A user logging 30 mg sees no tier.
- **Severity**: MAJOR

### Milnacipran
- **Route / Field**: oral / strong and heavy overlap
- **Shown**: strong 200 mg (single point), heavy ≥200 mg — both start at 200 mg, strong has zero width
- **Expected**: strong should span a range below heavy, e.g. strong 150–200 mg, heavy ≥200 mg; or strong 200–250 mg, heavy ≥250 mg. As written, "strong" is a degenerate tier.
- **Severity**: MAJOR

### Desvenlafaxine
- **Route / Field**: oral / heavy threshold
- **Shown**: strong 50–100 mg, heavy ≥400 mg (gap of 100–400 mg is unrepresented)
- **Expected**: heavy should begin where strong ends, ≥100 mg. The 300 mg gap means doses from 100–399 mg show no tier. The FDA-approved dose is 50 mg/day; doses above 100 mg are off-label and should still be classifiable.
- **Severity**: MAJOR

### Fluoxetine
- **Route / Field**: oral / half-life
- **Shown**: 384h (16 days)
- **Expected**: ~96–144h (4–6 days) for the combined parent+norfluoxetine effective half-life as used clinically. 384h is the extreme upper bound of norfluoxetine in ultra-slow CYP2D6 metabolizers; using it as the single stated half-life will cause the app's PK curves and active-substance calculations to show fluoxetine as active for weeks past when it is practically relevant for nearly all users.
- **Severity**: MAJOR

### Tianeptine
- **Route / Field**: oral / common dose
- **Shown**: common 25–50 mg
- **Expected**: common ~12.5–37.5 mg (the standard therapeutic regimen is 12.5 mg three times daily = 37.5 mg/day total). The lower bound of 25 mg is above the standard single dose (12.5 mg) and the upper bound of 50 mg exceeds the standard total daily dose. If the field is per-dose, 25–50 mg is substantially above therapeutic; if per-day, the lower bound should start at 37.5 mg. Either way the range is shifted high relative to the clinical standard.
- **Severity**: MAJOR

### Tianeptine sodium
- **Route / Field**: oral / heavy dose
- **Shown**: heavy ≥100 mg
- **Expected**: ≥75 mg is where opioid-like abuse and dependency risk becomes clinically significant for tianeptine sodium. The standard maximum therapeutic daily dose is 37.5 mg; 100 mg/day represents approximately 2.7× the therapeutic ceiling and is well into abuse/toxicity territory. For harm-reduction purposes, heavy should arguably start at ≥50–75 mg to flag this risk zone sooner.
- **Severity**: MINOR

### Selegiline
- **Route / Field**: oral / strong and heavy overlap
- **Shown**: strong 10 mg (single point), heavy ≥10 mg — identical threshold, zero-width strong tier
- **Expected**: strong should span a range, e.g. strong 10–15 mg; heavy ≥15 mg. Additionally, oral selegiline >10 mg/day loses MAO-B selectivity and becomes a non-selective MAOI, requiring tyramine dietary restriction — this pharmacological threshold at 10 mg makes the zero-width strong tier particularly confusing.
- **Severity**: MAJOR

### Tranylcypromine
- **Route / Field**: oral / strong and heavy overlap
- **Shown**: strong 60 mg (single point), heavy ≥60 mg — identical threshold, zero-width strong tier
- **Expected**: strong should span a range, e.g. strong 60–80 mg, heavy ≥80 mg (max recommended dose is 60 mg/day for maintenance, with some sources citing up to 90 mg under supervision).
- **Severity**: MAJOR


================================================================================
# Antihistamine
================================================================================

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


================================================================================
# Antimicrobial
================================================================================

No findings.

================================================================================
# Antipsychotic
================================================================================

# Antipsychotic Verification Findings

### Aripiprazole
- **Route / Field**: intramuscular / threshold vs light dose ordering
- **Shown**: threshold 400 mg, light 300–400 mg
- **Expected**: threshold should be below the light range floor; here threshold (400) equals or exceeds the top of the light range (400) while the light range bottom (300) is below threshold — the dose tiers are inverted. For the Abilify Maintena depot, 400 mg is the standard dose and 300 mg is the lower approved dose; threshold should be ≤300 mg or the light range should start at 400 mg.
- **Severity**: MAJOR

### Cariprazine
- **Route / Field**: half-life
- **Shown**: 1200h (~50 days)
- **Expected**: ~91–504h (4–21 days). Cariprazine's primary active metabolite DDCAR has a half-life of approximately 1–3 weeks (168–504h). 1200h (50 days) is 2–3× too long and not supported by the prescribing information or published PK studies.
- **Severity**: MAJOR

### Quetiapine
- **Route / Field**: oral / common dose
- **Shown**: 150–750 mg
- **Expected**: common dose range of 150–400 mg (antipsychotic indication) or 50–150 mg (sedation/augmentation, which is the predominant recreational/tracking use case). A 5× span (150–750 mg) spanning from low therapeutic to near-maximum daily dose makes "common" meaningless and conflates multiple distinct indications. The PsychonautWiki value (50–150 mg) and TripSit value (50 mg) both flag this discrepancy.
- **Severity**: MAJOR

### Quetiapine
- **Route / Field**: oral / strong and heavy dose
- **Shown**: strong 750–800 mg, heavy ≥800 mg
- **Expected**: strong ≥400–600 mg, heavy ≥800 mg. Since common extends to 750 mg, the "strong" band is only 50 mg wide (750–800). This leaves effectively no daylight between common and heavy, making the strong tier pharmacologically uninformative.
- **Severity**: MINOR

### Pimavanserin
- **Route / Field**: oral / strong and heavy dose
- **Shown**: strong 34 mg, heavy ≥34 mg
- **Expected**: Pimavanserin is a fixed-dose drug (34 mg/day is the sole approved dose). Having strong = 34 mg and heavy = ≥34 mg means the standard therapeutic dose is simultaneously labeled "strong" and the floor of "heavy." Users seeing their prescribed dose flagged as heavy/strong could be alarmed without cause, or conversely could misinterpret the label. There is no meaningful supertherapeutic range to distinguish strong from heavy here; at minimum heavy should be ≥68 mg (2× standard dose).
- **Severity**: MINOR

### Paliperidone
- **Route / Field**: oral / total duration
- **Shown**: 96–192h (4–8 days)
- **Expected**: ~24–36h. Oral paliperidone (Invega) is a once-daily formulation with a half-life of ~23h. Per-dose duration should be approximately 24h. 4–8 days reflects steady-state accumulation over a dosing regimen, not the duration of effect of a single oral dose, and would mislead users about how long a single dose lasts.
- **Severity**: MAJOR


================================================================================
# Benzodiazepine_01
================================================================================

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


================================================================================
# Benzodiazepine_02
================================================================================

### Rilmazafone
- **Route / Field**: oral / dose tier ordering (light vs common)
- **Shown**: light 1–5 mg, common 1–2 mg
- **Expected**: light ceiling should be below common floor; common should exceed light (e.g., light 1–2 mg, common 2–4 mg or similar). As listed, the light range (up to 5 mg) wholly contains and exceeds the common range (up to 2 mg), making the tier ordering pharmacologically incoherent.
- **Severity**: BLOCKER — a user following the "common" label would stop at 2 mg while the "light" tier extends to 5 mg; the tier hierarchy is inverted and will confuse safe-dosing decisions.

### Triazolam
- **Route / Field**: oral / total duration (missing)
- **Shown**: onset 10–20 min, afterglow 1–6 h — no peak, offset, or total duration listed
- **Expected**: total duration ~2–6 h (half-life 1.5–5 h; consistent with TripSit and PsychonautWiki which show ~2–5 h effects). Absence of a total duration value leaves the timeline graph with no upper bound, which could cause users to redose a drug with unpredictable potency.
- **Severity**: MAJOR — missing total duration for a high-potency, short-acting benzo is clinically relevant; users may interpret lack of a total as "still active" or "unknown" and redose unsafely.


================================================================================
# Cannabinoid
================================================================================

# Cannabinoid Verification Findings

### ADB-INACA
- **Route / Field**: inhalation / total duration
- **Shown**: 60h–180h
- **Expected**: 0.5h–3h. Synthetic cannabinoid inhalation effects resolve within 30 minutes to a few hours; no inhaled SC has a 2.5–7.5 day duration. This value is clearly a data error (likely minutes-to-hours was entered as hours, or hours were confused with days).
- **Severity**: BLOCKER — users would not redose for days, but the displayed duration is so absurd it undermines trust and could confuse harm-reduction decisions.

---

### ADB-PINACA
- **Route / Field**: inhalation / total duration
- **Shown**: 60h–180h
- **Expected**: 0.5h–3h. Same issue as ADB-INACA inhalation; synthetic cannabinoids inhaled last under 3 hours in virtually all documented cases.
- **Severity**: BLOCKER

- **Route / Field**: oral / total duration
- **Shown**: 120h–240h
- **Expected**: 3h–8h. Five to ten days of duration for an oral synthetic cannabinoid is pharmacologically impossible. Even long-acting cannabinoids (e.g., cannabis edibles with THC half-life ~30h) produce subjective effects for 8–12 hours at most.
- **Severity**: BLOCKER

---

### AM-2201
- **Route / Field**: oral / total duration
- **Shown**: 60h–180h
- **Expected**: 3h–6h. AM-2201 has a short elimination half-life (~1.8h for its major metabolite); oral effects would last a few hours, not 2.5–7.5 days. Same category error seen in ADB-INACA/ADB-PINACA.
- **Severity**: BLOCKER

---

### CB-13
- **Route / Field**: inhalation / common dose
- **Shown**: 15–30 mg
- **Expected**: ~0.5–3 mg. CB-13 (cannabilactone) is a high-affinity CB1/CB2 agonist (Ki ~0.45 nM at CB1, ~3.4 nM at CB2) — roughly equipotent to JWH-018 or more potent. Common inhaled doses for compounds in this potency class are measured in low milligrams. 15–30 mg inhaled would represent a severe overdose risk.
- **Severity**: BLOCKER

- **Route / Field**: oral / common dose
- **Shown**: 150–300 mg
- **Expected**: 5–20 mg. Even accounting for poor oral bioavailability, 150–300 mg of a high-affinity CB1 agonist taken orally is dangerous. No harm-reduction source documents human oral doses of CB-13 in this range; these values appear to be placeholders scaled from inactive cannabinoids like CBC.
- **Severity**: BLOCKER

---

### Nabilone
- **Route / Field**: oral / half-life
- **Shown**: 2h
- **Expected**: ~35h effective (parent ~2h, but active metabolites have t½ ≈ 35h). Nabilone's parent compound has a ~2h half-life, but it undergoes extensive hepatic metabolism to active metabolites with half-lives of 35+ hours — which is why its clinical dosing interval is 8–12 hours and accumulation is a known concern. Displaying 2h will lead users to believe the drug clears quickly and redose unsafely.
- **Severity**: BLOCKER

---

### JWH-018
- **Route / Field**: inhalation / dose tier boundary
- **Shown**: strong 5–8 mg, heavy ≥10 mg
- **Expected**: heavy ≥8 mg. There is an unexplained gap between the strong ceiling (8 mg) and heavy threshold (10 mg) — 8–10 mg is in a dead zone with no tier. The heavy threshold should start where strong ends.
- **Severity**: MINOR


================================================================================
# Cardiovascular
================================================================================

# Cardiovascular — Verification Findings

### Propranolol
- **Route / Field**: intravenous / strong and heavy dose thresholds
- **Shown**: strong 10–20 mg, heavy ≥20 mg
- **Expected**: strong ≤5–7 mg, heavy ≥10 mg — IV propranolol maximum is 0.1 mg/kg (≈7 mg for a 70 kg adult) for arrhythmia management; 10–20 mg IV would cause severe bradycardia, hypotension, and cardiac arrest risk. Standard IV dose is 0.5–3 mg given slowly; a cumulative ceiling of ~10 mg is an absolute limit under resuscitative conditions, not a "strong" recreational tier.
- **Severity**: BLOCKER (could harm user)


================================================================================
# Depressant_01
================================================================================

# Depressant_01 Verification Findings

### Allobarbital
- **Route / Field**: oral / common dose and strong dose
- **Shown**: common 1000–1500 mg, strong 1500–2000 mg
- **Expected**: common ~100–200 mg, strong ~200–400 mg. Allobarbital's historical therapeutic/hypnotic dose was 100–200 mg; 1000–2000 mg is well into the lethal range for any barbiturate.
- **Severity**: BLOCKER

### Gaboxadol
- **Route / Field**: oral / offset and total duration
- **Shown**: offset 1m–3m, total 2m–5m
- **Expected**: offset ~1h–3h, total ~2h–5h. All other phase durations (onset 15m–1h, peak 1h–2h) are in hours; offset and total have clearly been entered as minutes instead of hours.
- **Severity**: BLOCKER

### Hexobarbital
- **Route / Field**: oral / all dose tiers
- **Shown**: light 10–15 mg, common 15–20 mg, strong 20–30 mg
- **Expected**: light ~100–200 mg, common ~200–400 mg, strong ~400–600 mg. Oral hypnotic dose of hexobarbital was historically 250–500 mg. The 10–30 mg range reflects IV anesthetic induction doses, not oral use. A user dosing 15 mg orally would feel nothing.
- **Severity**: MAJOR

### Marinol (Dronabinol)
- **Route / Field**: oral / common and strong dose
- **Shown**: common 20–30 mg, strong 30–50 mg
- **Expected**: common ~5–15 mg, strong ~15–25 mg. FDA-approved therapeutic doses are 2.5–20 mg. Recreational use community reports suggest 10–20 mg as a strong experience. 30–50 mg is an extreme dose associated with significant adverse effects (paranoia, tachycardia, dysphoria) in opioid-naive individuals; presenting it as merely "strong" understates the risk.
- **Severity**: MAJOR

### Mephenaqualone
- **Route / Field**: oral / offset and total duration
- **Shown**: offset 10h–15h, total 15h–20h
- **Expected**: offset ~2h–4h, total ~4h–8h. Methaqualone analogs have half-lives in the range of 10–40 hours, but the active experiential duration is typically 4–8 hours. A 15–20 hour total duration would imply residual effects lasting the better part of a day, which is not consistent with community reports or the pharmacology of quaalude-class sedatives.
- **Severity**: MAJOR


================================================================================
# Depressant_02
================================================================================

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


================================================================================
# Dissociative_01
================================================================================

# Dissociative_01 Verification Findings

### 2-MeO-Ketamine
- **Route / Field**: insufflation / total duration AND intramuscular / total duration AND oral / total duration
- **Shown**: insufflation 60h–150h, IM 60h–150h, oral 90h–180h
- **Expected**: insufflation ~1–3h, IM ~45m–2h, oral ~2–4h — no ketamine analog has multi-day duration; values appear to be a unit error (minutes interpreted as hours, or decimal place shift). Even the longest-acting NMDA antagonists (memantine) plateau at ~24h.
- **Severity**: BLOCKER (multi-day duration displayed for a short-acting dissociative would completely misrepresent active window and re-dose risk)

---

### Deschloroketamine
- **Route / Field**: insufflation / common dose
- **Shown**: 40–100 mg (piru-curated)
- **Expected**: 15–25 mg — PsychonautWiki and drug.community independently agree on 15–25 mg. DCK is substantially more potent than ketamine; 40–100 mg insufflated is well into heavy/hole territory by community consensus. The winning source is ~3–4× above two independent references.
- **Severity**: BLOCKER (significantly overstated common dose for a potent dissociative could lead users to dose into a k-hole believing it is a moderate experience)

---

### Deschloroketamine
- **Route / Field**: oral / common dose
- **Shown**: 75–200 mg (piru-curated)
- **Expected**: 15–30 mg — three independent sources (PsychonautWiki 20–30 mg, TripSit 15–25 mg, drug.community 20–30 mg) cluster tightly at 15–30 mg oral. The winning value is ~5–7× the independent consensus for a substance known to be significantly more potent than ketamine.
- **Severity**: BLOCKER (a 5–7× overstatement of common oral dose for a potent NMDA antagonist represents serious harm potential)

---

### HXE
- **Route / Field**: insufflation / light dose
- **Shown**: light 40–20 mg (inverted range, lower bound > upper bound)
- **Expected**: light ~20–40 mg — the bounds are transposed; this is a data entry error.
- **Severity**: MAJOR (inverted range is nonsensical and will display incorrectly to users)

---

### Etoxadrol
- **Route / Field**: intravenous / total duration
- **Shown**: 14h–53h
- **Expected**: ~1–4h IV — etoxadrol was studied clinically as an IV anesthetic/analgesic in the 1970s–80s. Its duration of action intravenously is on the order of 1–4 hours. A 14–53h range is inconsistent with clinical pharmacology data and is implausibly wide (>3× spread).
- **Severity**: MAJOR (dramatically overstated duration for an IV-route substance misleads users about duration of impairment)


================================================================================
# Dissociative_02
================================================================================

### S-Ketamine
- **Route / Field**: insufflation / total duration
- **Shown**: 60h–120h
- **Expected**: ~45–90 min; S-ketamine (esketamine) insufflated has the same ~45–90 min pharmacodynamic window as racemic ketamine — the source value appears to have a unit error (hours instead of minutes).
- **Severity**: BLOCKER (could lead user to severely underestimate redosing risk or duration)

### S-Ketamine
- **Route / Field**: intravenous / total duration
- **Shown**: 45h–90h
- **Expected**: ~20–45 min; IV esketamine has a short half-life (~2–3 h) and dissociative effects resolve within 20–45 min. A value of 45–90 hours is implausible by 2–3 orders of magnitude.
- **Severity**: BLOCKER (could harm user)

### PCP
- **Route / Field**: oral / common dose
- **Shown**: 5–10 mg
- **Expected**: ~5–10 mg is at the upper end but within range for street PCP; however the threshold of 1 mg oral is far too low — community and clinical reports place oral threshold closer to 3–5 mg. A 1 mg oral threshold alongside a 5–10 mg common dose implies an unusually shallow dose-response curve.
- **Severity**: MAJOR (threshold value off ~3–5×, putting naïve users at risk of underestimating potency at threshold)

### Tiletamine
- **Route / Field**: intramuscular / afterglow duration
- **Shown**: 1h–72h
- **Expected**: tiletamine IM in veterinary use has a recovery time on the order of hours, not days; an afterglow extending to 72 h is inconsistent with its known pharmacokinetics (half-life ~3 h in most species). 1–8 h would be more appropriate.
- **Severity**: MAJOR (upper bound wildly inflated)


================================================================================
# Dysdelic
================================================================================

### Benzydamine

- **Route / Field**: oral / common dose
- **Shown**: common 500–1000 mg
- **Expected**: common ~300–500 mg. Benzydamine (Tantum Rosa / Difflam) recreational use is typically 300–600 mg; 500–1000 mg is the "strong" range and produces severe anticholinergic delirium. Having the *common* window start at 500 mg normalises a dose that causes dangerous toxicity in naive users.
- **Severity**: BLOCKER

- **Route / Field**: oral / strong dose
- **Shown**: strong 1000–2000 mg
- **Expected**: strong ~500–800 mg. Doses above 1 g are associated with seizures, severe tachycardia, and ICU admissions in case-series literature. Displaying 1000–2000 mg as merely "strong" understates the danger.
- **Severity**: BLOCKER

### Myristicin

- **Route / Field**: oral / common dose
- **Shown**: common 200–500 mg (pure myristicin)
- **Expected**: community consensus for pure myristicin is roughly 100–200 mg for a common experience. 200–500 mg pushes well into doses linked to severe anticholinergic/serotonergic toxicity (tachycardia, panic, psychosis) lasting 24–48 h. The `[also: drug.community: common 5–10 g nutmeg]` note shows the community source expresses the dose in whole nutmeg equivalents (~5 g nutmeg ≈ 40–100 mg myristicin), so the two figures are not in conflict on underlying dose — but the winning 200–500 mg figure is approximately 2–5× too high for "common."
- **Severity**: MAJOR

### Salvinorin A

- **Route / Field**: sublingual / heavy dose lower bound
- **Shown**: heavy ≥15 mg
- **Expected**: heavy ≥12 mg (consistent with the strong upper bound shown as 12 mg). The gap between strong (6–12 mg) and heavy (≥15 mg) leaves a 12–15 mg range unclassified, which is an internal inconsistency rather than a literature error, but could mislead users into thinking 13 mg is sub-heavy.
- **Severity**: MINOR


================================================================================
# Empathogen_01
================================================================================

# Verification Findings — Empathogen_01

## 4,4-Dmar
- **Route / Field**: oral / common dose
- **Shown**: common 60–120 mg
- **Expected**: common 20–40 mg. 4,4-DMAR caused a cluster of deaths in Europe (EMCDDA early-warning, 2013). Forensic toxicology places lethal and near-lethal exposures in the range shown as "common" here. The substance has extreme monoamine toxicity; community harm-reduction sources consistently place active doses well below 60 mg.
- **Severity**: BLOCKER

## 5-It
- **Route / Field**: oral / common dose
- **Shown**: common 50–100 mg
- **Expected**: common 15–25 mg. 5-IT (5-(2-aminopropyl)indole) caused multiple fatalities in Scandinavia (2012–2013); forensic case series implicate doses in the 50–100 mg range in cardiac arrest and hyperthermia deaths. Community harm-reduction literature places an active threshold around 10–15 mg and a cautious common dose of 15–25 mg.
- **Severity**: BLOCKER

## 3-Fea (insufflation)
- **Route / Field**: insufflation / strong dose range
- **Shown**: strong 50–60 mg (lower bound of strong is below the upper bound of common: common 35–60 mg, strong 50–60 mg — the ranges overlap and the strong upper bound equals the common upper bound)
- **Expected**: strong range should start at or above the top of the common range, e.g. strong 60–80 mg. As listed, "strong" and "common" are nearly indistinguishable and the strong ceiling seems truncated.
- **Severity**: MAJOR

## Dipentylone
- **Route / Field**: insufflation / dose tiers
- **Shown**: threshold 3, light 3–8 mg, [common and strong absent], heavy ≥50
- **Expected**: intermediate tiers (common ~10–25 mg, strong ~25–40 mg) are missing, leaving a ~6× jump from light to heavy with no guidance. This is a data-completeness gap that leaves users without dose escalation context for a potent cathinone.
- **Severity**: MAJOR

## Dipentylone
- **Route / Field**: oral / dose tiers
- **Shown**: threshold 5, [light/common/strong absent], heavy ≥80
- **Expected**: similar to insufflation — all intermediate tiers are missing. Users see only threshold and heavy, making safe dose titration impossible.
- **Severity**: MAJOR


================================================================================
# Empathogen_02
================================================================================

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


================================================================================
# Endocrine
================================================================================

### Estradiol
- **Route / Field**: intramuscular / total duration
- **Shown**: 7h–28h
- **Expected**: 4–14 days (96h–336h). Estradiol IM preparations (cypionate, valerate, benzoate) are depot injections with durations of several days to two weeks. Even the shortest-acting IM form (estradiol benzoate) lasts 2–3 days. 7–28 hours would only apply to IV administration, not IM depot injection.
- **Severity**: BLOCKER (a user logging IM estradiol would be told their dose wears off in under 30 hours, potentially prompting dangerous re-dosing far too soon)


================================================================================
# Eugeroic
================================================================================

### Adrafinil
- **Route / Field**: oral / common dose
- **Shown**: 600–900 mg (piru-curated)
- **Expected**: ~300–600 mg; both PsychonautWiki and TripSit (shown as `[also: …]`) agree on 250–400 mg as common, and the broader harm-reduction literature treats 600 mg as already a strong dose — the piru-curated value is roughly 2× the cross-source consensus.
- **Severity**: MAJOR


================================================================================
# GABAergic
================================================================================

# GABAergic — Verification Findings

### Gabapentin
- **Route / Field**: oral / common dose
- **Shown**: 900–1500 mg (psychonautwiki)
- **Expected**: 300–900 mg — drug.community's alternative aligns with actual recreational practice; most users reporting pleasant recreational effects are in the 300–900 mg range. The PsychonautWiki 900–1500 mg figure conflates tolerant heavy-use with "common," and displaying this as the winning common value significantly over-represents what a naive or occasional user would take. At 900–1500 mg, adverse effects (sedation, ataxia, cognitive impairment) are much more pronounced and risk of dangerous CNS depression with alcohol/opioids is meaningfully elevated.
- **Severity**: MAJOR

### Pregabalin
- **Route / Field**: oral / strong dose
- **Shown**: 600–900 mg (psychonautwiki)
- **Expected**: ≤600 mg — 600 mg is the maximum approved therapeutic daily dose. A single recreational dose of 600–900 mg substantially exceeds this, places users in territory with documented seizure risk (especially on abrupt discontinuation after repeated dosing), respiratory depression risk when combined with CNS depressants, and severe hypotension. Many recreational harm-reduction sources treat anything above 450–600 mg as heavy/dangerous, not merely "strong." Displaying 600–900 mg as the "strong" band normalizes a clinically serious dose.
- **Severity**: BLOCKER

### Pregabalin
- **Route / Field**: oral / heavy dose
- **Shown**: ≥900 mg (psychonautwiki)
- **Expected**: ≥600 mg — the heavy threshold should begin at or below 600 mg for an app context. 900 mg as the floor of "heavy" implies doses below 900 mg are sub-heavy, which contradicts clinical reality. This compounds the strong-dose issue above: users see 600–900 mg labelled "strong" (not "heavy/dangerous") and ≥900 mg as "heavy," suppressing risk perception across the entire upper range.
- **Severity**: BLOCKER


================================================================================
# Gastrointestinal
================================================================================

# Gastrointestinal — Verification Findings

### Droperidol
- **Route / Field**: intravenous / heavy dose
- **Shown**: heavy ≥10 mg
- **Expected**: heavy ≥5 mg. FDA boxed warning exists for QTc prolongation; clinical antiemetic IV doses rarely exceed 2.5 mg (PONV) or 5 mg (rescue). Labeling a ≥10 mg threshold as merely "heavy" understates risk and could encourage a dose that causes fatal arrhythmia.
- **Severity**: BLOCKER

### Metoclopramide
- **Route / Field**: oral / strong dose
- **Shown**: strong 20–40 mg
- **Expected**: strong ~15–20 mg. Standard single antiemetic dose is 10 mg; 20 mg is already at the high end for a single administration. Labeling 20–40 mg as merely "strong" understates tardive dyskinesia risk.
- **Severity**: MAJOR

### Metoclopramide
- **Route / Field**: oral / heavy dose
- **Shown**: heavy ≥60 mg
- **Expected**: heavy ≥20–30 mg. The FDA-approved maximum daily dose is 40 mg/day (short-term use). Labeling ≥60 mg as "heavy" (implying a single-dose landmark) is well above the entire daily ceiling and carries high EPS/tardive dyskinesia risk.
- **Severity**: BLOCKER

### Prochlorperazine
- **Route / Field**: oral / common dose
- **Shown**: common 10–20 mg
- **Expected**: common 5–10 mg. Standard single oral antiemetic dose is 5–10 mg q6–8h. A "common" range of 10–20 mg is 2× the typical single dose and approaches the single-dose ceiling for most guidelines.
- **Severity**: MAJOR

### Prochlorperazine
- **Route / Field**: oral / heavy dose
- **Shown**: heavy ≥40 mg
- **Expected**: heavy ≥25–30 mg. Many formularies cap single-dose oral prochlorperazine at 25 mg; ≥40 mg as a single dose risks severe EPS, NMS, and cardiovascular effects.
- **Severity**: BLOCKER


================================================================================
# Nootropic
================================================================================

# Nootropic Verification Findings

### Citicoline
- **Route / Field**: oral / total duration
- **Shown**: offset 30h–40h, total 58h–74h, afterglow 40h–60h
- **Expected**: total ~6h–12h. Citicoline (CDP-choline) has a plasma half-life of ~56h for choline, but the subjective/cognitive duration of a single dose is 6–12h, not 58–74h. These duration figures appear to have conflated the pharmacokinetic elimination half-life of the choline metabolite with the subjective effect duration.
- **Severity**: MAJOR

### Meclofenoxate
- **Route / Field**: oral / dose scale ordering
- **Shown**: light 50–200 mg, common 400–800 mg, strong 800–1000 mg, heavy ≥600 mg
- **Expected**: heavy ≥1000 mg (or ≥1200 mg). The heavy threshold of ≥600 mg is lower than the strong ceiling of 1000 mg, making the scale non-monotonic. Heavy must exceed the strong upper bound.
- **Severity**: BLOCKER

### Noopept
- **Route / Field**: oral / common dose
- **Shown**: common 20–30 mg
- **Expected**: common 10–20 mg. Noopept is active at very low doses (10 mg is the established standard dose; 20–30 mg is upper-end / strong territory). The `[also: tripsit: common 10 mg]` alternative is more consistent with the literature and the strong tier shown at 30–40 mg, which means "common" and "strong" overlap.
- **Severity**: MAJOR

### Huperzine A (duplicate entry as "Huperzine-a")
- **Route / Field**: insufflation / route existence
- **Shown**: light 50–75 µg, common 75–150 µg, heavy ≥150 µg via insufflation
- **Expected**: Insufflation of huperzine A is not a recognized or documented route; it is a solid extract (sesquiterpene alkaloid) used exclusively orally. No community or clinical data supports intranasal use. This entry likely should not exist at all, or at minimum the duration afterglow of 1h–14h is implausibly wide.
- **Severity**: MAJOR

### Phenylpiracetam
- **Route / Field**: oral / strong and heavy dose
- **Shown**: strong 200–400 mg, heavy ≥600 mg
- **Expected**: strong ~200–250 mg, heavy ≥300–400 mg. Standard community doses are 100–200 mg; 400 mg oral is already well into territory associated with pronounced side effects (anxiety, hypertension). The strong/heavy cutoffs are approximately 2× higher than harm-reduction community consensus.
- **Severity**: MAJOR

### Bromantane
- **Route / Field**: oral / duration (peak and total)
- **Shown**: peak 4h–10h, offset 10h–16h, total 16h–24h
- **Expected**: total ~8h–12h. Bromantane has a half-life of ~11–12h but subjective stimulant/anxiolytic effects are typically 4–8h per dose. A total effect window of 16–24h is more consistent with persistent residual effects from accumulation on repeated dosing, not a single-dose timeline.
- **Severity**: MINOR

### Vinpocetine
- **Route / Field**: half-life
- **Shown**: 1.5h
- **Expected**: ~2–3h. Vinpocetine's terminal half-life is reported as 2–3h in pharmacokinetic studies (with some reporting up to 14h for the apovincaminic acid metabolite). 1.5h is at the very low end and may understate re-dosing intervals.
- **Severity**: MINOR


================================================================================
# Opioid_01
================================================================================

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


================================================================================
# Opioid_02
================================================================================

### Pethidine (Meperidine)
- **Route / Field**: oral / peak duration
- **Shown**: peak 4h–6h
- **Expected**: peak ~1h–2h. Pethidine has a short duration of action (~2–3h total); a 4–6h peak duration is longer than its entire typical effect window.
- **Severity**: MAJOR

### Remifentanil
- **Route / Field**: intravenous / total duration
- **Shown**: total 5h–10h
- **Expected**: total ~5m–15m. Remifentanil is an ultra-short-acting opioid with an elimination half-life of ~3–10 minutes due to ester hydrolysis by non-specific tissue and plasma esterases. A 5–10 hour total duration is off by roughly 30–60×.
- **Severity**: BLOCKER

### Sufentanil
- **Route / Field**: oral / onset and total duration
- **Shown**: onset 1m–2m, total 5m–10m
- **Expected**: oral onset ~15m–45m, total ~3h–6h (sublingual/buccal) or not a practical oral route. The displayed durations appear to be copy-paste errors from the IV row. Sufentanil is not meaningfully active via swallowed oral route (high first-pass), and even if sublingual, 5–10 min total duration is implausibly short — that mirrors IV kinetics, not oral/mucosal.
- **Severity**: BLOCKER

### Tramadol
- **Route / Field**: oral / common dose upper bound
- **Shown**: common 100–250 mg, strong 250–300 mg
- **Expected**: common 100–200 mg, strong 200–400 mg (max single dose 200 mg, max daily 400 mg per clinical guidelines). 250 mg placed in the "common" tier and 300 mg as the top of "strong" compresses the range oddly — 250–300 mg straddles the maximum recommended single dose and seizure risk threshold. The strong ceiling of 300 mg is plausible but the common upper bound of 250 mg is high.
- **Severity**: MINOR

### Oxycodone
- **Route / Field**: inhalation / heavy threshold
- **Shown**: strong 20–35 mg, heavy ≥30 mg (heavy threshold is lower than the strong upper bound — overlap/inversion)
- **Expected**: heavy ≥35 mg (or strong ceiling reduced to 30 mg). The heavy threshold (30 mg) is below the strong ceiling (35 mg), creating a logical inversion in the dose tiers.
- **Severity**: MAJOR


================================================================================
# Other
================================================================================

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


================================================================================
# Peptide
================================================================================

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


================================================================================
# Psychedelic_01
================================================================================

# Verification Findings — Psychedelic_01

### 25C-NBOH
- **Route / Field**: sublingual / afterglow duration
- **Shown**: 72h–144h (3–6 days)
- **Expected**: 6h–24h; afterglow for NBOHs is typically a few hours to ~1 day, consistent with 25I-NBOH PsychonautWiki data and community reports. A 3–6 day afterglow would be clinically significant and is not supported by any literature source.
- **Severity**: MAJOR

### 25E-NBOH
- **Route / Field**: sublingual / afterglow duration
- **Shown**: 120h–240h (5–10 days)
- **Expected**: 6h–24h; no literature supports a 5–10 day afterglow for any NBOH compound. This is likely a data-entry error (hours confused with minutes, or wrong units).
- **Severity**: BLOCKER (could cause a user to believe effects lasting days are normal rather than seeking help)

### 25I-NBOME
- **Route / Field**: insufflation / total duration
- **Shown**: onset 5m–10m, comeup 10m–30m, peak 1h–2h, offset 2h–3h, total 4h–6h, afterglow 24h–168h (1–7 days)
- **Expected**: afterglow 2h–12h; 1–7 day afterglow is pharmacologically implausible for a compound with a ~6h total duration. The 168h upper bound in particular is unsupported by any literature.
- **Severity**: MAJOR

### 25I-NBOH
- **Route / Field**: sublingual / afterglow duration
- **Shown**: 72h–288h (3–12 days)
- **Expected**: 6h–24h; a 3–12 day afterglow is pharmacologically implausible. This is clearly erroneous — likely the same systematic data error as 25C-NBOH and 25E-NBOH.
- **Severity**: BLOCKER (user seeing "afterglow 12 days" may not seek care for prolonged adverse effects)

### 2C-F
- **Route / Field**: oral / all doses
- **Shown**: threshold 100 mg, light 250–350 mg, common 350–500 mg, strong 500–750 mg, heavy ≥750 mg
- **Expected**: threshold ~10–20 mg, common ~150–200 mg; per Shulgin's PIHKAL, 2C-F is active at low tens of milligrams (light ~50–100 mg, common ~100–200 mg). The shown values are 3–5× too high and put the "light" range at doses Shulgin describes as strong-to-heavy. At 500–750 mg this would be a grossly dangerous overdose.
- **Severity**: BLOCKER

### 2C-G
- **Route / Field**: oral / total duration
- **Shown**: total 15h–35h
- **Expected**: ~8h–14h; per Shulgin PIHKAL and Erowid reports, 2C-G has a prolonged duration (~10–18h is plausible on the high end) but 35h total is well outside any reported range and would alarm users into thinking effects are pathologically prolonged.
- **Severity**: MAJOR


================================================================================
# Psychedelic_02
================================================================================

# Pharmacological Review — Psychedelic_02

### 2C-T (2,5-dimethoxy-4-(methylthio)phenethylamine)
- **Route / Field**: oral / peak duration
- **Shown**: peak 30m–1.91667h (≈ 30m–115min)
- **Expected**: peak ~2h–4h; total 4h–6h is plausible but the fractional "1.91667h" is a floating-point artefact (115/60), not a real data value — indicates a raw-minutes field was divided by 60 without rounding
- **Severity**: MINOR (display artefact, not a dose safety issue, but will confuse users)

### 2C-N
- **Route / Field**: oral / light and common dose
- **Shown**: light 100 mg, common 100–125 mg
- **Expected**: light dose should be below common; a light value equal to the bottom of common is internally inconsistent — typical 2C-N light is ~50–75 mg per community reports
- **Severity**: MAJOR (light = common lower bound makes the tier meaningless and could mislead a first-time user into starting at an already-common dose)

### 4-Aco-Det (4-AcO-DET)
- **Route / Field**: inhalation / total duration
- **Shown**: total 30m–1.5h
- **Expected**: 4-AcO-DET vaporized/smoked is short-acting but community reports consistently place total duration at 1.5h–4h; 30 minutes at the low end is implausibly brief for a tryptamine ester — even DMT vaped lasts 15–30 min; the acetylated tryptamine would be longer
- **Severity**: MAJOR (understating duration could lead a user to redose prematurely)

### 4-HO-DMT / Psilocin (listed as "4-HO-DMT / 4-HO-DMT PHOSPHATE ESTER")
- **Route / Field**: oral / common dose
- **Shown**: common 10–20 mg
- **Expected**: 10–20 mg is correct for pure 4-AcO-DMT or psilocin; however this entry is labelled the phosphate ester (psilocybin). Psilocybin is ~1.4× the MW of psilocin, so the same molar dose is ~14–28 mg. If this entry actually represents the free base (psilocin/4-HO-DMT), 10–20 mg is accurate. The naming ambiguity could lead to a 40% underdose or overdose depending on which form is actually being logged. The slash naming conflating two different molecular forms is the core issue.
- **Severity**: MAJOR (two chemically distinct compounds with meaningfully different dosing collapsed into one entry — could cause systematic dosing errors)

### 2C-P-NBOMe / sublingual
- **Route / Field**: sublingual / common dose
- **Shown**: common 250–600 µg
- **Expected**: 2C-P-NBOMe sublingual community data is extremely thin and the compound is poorly characterised; however the range 250–600 µg spans 2.4× — an unusually wide common range. More importantly, 600 µg sublingual for any NBOMe compound approaches territory where cardiovascular toxicity (hypertensive crisis, seizures) has been reported for well-studied analogues (25I-NBOMe). Given 2C-P's own high potency and long duration (10–20h oral), the NBOMe derivative at 600 µg could be dangerous.
- **Severity**: BLOCKER (upper bound of "common" for an NBOMe of an already-potent, long-duration compound — insufficient safety margin; upper common should probably be flagged as "strong" at minimum)


================================================================================
# Psychedelic_03
================================================================================

# Verification Findings — Psychedelic_03

### 4-Ho-Mpmi
- **Route / Field**: oral / dose range unit inconsistency
- **Shown**: threshold 500, light 750 µg, common 1–2 µg
- **Expected**: common 1–2 **mg**. The threshold (500 µg) and light (750 µg) are in micrograms, but common drops to 1–2 µg — which is *lower* than threshold, pharmacologically impossible. Almost certainly a unit encoding error: common should be 1–2 mg (i.e., 1000–2000 µg), consistent with the ascending threshold → light → common sequence.
- **Severity**: BLOCKER (common dose shown as 1–2 µg is sub-threshold by its own scale; if a user interprets this as micrograms they may radically overdose trying to "reach" the stated common dose)

---

### 5-Bromo-DMT
- **Route / Field**: inhalation / total duration
- **Shown**: total 15h–90h
- **Expected**: ~15 min–2 h. Vaporized tryptamines characteristically produce short-duration experiences (minutes to ~1–2 h). A 15–90 hour inhaled duration is pharmacologically implausible for any tryptamine; this figure may have been erroneously copied from a speculative oral/enteral dataset or confused with half-life data.
- **Severity**: BLOCKER (a user could believe an hours-long crisis is still within expected duration and delay seeking help, or conversely panic unnecessarily)

---

### 5-Meo-Dalt
- **Route / Field**: inhalation / total duration
- **Shown**: total 15m–20m
- **Expected**: ~30 min–1 h. 5-MeO-DALT is a long-chain tryptamine; community reports for vaporized administration consistently indicate 30–60 min total. The 15–20 min figure matches vaporized DMT or 5-MeO-DMT, not 5-MeO-DALT, suggesting DMT duration data was applied here.
- **Severity**: MAJOR (undershoots by ~2×; user may re-dose prematurely thinking the experience has ended)

---

### 5-MEO-MIPT
- **Route / Field**: inhalation / total duration
- **Shown**: onset 20m–1h, peak 1h–2h, offset 1h–2h, total 5h–8h
- **Expected**: total ~1–3 h for vaporized route. 5-MeO-MiPT inhaled produces a short, intense experience; a 5–8 hour total duration matches the *oral* profile, not inhalation. Onset of 20 min–1 h for an inhaled substance is also implausible (should be seconds to minutes).
- **Severity**: MAJOR (oral duration data appears to be displayed for the inhalation route; onset and total duration are both wrong for this ROA)


================================================================================
# Psychedelic_04
================================================================================

### Bufotenin
- **Route / Field**: insufflation / total duration
- **Shown**: 45h–120h
- **Expected**: ~45m–2h. Insufflated bufotenin produces an experience of similar length to inhalation (tens of minutes to under 2 hours). The resolved value is almost certainly a unit error (minutes rendered as hours, or a decimal-place slip).
- **Severity**: BLOCKER (user sees "up to 120 hours" for an insufflated dose; they may redose repeatedly believing the substance has worn off when it has not, or panic thinking an effect lasting days is normal)

---

### Changa
- **Route / Field**: oral / route label
- **Shown**: oral: light 5–15 mg, common 15–30 mg, strong 30–50 mg
- **Expected**: Changa is a DMT-infused smokable herb blend; the only recognised route is inhalation (smoking). Oral DMT without a co-ingested MAOI is inactive due to first-pass MAO metabolism. These dose values (which are consistent with smoked DMT) should be labelled inhalation, not oral.
- **Severity**: BLOCKER (labelling smoked doses as oral could lead a user to swallow the blend; if the blend's herb carrier contains sufficient beta-carbolines to act as an MAOI, the result is an uncontrolled and potentially dangerous ayahuasca-like oral experience)

---

### Doip
- **Route / Field**: oral / common dose
- **Shown**: threshold 800, light 800–1500 µg, common 1.5–3 µg, heavy ≥3
- **Expected**: common 1.5–3 mg (i.e. 1500–3000 µg). The threshold and light tiers are correctly expressed in µg, so the common tier — which at 1.5–3 µg is lower than the light tier and 500× below threshold — is a unit-conversion error. Based on DOI/DOB analogue potency and the surrounding tier values, the intended unit is mg.
- **Severity**: BLOCKER (common dose is displayed as 1.5–3 µg when it should be 1.5–3 mg; a user calibrating their dose from this display could ingest 1000× the intended amount)


================================================================================
# Psychedelic_05
================================================================================

# Pharmacology Review — Psychedelic_05

### Efavirenz
- **Route / Field**: inhalation / common dose
- **Shown**: 600–1800 mg
- **Expected**: 50–200 mg smoked — Efavirenz (an antiretroviral) is reportedly smoked recreationally in South Africa at far lower doses; therapeutic oral doses are 600 mg once daily, but inhalation bioavailability is much higher and users typically smoke crushed 200 mg tablets or fractions thereof. 600–1800 mg inhaled would be an extraordinary and dangerous quantity — far exceeding any documented recreational use.
- **Severity**: BLOCKER

### HARMALINE
- **Route / Field**: oral / common dose
- **Shown**: 150–300 mg
- **Expected**: 25–100 mg — Harmaline is a potent MAO inhibitor and tremorigenic alkaloid. PIHKAL/TIHKAL and harm-reduction literature consistently cite psychoactive doses of 25–75 mg oral; 300 mg approaches doses associated with severe tremor, ataxia, and toxic crisis in animal and case-series literature.
- **Severity**: BLOCKER

### HARMINE
- **Route / Field**: oral / common dose
- **Shown**: 225–375 mg
- **Expected**: 25–150 mg — Harmine shares the β-carboline MAOi pharmacophore with harmaline. Community and clinical literature (ayahuasca research, TIHKAL) cite psychoactive doses of 25–100 mg pure harmine. 225–375 mg pure harmine oral is a potentially dangerous overdose range.
- **Severity**: BLOCKER

### Lsa (Morning Glory / Hawaiian Baby Woodrose)
- **Route / Field**: oral / common dose
- **Shown**: 100–250 seeds
- **Expected**: 5–10 seeds (Hawaiian Baby Woodrose, HBWR) or 200–400 morning glory seeds — The oral route entry says "100–250 seeds" without specifying species. If these are HBWR seeds (Argyreia nervosa, ~2–4 µg LSA/seed), 100–250 would be an extreme overdose; HBWR common doses are 4–8 seeds. If morning glory (Ipomoea violacea, ~0.02 µg LSA/seed), 100–250 is on the low end. The "other" route entry showing 2–6 seeds clearly describes HBWR. The oral route's "100–250 seeds" is internally inconsistent with the sublingual (5–7 seeds) and "other" (2–6 seeds) routes, strongly suggesting a species mismatch or magnitude error.
- **Severity**: MAJOR

### IBOGAINE
- **Route / Field**: oral / common dose
- **Shown**: 15–22 mg/kg of body weight
- **Expected**: 10–15 mg/kg (flood dose) — The flood dose for addiction interruption is conventionally cited at 10–15 mg/kg; 15–22 mg/kg is at the upper boundary or beyond the documented flood dose range and overlaps with doses associated with cardiac arrhythmia and fatality. While 15 mg/kg appears in some protocols, 22 mg/kg as a "common" upper end is clinically concerning.
- **Severity**: MAJOR

### MDE (MDEA)
- **Route / Field**: oral / total duration
- **Shown**: 3h–5h
- **Expected**: 4h–6h — MDE (N-ethyl MDA) duration is consistently reported at 4–6 hours in PIHKAL and community reports; 3 hours is below the lower bound of any credible source and could cause users to redose prematurely.
- **Severity**: MINOR


================================================================================
# Psychedelic_06
================================================================================

# Verification Findings — Psychedelic_06

### MEE (Psychedelic)
- **Route / Field**: oral / common dose
- **Shown**: 3.45–5.75 mg
- **Expected**: ~30–60 mg; MEE (3-methoxy-4,5-methylenedioxyamphetamine isomer) is a phenethylamine amphetamine analog from PIHKAL. Shulgin's actual entry reports active doses in the 30–60 mg range. The ~3–6 mg value looks like a 10× unit-conversion error (possibly µg or a decimal shift).
- **Severity**: BLOCKER (if displayed to a user, 3–6 mg would appear subthreshold and encourage dangerous dose escalation to reach effects; actual doses at 10× could be harmful)

### Met (Psychedelic) — oral route
- **Route / Field**: oral / common dose
- **Shown**: 120–150 mg (psychonautwiki)
- **Expected**: ~20–30 mg; Met (N-methyl-tryptamine / MMT) by the oral route is active at 20–30 mg. 120–150 mg is a 4–6× overdose relative to community consensus and TripSit data (the `[also: tripsit: common 20–25 mg]` note flags the same discrepancy). At 120 mg+ oral MMT, severe serotonergic effects and cardiovascular toxicity are plausible.
- **Severity**: BLOCKER (winning value is 4–6× above established community consensus; safety risk if user self-doses from this figure)

### PEA (Psychedelic) — oral route
- **Route / Field**: oral / common dose
- **Shown**: 1200–2000 mg
- **Expected**: ~200–400 mg endogenous trace amine (essentially inert orally due to rapid MAO-A metabolism unless combined with an MAOI); if used with an MAOI the active dose is extremely low (~10–25 mg). 1200–2000 mg is far beyond any documented human use in PIHKAL or harm-reduction literature and is not a realistic "common dose" for any context.
- **Severity**: MAJOR (no credible source documents 1200–2000 mg as a common dose; value appears implausible and could cause cardiovascular harm if taken literally, especially in any MAOI-adjacent context)

### Psilocybin mushrooms (Psychedelic) — oral route
- **Route / Field**: oral / dose tiers (unit)
- **Shown**: threshold 2.5, light 2.5–10 mg, common 10–25 mg, strong 25–50 mg, heavy ≥50 mg
- **Expected**: These values in **mg** match psilocybin *extract* dosing, not **mushroom** dosing (which is in grams). The entry title is "Psilocybin mushrooms" (the dried fungal material), so the unit should be grams (threshold ~0.5 g, light 0.5–1.5 g, common 1.5–3.5 g, strong 3.5–5 g, heavy ≥5 g). A user reading "common 10–25 mg" of dried mushrooms would consume a negligible amount and see no effect, or—if they misread mg as grams—a dangerous overdose.
- **Severity**: MAJOR (unit mismatch between substance name and dose values; compare adjacent "Mushrooms" entry which correctly uses grams)

### Para-Methoxyamphetamine (Psychedelic) — oral / total duration
- **Route / Field**: oral / total duration
- **Shown**: 6h–24h
- **Expected**: ~8–12h; the upper bound of 24h is highly implausible for PMA at any dose. PMA has a reported duration of 8–12h in overdose case literature. A 24h upper bound could cause a user to redose dangerously early thinking the drug has worn off. (The lower bound of 6h is plausible.)
- **Severity**: MAJOR (wide range with an implausible 24h ceiling on a substance notorious for fatal overdoses from staggered redosing)


================================================================================
# Psychedelic_07
================================================================================

### Truffles
- **Route / Field**: other / all dose tiers and heavy threshold
- **Shown**: light 0.5–1.5 g, common 1.5–4 g, heavy ≥4 g
- **Expected**: light 5–7 g, common 10–15 g, heavy ≥20 g — Magic truffles (Psilocybe sclerotia) are sold and consumed fresh; fresh truffle doses are approximately 4–5× higher than dried mushroom caps due to water content (~90% water). The shown values match dried *Psilocybe* mushroom doses, not fresh sclerotia. A user treating "heavy ≥4 g" as the upper bound for fresh truffles would be severely underdosed, while a user expecting the shown "common" range and consuming a standard 15 g fresh truffle pack could be alarmed thinking they've taken a massive overdose.
- **Severity**: BLOCKER (unit/form confusion — dried mushroom thresholds applied to fresh truffles, off by ~4–5×)


================================================================================
# Stimulant_01
================================================================================

# Stimulant_01 Verification Findings

### 4-Methylaminorex (4-MAX / "U4Euh")
- **Route / Field**: oral / common dose
- **Shown**: common 5–10 mg (tripsit)
- **Expected**: common 10–25 mg — community reports and PsychonautWiki consistently place common oral doses in the 10–25 mg range; the tripsit value reflects a conservative/threshold tier, not the typical recreational dose. The `[also: drug.community: common 10–25 mg]` alternate confirms the winning value is an underestimate.
- **Severity**: MAJOR

### 4-Fluoromethylphenidate (4F-MPH)
- **Route / Field**: oral / afterglow duration
- **Shown**: afterglow 5h–10h
- **Expected**: afterglow 1h–3h — afterglow of 5–10 h for a methylphenidate analogue is anomalously long. Standard MPH and its fluorinated analogues produce afterglow lasting roughly 1–3 h. A 5–10 h afterglow would be consistent with the *total* duration, not the afterglow phase, suggesting a data entry confusion.
- **Severity**: MAJOR

### 2-DPMP (Desoxypipradrol)
- **Route / Field**: insufflation / total duration
- **Shown**: total 16h–72h (tripsit)
- **Expected**: total 16h–36h — the upper bound of 72 h is plausible only for extreme doses; community harm-reduction documentation (PsychonautWiki, Erowid trip reports) consistently reports 24–36 h as the typical upper bound for a single dose. A 72 h total is not impossible at high doses, but presenting it as a routine range without a strong-dose qualifier is misleading and may cause users to underestimate duration and redose dangerously. NOTE: this is an edge call — the half-life of 18 h makes a very long duration biologically plausible. Flagging MINOR only.
- **Severity**: MINOR

### 4-CMC (Clephedrone)
- **Route / Field**: oral / common dose
- **Shown**: common 50 mg (single value, no range) (tripsit)
- **Expected**: common 50–100 mg — a point value with no range is almost certainly a truncated or incomplete entry. Community and TripSit data for cathinones in this potency class consistently give a range. A single value of "50 mg" with no upper bound is functionally useless and suggests data corruption or truncation.
- **Severity**: MINOR


================================================================================
# Stimulant_02
================================================================================

# Stimulant_02 Verification Findings

### Caffeine
- **Route / Field**: insufflation / offset vs total duration
- **Shown**: offset 6h–10h, total 1h–2.5h
- **Expected**: offset should be shorter than total duration (e.g. offset 15m–45m within a total of 1h–2.5h). The 6h–10h offset figure appears to be copy-paste contamination from the oral route's offset, which reflects caffeine's long elimination half-life (~5h) dragging into the comedown — not the insufflation offset.
- **Severity**: BLOCKER (pharmacologically self-contradictory: offset cannot exceed total; displayed in-app duration timeline would be nonsensical)

### Cocaine
- **Route / Field**: intravenous / common dose
- **Shown**: 5–10 mg (psychonautwiki wins)
- **Expected**: 30–60 mg per injection is the community-consensus figure (also the `[also: drug.community]` value). IV cocaine is typically used in doses of 25–75 mg in recreational contexts; 5–10 mg is a sub-threshold test dose, not a common dose.
- **Severity**: MAJOR (winning value is ~5× below realistic common-use range; understating IV cocaine dose misleads harm-reduction guidance)

### Crack
- **Route / Field**: inhalation / total duration
- **Shown**: 5h–20h
- **Expected**: 5m–15m per hit; a heavy smoking session is commonly described as lasting 30m–2h total. 20h is physiologically implausible for smoked cocaine — its characteristically short duration (minutes) is a key reason for its high addiction liability.
- **Severity**: BLOCKER (could cause user to drastically underestimate redosing risk; 20h is off by ~60×)

### Butylone
- **Route / Field**: oral / common dose
- **Shown**: 150–250 mg (piru-curated)
- **Expected**: 70–100 mg per TripSit and broader community reports. Butylone potency is comparable to MDPV precursor cathinones; 150–250 mg oral is the strong-to-heavy range, not common.
- **Severity**: MAJOR (winning value is ~2–3× above established community consensus; could normalize a strong-to-heavy dose as typical)

### 4-Methylthioamphetamine
- **Route / Field**: oral / total duration
- **Shown**: 8h–20h
- **Expected**: ~6h–10h. 4-MTA is a substituted amphetamine with MAOI-like serotonergic activity; pharmacokinetics would not support a 20h upper bound for a single oral dose. Literature (EMCDDA, forensic reports) describes effects lasting 4–8h. The 20h figure may reflect rare prolonged after-effects being misclassified as total duration.
- **Severity**: MAJOR (upper bound is approximately 2× too high; could cause dangerous re-dose timing errors given 4-MTA's serotonin toxicity risk)


================================================================================
# Stimulant_03
================================================================================

# Stimulant_03 Verification Findings

### Focalin (dexmethylphenidate)
- **Route / Field**: oral / total duration
- **Shown**: 9h–12h
- **Expected**: 4h–6h for IR formulation. Focalin XR runs 8–10h, but the dose range (10–40 mg) matches IR tablets. IR dexmethylphenidate duration is comparable to IR methylphenidate (2.5–5h); 9–12h is the XR profile and will mislead users taking the immediate-release form.
- **Severity**: MAJOR

### Methcathinone
- **Route / Field**: oral / common dose
- **Shown**: 100–200 mg
- **Expected**: 25–75 mg. The `[also: drug.community: common 25–50 mg]` alternative is more consistent with harm-reduction literature (Erowid, PsychonautWiki). 100–200 mg oral methcathinone is in the strong-to-heavy range for most users and carries meaningful cardiovascular risk at that scale.
- **Severity**: BLOCKER

### Pentedrone
- **Route / Field**: insufflation / common dose
- **Shown**: 75–125 mg (piru-curated), while both psychonautwiki and tripsit show common 5–10 mg
- **Expected**: 5–15 mg. Both authoritative sources agree on 5–10 mg. The piru-curated value is 7–12× higher than consensus — a massive overdose if a user trusts the app's displayed "common" figure.
- **Severity**: BLOCKER

### Kratom
- **Route / Field**: oral / total duration
- **Shown**: total 2h–4h
- **Expected**: 4h–6h (stimulant dose), up to 6h–8h at sedating doses. 2–4h is short even for the stimulant threshold dose range; most harm-reduction sources (Erowid, PsychonautWiki) report 4–6h total. Users may redose too early.
- **Severity**: MAJOR

### Methylphenidate
- **Route / Field**: oral / total duration
- **Shown**: total 2.5h–4h
- **Expected**: 3h–6h for IR methylphenidate. 2.5h lower bound is plausible at the short end but the upper bound of 4h is consistently underestimated in clinical data (FDA label: up to 5h). Minor but relevant for users timing their next dose.
- **Severity**: MINOR

### Naphyrone
- **Route / Field**: insufflation / total duration
- **Shown**: total 6h–10h
- **Expected**: 2h–4h. Naphyrone (naphthylpyrovalerone) is a cathinone derivative pharmacologically similar to pyrovalerone. Community reports (Erowid, Drugs-Forum, early PsychonautWiki entries) consistently document 2–4h duration by insufflation. 6–10h would be extraordinary for this compound class and could suppress redose caution.
- **Severity**: MAJOR


================================================================================
# Stimulant_04
================================================================================

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


================================================================================
# Supplement_01
================================================================================

# Verification Findings — Supplement_01 (chunk 1/2)

### Iodine (Supplement)
- **Route / Field**: oral / strong and heavy doses
- **Shown**: strong 500–1000 mcg, heavy ≥1100 mcg
- **Expected**: strong ≤400 mcg, heavy ≥400–500 mcg. The tolerable upper intake level (UL) established by the Institute of Medicine is 1,100 mcg/day for adults; displaying 500–1000 mcg as merely "strong" normalises intake that is already approaching the UL. More importantly, presenting ≥1,100 mcg as the "heavy" threshold (rather than a danger threshold) is misleading — chronic intake at this level causes thyroid dysfunction (Wolff-Chaikoff effect, autoimmune thyroiditis). The "common" range of 300–500 mcg is also above the RDA of 150 mcg and the safe upper supplemental range (~500 mcg) for most users.
- **Severity**: BLOCKER (could harm user — iodine toxicity is clinically real and the heavy label undersells the risk)

### Selenium (Supplement)
- **Route / Field**: oral / strong and heavy doses
- **Shown**: strong 200–400 mcg, heavy ≥400 mcg
- **Expected**: strong 100–200 mcg; heavy ≥200–400 mcg. The tolerable UL for selenium is 400 mcg/day. Displaying 200–400 mcg as merely "strong" and ≥400 mcg as "heavy" (implying survivable excess) is dangerous — selenium toxicity (selenosis) begins at intakes persistently above the UL and is irreversible at higher doses (hair loss, nail brittleness, neurological damage). A "common" dose of 100–200 mcg is already at the high end of supplemental ranges; 200–400 mcg should carry a stronger label.
- **Severity**: BLOCKER (could harm user — selenium has a narrow therapeutic window and the thresholds are systematically too permissive)

### Vitamin A (Supplement)
- **Route / Field**: oral / strong dose
- **Shown**: strong 10000–25000 IU
- **Expected**: strong 5000–10000 IU. The tolerable UL for preformed vitamin A (retinol) is 10,000 IU/day for adults. Calling 10,000–25,000 IU "strong" frames intake above the UL as a normal supplemental tier. Chronic intake at 25,000 IU causes hypervitaminosis A (hepatotoxicity, teratogenicity, increased fracture risk). The heavy threshold of ≥25,000 IU is appropriate as a danger marker but the strong range bleeds well above the UL.
- **Severity**: BLOCKER (could harm user — preformed vitamin A is teratogenic and hepatotoxic at sustained doses above the UL; this framing normalises those doses)

### Vitamin B6 (Supplement)
- **Route / Field**: oral / strong and heavy doses
- **Shown**: strong 100–200 mg, heavy ≥200 mg
- **Expected**: strong 50–100 mg; heavy ≥100–200 mg. The EU tolerable UL is 25 mg/day; the US UL is 100 mg/day. Peripheral neuropathy from pyridoxine toxicity is well-documented at sustained intakes above 50–100 mg/day, with case reports of sensory neuropathy at doses as low as 50–100 mg taken chronically. Displaying 100–200 mg as "strong" (implying safe if experienced) and ≥200 mg as merely "heavy" is clinically dangerous.
- **Severity**: BLOCKER (could harm user — B6 neuropathy is a known, well-documented clinical harm at these doses)

### Vitamin E (Supplement)
- **Route / Field**: oral / strong and heavy doses
- **Shown**: strong 800–1500 IU, heavy ≥1500 IU
- **Expected**: strong 400–800 IU; heavy ≥800–1000 IU. The tolerable UL for vitamin E is 1,000 mg (~1,500 IU of natural or ~1,100 IU of synthetic α-tocopherol). The strong range extends to 1,500 IU which exceeds the UL, and the heavy threshold at ≥1,500 IU is above it as well. High-dose vitamin E (>400 IU/day) has been associated with increased all-cause mortality in meta-analyses, and doses above the UL carry haemorrhagic risk (anti-platelet and vitamin-K antagonism).
- **Severity**: MAJOR (strong range crosses the UL; warrants re-anchoring the heavy threshold to ≥1,000 IU)

### Vitamin B3 (Supplement)
- **Route / Field**: oral / strong and heavy doses
- **Shown**: strong 500–1500 mg, heavy ≥2000 mg
- **Expected**: strong 500–1000 mg; heavy ≥1000–1500 mg. The tolerable UL for niacin (as nicotinic acid) is 35 mg/day for flush-producing forms. For supplemental niacin used therapeutically, hepatotoxicity has been documented at 1,000–3,000 mg/day. Displaying 500–1,500 mg as "strong" and ≥2,000 mg as "heavy" could lead a user to take a dose in the hepatotoxic range thinking it is merely "strong." Extended-release niacin is particularly hepatotoxic at these doses.
- **Severity**: MAJOR (hepatotoxic range is presented as ordinary strong/heavy tiers without sufficient contextual warning via the dose labels alone)

### L-Theanine (Supplement)
- **Route / Field**: oral / half-life
- **Shown**: 1h
- **Expected**: ~2.5–3.5h. Published pharmacokinetic studies (e.g., Türközü & Şanlier, 2017; Kimura et al.) report an elimination half-life of approximately 1.2–3.5h, with most sources citing ~2–3h. A 1h half-life is at the low end of the range and likely underestimates duration, which could cause users to redose too soon.
- **Severity**: MINOR (plausible at the low end but likely underestimated; practical impact is minor)

### Quercetin (Supplement)
- **Route / Field**: oral / half-life
- **Shown**: 12h
- **Expected**: ~1.5–5h. Human PK studies of quercetin report a half-life of approximately 1.5–5 hours for quercetin aglycone and glycosides. A 12h half-life would be appropriate for quercetin-3-glucoside in some forms but is approximately 2–3× too long for standard quercetin supplements and may cause users to under-dose frequency.
- **Severity**: MINOR (directionally concerning — shifts the apparent accumulation profile but unlikely to cause acute harm)


================================================================================
# Supplement_02
================================================================================

# Verification Findings — Supplement_02.txt

### Zinc Picolinate
- **Route / Field**: oral / half-life
- **Shown**: 24h
- **Expected**: ~1–2h plasma half-life (zinc redistributes rapidly into erythrocytes and tissues after absorption; plasma Zn t½ measured in healthy adults is 1–2h, not a day)
- **Severity**: MAJOR (off by ~12–24×; will make the app's "active window" visualization wildly incorrect)

### Zinc Picolinate
- **Route / Field**: oral / strong dose and heavy dose
- **Shown**: strong 50–100 mg, heavy ≥100 mg
- **Expected**: strong ~40 mg, heavy ≥50 mg — the NIH tolerable upper intake level (UL) for elemental zinc in adults is 40 mg/day; 50–100 mg regularly causes nausea/vomiting and copper deficiency; ≥100 mg is medically significant acute toxicity territory
- **Severity**: BLOCKER (labelling a dose well above the established UL as merely "strong" normalises harmful intake; a user could interpret this as a reasonable upper-recreational range)


================================================================================
# Uncategorized
================================================================================

# Uncategorized — Verification Findings

### Blue Lotus

- **Route / Field**: oral / onset
- **Shown**: 10s–1m
- **Expected**: ~15–45 min; a 10-second onset is physically impossible for oral administration — gastric absorption requires at minimum several minutes even for rapidly absorbed compounds. This value belongs to an inhalation profile, not oral.
- **Severity**: BLOCKER (could mislead a user into re-dosing because they believe oral onset is near-instantaneous)

- **Route / Field**: oral / total duration
- **Shown**: 6h–8h
- **Expected**: ~2–4h; Blue Lotus active alkaloids (nuciferine, apomorphine analogues) have short half-lives. Community reports and the limited pharmacological literature consistently place total oral duration at 2–4 hours, not 6–8.
- **Severity**: MAJOR (off by ~2×)

- **Route / Field**: oral / afterglow duration
- **Shown**: 6h–8h (same as total duration)
- **Expected**: ~1–2h, or less than the total duration; an afterglow equal to or exceeding the active phase is pharmacologically implausible and would effectively double the displayed experience length.
- **Severity**: MAJOR (logically inconsistent — afterglow cannot equal total duration)
