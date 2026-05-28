

# AMPAkine

# AMPAkine — Verification Findings

### Aniracetam
- **Route / Field**: oral / heavy dose
- **Shown**: ≥4500 mg
- **Expected**: ≥2000–2500 mg. Clinical trials use 750–1500 mg/day total (split doses); community reports cap "heavy" around 2000–2500 mg. 4500 mg is 3× the top of the common range and has no support in either pharmacokinetic or harm-reduction literature. The strong tier already reaches 3000 mg, making 4500 mg an implausible jump.
- **Severity**: MAJOR


# Analgesic

No findings.


# Anticonvulsant

# Anticonvulsant — Verification Findings

### CBDV
- **Route / Field**: all routes / half-life
- **Shown**: 24h
- **Expected**: ~1.5–3h — CBDV (cannabidivarin) is rapidly metabolized; its half-life in human studies is 1–3h, far shorter than CBD (~14–30h). The 24h figure likely conflates CBDV with CBD.
- **Severity**: BLOCKER

### Epidiolex
- **Route / Field**: oral / all dose tiers
- **Shown**: threshold 2.5 mg, light 2.5–5 mg, common 5–10 mg, strong 10–20 mg, heavy ≥20 mg
- **Expected**: therapeutic range starts at ~2.5 mg/kg/day titrating to 5–20 mg/kg/day (350–1400 mg/day for a 70 kg adult) — Epidiolex is pharmaceutical CBD dosed in mg/kg; the flat mg values shown (5–20 mg) are 50–100× below any clinically meaningful dose and match no documented harm-reduction pattern either.
- **Severity**: BLOCKER

### Perampanel
- **Route / Field**: oral / peak duration
- **Shown**: 8h–24h
- **Expected**: ~0.5–2.5h — labelled Tmax for perampanel is 0.5–2.5h across multiple studies; a peak window of 8–24h describes the elimination tail, not the peak effect.
- **Severity**: MAJOR

### Zonisamide
- **Route / Field**: oral / half-life
- **Shown**: 78h
- **Expected**: ~50–70h (commonly cited as 63h in multiple PK references and the FDA label) — 78h is outside the established range and would meaningfully distort dosing-interval estimates.
- **Severity**: MINOR


# Antidepressant

# Antidepressant — Verification Findings

### Isocarboxazid
- **oral / half-life**
- **Shown**: 2.5h
- **Expected**: ~36h — isocarboxazid's plasma elimination half-life is reported as approximately 36h in clinical pharmacokinetic studies; 2.5h is closer to the half-life of phenelzine or tranylcypromine and appears to be a cross-substance data error
- **Severity**: BLOCKER

### Desvenlafaxine
- **oral / heavy**
- **Shown**: ≥400 mg
- **Expected**: ≥150 mg — the maximum recommended daily dose is 100 mg; doses above 100 mg confer no additional antidepressant benefit and increase adverse effects; 400 mg as the heavy threshold is 4× the clinical ceiling
- **Severity**: MAJOR

### Tianeptine
- **oral / common**
- **Shown**: 25–50 mg
- **Expected**: 12–25 mg — the therapeutic regimen is 12.5 mg three times daily (37.5 mg total daily); a single-dose common of 25–50 mg exceeds the full daily therapeutic dose; PsychonautWiki (12–35 mg) and TripSit (12.5 mg) both corroborate the lower range
- **Severity**: MAJOR

### Fluoxetine
- **oral / half-life**
- **Shown**: 384h (16 days)
- **Expected**: 96–288h (4–12 days) — parent fluoxetine half-life is 1–4 days; active metabolite norfluoxetine is 4–16 days; citing 384h represents the absolute upper bound of the metabolite range and overstates the effective half-life that most references cite as 1–2 weeks (168–336h)
- **Severity**: MINOR

### Milnacipran
- **oral / strong and heavy**
- **Shown**: strong 200 mg, heavy ≥200 mg
- **Expected**: strong threshold below 200 mg (e.g., 150–200 mg), heavy ≥200 mg — strong and heavy share an identical boundary at 200 mg, making the strong tier a zero-width range at its upper bound; maximum approved dose is 200 mg/day, so the heavy anchor is correct but strong needs a lower ceiling
- **Severity**: MINOR

### Tranylcypromine
- **oral / half-life**
- **Shown**: 2.16667h
- **Expected**: 2.5h — the value 2.16667 = 130 ÷ 60, indicating 130 minutes was entered and divided by 60 rather than using the published half-life of ~2.5h; pharmacologically close but the fractional artifact signals a unit-conversion error in data entry
- **Severity**: MINOR


# Antihistamine

# Antihistamine — Verification Findings

### Atropine
- **Route / Field**: oral / common & strong doses
- **Shown**: common 2–5 mg, strong 6–10 mg
- **Expected**: common 0.4–1 mg, strong 1–2 mg — therapeutic anticholinergic range tops out at ~2 mg; 2–5 mg oral produces severe toxidrome in most adults, and 6–10 mg is potentially lethal (atropine LDLo estimates ~1–4 mg/kg)
- **Severity**: BLOCKER

### Diphenhydramine
- **Route / Field**: oral / common dose
- **Shown**: common 50–100 mg (piru-curated wins over psychonautwiki 200–400 mg and tripsit 200–500 mg)
- **Expected**: common 200–400 mg for recreational/deliriant use — 50–100 mg is the therapeutic antihistamine/sleep dose; both major harm-reduction databases place recreational common at 4–8× higher; the winning value understates recreational exposure by a large margin
- **Severity**: MAJOR

### Doxylamine
- **Route / Field**: oral / common dose
- **Shown**: common 25 mg (piru-curated wins over tripsit 200–350 mg)
- **Expected**: common ~200–350 mg for recreational use — 25 mg is the OTC sleep-aid dose; tripsit places recreational common at ~10× higher; same pattern as diphenhydramine (first-generation deliriant antihistamine)
- **Severity**: MAJOR


# Antimicrobial

No findings.


# Antipsychotic

# Antipsychotic — Verification Findings

### Aripiprazole
- **Route / Field**: intramuscular / duration peak
- **Shown**: peak 240h–720h (10–30 days)
- **Expected**: ~96h–168h (4–7 days); Abilify Maintena Tmax is ~7 days per FDA label; 30-day upper bound is inflated by ~4×
- **Severity**: MAJOR

### Aripiprazole
- **Route / Field**: intramuscular / duration offset + total
- **Shown**: offset 2160h–3120h (90–130 days), total 2880h–4320h (120–180 days)
- **Expected**: offset ~480h–672h, total ~672h–840h; dosing interval is 28 days (672h); 5 half-lives of aripiprazole (96h) ≈ 480h; stated values are 4–6× too long
- **Severity**: BLOCKER

### Cariprazine
- **Route / Field**: oral / half-life
- **Shown**: 1200h (50 days)
- **Expected**: ≤504h (~21 days); DDCAR (longest active metabolite) t½ is 1–3 weeks per FDA label; 50 days is ~2.4× the upper bound
- **Severity**: BLOCKER

### Cariprazine
- **Route / Field**: oral / duration total
- **Shown**: total 672h–1344h (28–56 days)
- **Expected**: total ≤168h–504h; a single oral dose does not produce clinically meaningful effect for 28–56 days; this flows from the inflated half-life
- **Severity**: MAJOR

### Paliperidone
- **Route / Field**: oral / duration peak, offset, total
- **Shown**: peak 24h–48h, offset 48h–96h, total 96h–192h (4–8 days per dose)
- **Expected**: peak ~12h–24h, total ~24h–48h; oral paliperidone ER (Invega) has a 24h dosing window and ~23h half-life; multi-day total duration per dose is implausible
- **Severity**: MAJOR

### Paliperidone
- **Route / Field**: intramuscular / duration offset + total
- **Shown**: offset 1680h–2880h (70–120 days), total 2880h–4320h (120–180 days)
- **Expected**: offset ~480h–840h, total ~672h–1008h; Invega Sustenna is a monthly injection (28-day cycle ≈ 672h); stated values are 4–6× the actual dosing interval
- **Severity**: BLOCKER

### Quetiapine
- **Route / Field**: oral / common dose upper bound
- **Shown**: common 150–750 mg
- **Expected**: common upper bound ~400 mg; 750 mg is the near-maximum approved dose for schizophrenia; even community harm-reduction sources (cited in data) list common at 50–150 mg; the curated upper bound is anomalously high
- **Severity**: MAJOR

### Risperidone
- **Route / Field**: intramuscular / duration total
- **Shown**: total 1344h–2016h (56–84 days)
- **Expected**: total ~336h–504h (2–3 weeks); Risperdal Consta dosing interval is 14 days (336h); microsphere drug release is complete by ~5–6 weeks at most; 56–84 days is 3–5× too long
- **Severity**: BLOCKER


# Benzodiazepine_01

# Verification Findings — Benzodiazepine chunk 1/2

### Deschloroetizolam
- **Route / Field**: oral / common dose
- **Shown**: 4–8 mg (piru-curated); [also: drug.community: common 1–2 mg]
- **Expected**: ~1–3 mg. Deschloroetizolam is roughly equipotent to etizolam; community reports and the drug.community source converge on 1–2 mg common. The piru-curated value is 2–8× too high and risks harm.
- **Severity**: BLOCKER

### Midazolam — insufflation / total duration
- **Route / Field**: insufflation / total duration
- **Shown**: 4h–8h
- **Expected**: 1h–2h (occasionally up to ~2.5h). Midazolam has a half-life of ~1.5–2.5 h and is specifically chosen clinically for its ultra-short action. Intranasal onset is rapid and total effect window is well under 2 h in virtually all reports. 4–8 h total is the duration of a long-acting benzo, not midazolam.
- **Severity**: BLOCKER

### Midazolam — intramuscular / total duration
- **Route / Field**: intramuscular / total duration
- **Shown**: 4h–8h
- **Expected**: 1h–2.5h. Same pharmacokinetic rationale as above; IM midazolam onset in ~5–15 min, clinical sedation 30–90 min, total subjective effects rarely exceed 2 h.
- **Severity**: MAJOR

### Midazolam — intravenous / peak duration
- **Route / Field**: intravenous / peak phase
- **Shown**: peak 1h–4h
- **Expected**: peak ~5–20 min. IV midazolam has near-instant onset; peak subjective effect lasts minutes, not 1–4 h. Total IV duration is typically 30–90 min. The peak range stated is off by an order of magnitude.
- **Severity**: BLOCKER

### Nifoxipam — oral / total duration
- **Route / Field**: oral / total duration
- **Shown**: 10h–75h (psychonautwiki)
- **Expected**: upper bound ≤ ~24h. Nifoxipam is a short-to-intermediate acting nitrobenzodiazepine (half-life ~3–5 h estimated from structural analogy to flunitrazepam). 75 h total is pharmacokinetically implausible and will mislead users dramatically.
- **Severity**: MAJOR

### Bromazepam — oral / peak duration
- **Route / Field**: oral / peak phase
- **Shown**: peak 2h–12h
- **Expected**: peak ~1h–3h. Bromazepam t½ ~10–20 h but peak subjective effect after oral dosing is 1–3 h; a 12 h peak window is implausible for a drug with a single Cmax.
- **Severity**: MINOR

### Medazepam — oral / afterglow
- **Route / Field**: oral / afterglow
- **Shown**: afterglow 1h–172h
- **Expected**: upper bound ≤ ~48h. 172 h (> 7 days) is not a plausible afterglow even accounting for medazepam's active metabolites (diazepam, desmethyldiazepam). The value appears to be a data entry artifact (possibly 12h corrupted to 172h).
- **Severity**: MAJOR


# Benzodiazepine_02

# Verification Findings — Benzodiazepine_02

## Quazepam

### oral / duration total
- **Shown**: total 6h–12h (tripsit)
- **Expected**: ~12h–24h minimum. Quazepam's parent t½ is ~39h; its active metabolite 2-oxoquazepam has t½ ~39h and N-desalkyl-2-oxoquazepam ~73h. Subjective sedation and residual impairment consistently extend well past 12h in clinical literature. 6–12h total dramatically understates the functional duration.
- **Severity**: MAJOR

---

## Temazepam

### oral / duration afterglow upper bound
- **Shown**: afterglow 3.5h–18.4h (psychonautwiki)
- **Expected**: Upper bound should be a round number (~18h or ~20h). 18.4h is an artifact of automated unit conversion (e.g. 1100 minutes ÷ 60 = 18.333…h displayed as 18.4h), not a pharmacologically meaningful figure. Indicates a data pipeline precision error upstream.
- **Severity**: MINOR

---

## Triazolam

### oral / strong dose upper bound
- **Shown**: strong 0.5–1.5 mg (tripsit)
- **Expected**: Strong ceiling should be ≤0.5 mg. Triazolam's maximum approved clinical dose is 0.25 mg (0.5 mg in some older guidelines). 1.5 mg is 6× the standard maximum and sits firmly in acute toxicity/overdose territory; labeling it "strong" normalises a genuinely dangerous dose.
- **Severity**: BLOCKER


# Cannabinoid

# Cannabinoid Verification Findings

### 4F-Neb
- **Route / Field**: Insufflation — common dose; Oral — common dose
- **Shown**: Insufflation common 75–150 mg; Oral common 100–150 mg (tripsit)
- **Expected**: Sub-milligram to low-milligram range, consistent with all other synthetic cannabinoids in this list (next-highest common inhaled doses are ~1–5 mg)
- **Severity**: BLOCKER — 75–300 mg is 50–300× higher than any comparable SC; if this is a synthetic cannabinoid these doses would be acutely life-threatening; likely a data entry error in TripSit conflating a different compound or using wrong units

### CBN-O
- **Route / Field**: Inhalation — onset duration
- **Shown**: onset 5m–20m (piru-curated)
- **Expected**: 1m–5m; CBN-O is cannabinol acetate ester, not a prodrug requiring hepatic deacetylation the way THC-O does — inhalation should produce near-immediate absorption; 5–20 min onset is inconsistent with pulmonary pharmacokinetics for a lipophilic cannabinoid
- **Severity**: MAJOR

### JWH-073
- **Route / Field**: Inhalation — offset duration
- **Shown**: offset 5m–10m (psychonautwiki)
- **Expected**: 30m–60m minimum; offset of 5–10 min is irreconcilable with the listed total of 1h–2h (onset 5–10 min + peak 1h–1.5h + offset 5–10 min far exceeds the stated total); likely a data entry error in PsychonautWiki (possibly comedown mislabeled as offset)
- **Severity**: MAJOR

### 5F-Pb-22
- **Route / Field**: Oral — all dose tiers
- **Shown**: threshold 1 mg, light 1–3 mg, common 3–5 mg, strong 5–8 mg, heavy ≥8 mg (psychonautwiki) — identical to inhalation doses
- **Expected**: Oral doses should be higher than inhalation doses; synthetic cannabinoids have substantially lower oral bioavailability vs inhalation; identical ranges suggest the oral entry is a copy of the inhalation entry
- **Severity**: MAJOR

### Nabilone
- **Route / Field**: Half-life
- **Shown**: 35h (piru-curated)
- **Expected**: ~2h for parent compound (per FDA label and published PK studies); active metabolites extend to ~35h, but storing the metabolite half-life as the compound half-life will cause the app to massively overestimate how long nabilone remains active; should be labeled as effective/metabolite half-life or corrected to ~2h parent + note
- **Severity**: MAJOR

### THC
- **Route / Field**: Inhalation — light/common dose gap
- **Shown**: light 2–5 mg, common 10–25 mg (piru-curated)
- **Expected**: No gap between tiers; light top (5 mg) and common bottom (10 mg) leave an uncharacterized 5–10 mg band; minor compared to other findings but atypical formatting — common lower bound should be ~5 mg to be contiguous with light
- **Severity**: MINOR


# Cardiovascular

# Cardiovascular Verification Findings

### Propranolol
- **Route / Field**: oral / afterglow duration
- **Shown**: afterglow 1h–8h
- **Expected**: Propranolol is a non-psychoactive beta-blocker with no afterglow phase. "Afterglow" is a psychedelic/entactogen concept; its presence here is a tripsit template bleed-through and is clinically meaningless and misleading.
- **Severity**: MAJOR

### Labetalol
- **Route / Field**: intravenous / strong–heavy tier boundary
- **Shown**: strong 80–160 mg, heavy ≥300 mg
- **Expected**: The gap between strong ceiling (160 mg) and heavy threshold (300 mg) is unclassified. Clinical IV labetalol is given as 20–80 mg boluses; cumulative max in hypertensive emergency is ~300 mg. A single-bolus heavy threshold of 300 mg is pharmacologically extreme and the 140 mg gap makes the tier ladder internally inconsistent.
- **Severity**: MINOR


# Depressant_01

# Verification Findings — Depressant_01

### Allobarbital
- **Route / Field**: oral / doses
- **Shown**: light 500–1000 mg, common 1000–1500 mg, strong 1500–2000 mg
- **Expected**: light ~50–100 mg, common ~100–200 mg, strong ~200–400 mg — Allobarbital is a long-acting barbiturate; therapeutic hypnotic doses were 100–200 mg. Values shown are 5–10× above any plausible recreational range and overlap the lethal zone for barbiturates.
- **Severity**: BLOCKER

### Gaboxadol
- **Route / Field**: oral / duration offset and total
- **Shown**: offset 1m–3m, total 2m–5m
- **Expected**: offset ~1h–2h, total ~3h–5h — unit should be hours not minutes. Gaboxadol (THIP) has a t½ ~1.5h and a clinical sleep-maintenance duration of ~4–6h. A 2–5 minute total duration is physiologically impossible for any orally absorbed CNS depressant.
- **Severity**: BLOCKER

### Mephenaqualone
- **Route / Field**: oral / duration offset and total
- **Shown**: offset 10h–15h, total 15h–20h
- **Expected**: offset ~2h–4h, total ~5h–8h — Mephenaqualone is pharmacologically very similar to methaqualone (t½ ~2–3h). A 15–20h total duration is not supported by any primary source and would imply an elimination half-life comparable to a long-acting benzodiazepine, which is inconsistent with its quinazolinone structure.
- **Severity**: MAJOR

### Methocarbamol
- **Route / Field**: oral / heavy dose
- **Shown**: heavy ≥6000 mg
- **Expected**: heavy ≥4500 mg (or continuous from strong 3000–4500 mg) — the strong tier already reaches 4500 mg, but the heavy threshold jumps to 6000 mg, leaving a 1500 mg gap. More critically, 6000 mg approaches the clinical maximum single dose (4500–6000 mg) used only in tetanus, so ≥6000 mg as a "heavy recreational" threshold is implausibly high for harm-reduction context. The gap between strong ceiling and heavy floor is also structurally anomalous.
- **Severity**: MINOR


# Depressant_02

# Depressant_02 Verification Findings

### Noctec (chloral hydrate)
- **Route / Field**: oral / common dose
- **Shown**: common 200–500 mg
- **Expected**: common 500–1000 mg — the therapeutic hypnotic dose of chloral hydrate is 500–1000 mg; 200 mg is a threshold/light dose. The "common" tier appears shifted one step low.
- **Severity**: MAJOR

### Secobarbital
- **Route / Field**: oral / peak duration
- **Shown**: peak 4h–8h
- **Expected**: peak 1h–3h — secobarbital is a short-to-intermediate barbiturate; maximum CNS effect (peak) occurs within 1–3 h of ingestion. A 4–8 h peak window describes the offset/plateau phase, not the true peak.
- **Severity**: MAJOR

### Sonata (zaleplon)
- **Route / Field**: oral / total duration
- **Shown**: total 3h–6h
- **Expected**: total 1h–3h — zaleplon is specifically marketed as an ultra-short-acting Z-drug with a clinical duration of approximately 1–2 h and a t½ of ~1 h. A 3–6 h total is roughly 2× the expected window and misrepresents its defining characteristic.
- **Severity**: BLOCKER

### Zopiclone
- **Route / Field**: oral / peak duration
- **Shown**: peak 3h–4h
- **Expected**: peak 0.75h–2h — zopiclone Tmax is ~1–2 h; subjective peak effect tracks plasma peak. A 3–4 h peak window is implausibly late and would overlap with what should be the offset phase.
- **Severity**: MAJOR


# Dissociative_01

# Verification Findings — Dissociative_01

### Deschloroketamine
- **Insufflation / Common dose**
- **Shown**: 40–100 mg (piru-curated)
- **Expected**: 15–25 mg — psychonautwiki and drug.community agree on 15–25 mg; piru-curated value is 4–6× the tripartite community consensus for a notably potent ketamine analogue where overdose risk is real.
- **Severity**: BLOCKER

### Deschloroketamine
- **Oral / Common dose**
- **Shown**: 75–200 mg (piru-curated)
- **Expected**: 20–30 mg — three independent sources (psychonautwiki, tripsit, drug.community) all converge on 15–30 mg common oral; piru-curated value is 5–7× higher, dramatically outside the consensus harm-reduction window.
- **Severity**: BLOCKER

### Esketamine
- **Half-life**
- **Shown**: 7h
- **Expected**: ~10–12 min — esketamine (Spravato) elimination half-life is 7–12 minutes for the parent compound; 7 hours corresponds to the noresketamine metabolite, not esketamine itself. Using 7h would produce wildly incorrect PK calculations.
- **Severity**: BLOCKER

### HXE
- **Insufflation / Light dose range**
- **Shown**: light 40–20 mg
- **Expected**: light 20–40 mg — range is inverted (upper bound < lower bound), a data entry error.
- **Severity**: MAJOR

### Bromoketamine
- **Intramuscular / All doses**
- **Shown**: threshold 0.3 mg, common 0.7–1 mg, strong 1–1.2 mg, heavy ≥1.2 mg
- **Expected**: doses ~10–40× higher — bromoketamine is a ketamine analogue; IM ketamine analogue common doses are typically 20–75 mg range. Sub-milligram IM doses are implausibly low and suggest a mg/kg value was recorded as absolute mg or a decimal-place error occurred.
- **Severity**: BLOCKER

### Memantine
- **Oral / Common dose**
- **Shown**: common 20–40 mg (piru-curated)
- **Expected**: ~47–110 mg (recreational) — piru-curated matches the therapeutic Alzheimer's dosing range (10–20 mg/day maintenance), not the recreational dissociative range. Psychonautwiki (70–110 mg) and drug.community (47–62 mg) reflect actual recreational use; the curated value is the clinical dose, inappropriate context here.
- **Severity**: MAJOR

### MXP
- **Intravenous route**
- **Shown**: IV threshold 5 mg, common 20–40 mg
- **Expected**: Route should not exist — MXP (methoxphenidine) is exclusively documented via oral and insufflation routes in all harm-reduction literature; no IV use is documented and the compound is not formulated or characterized for injection. Displaying IV doses is a patient-safety hazard.
- **Severity**: BLOCKER

### Diphenidine
- **Inhalation / Onset duration**
- **Shown**: onset 30s–1.5m
- **Expected**: onset ~2–10 min — diphenidine has low vapor pressure and significant lipophilicity; even if vaporized, pulmonary absorption to CNS effect does not occur in 30 seconds (compare ketamine inhalation onset ~1–5 min for a far more volatile compound). A 30-second onset figure is not supported by any pharmacokinetic rationale and would lead users to redose dangerously early.
- **Severity**: MAJOR


# Dissociative_02

# Dissociative_02 Verification Findings

### PCP

- **Route / Field**: Oral / total duration
- **Shown**: 4h–8h (psychonautwiki)
- **Expected**: 6h–24h — PCP oral duration is well-established in clinical pharmacology and toxicology literature; 6–24 hours is the accepted range, with prolonged effects common in recreational doses. 4–8h is consistent with insufflated/smoked routes but significantly underestimates the oral route.
- **Severity**: BLOCKER

---

### PCP

- **Route / Field**: Inhalation, Insufflation, Oral — all dose tiers
- **Shown**: Identical values to PCE entry (psychonautwiki): threshold 1 mg, light 2–4 mg / 2–4 mg / 3–5 mg, common 4–8 mg / 4–8 mg / 5–10 mg, strong 8–12 mg / 8–15 mg / 10–15 mg
- **Expected**: PCP and PCE should not be byte-for-byte identical across all three routes and all duration phases — PCE (N-ethyl-PCP) is generally considered slightly more potent than PCP, implying somewhat lower dose thresholds. Verbatim duplication across both substances is a strong signal of a data copy/propagation error in the PsychonautWiki source or the merge pipeline.
- **Severity**: MAJOR

---

### S-Ketamine

- **Route / Field**: Insufflation / strong and heavy tiers absent
- **Shown**: threshold 28 mg, light 28–56 mg, common 56–84 mg — no strong or heavy tier listed
- **Expected**: Esketamine is ~2× more potent than racemic ketamine; racemic ketamine insufflation strong tier is typically ~100–150 mg, implying S-ketamine strong ≈ 50–75 mg — meaning the listed "common" top end (84 mg) already overlaps the expected strong tier. The absence of strong/heavy tiers leaves users without a ceiling reference and misclassifies high doses as common.
- **Severity**: MAJOR


# Dysdelic

### Salvinorin A
- **Sublingual / common dose**
- **Shown**: common 3–6 mg (piru-curated)
- **Expected**: ~0.5–1 mg; the alternate source (drug.community: common 500–1000 µg) aligns with Erowid, PsychonautWiki sublingual entries, and the Hooker et al. (2008) human study — sublingual absorption is more efficient than combustion losses suggest, and 3–6 mg would be an extreme dose by virtually all community and clinical accounts.
- **Severity**: MAJOR


# Empathogen_01

# Verification Findings — Empathogen_01

### 3-Fea
- **Route / Field**: insufflation / dose brackets
- **Shown**: common 35–60 mg, strong 50–60 mg
- **Expected**: strong lower bound should be ≥ common upper bound (≥60 mg); current brackets place the entire strong range (50–60) inside the common range (35–60), making them indistinguishable
- **Severity**: MAJOR

### 4,4-DMAR
- **Route / Field**: oral / common and strong doses
- **Shown**: common 60–120 mg, strong 120–200 mg
- **Expected**: common ≤~30–50 mg, strong ≤~60–80 mg; 4,4-DMAR was associated with multiple fatalities in the Netherlands and UK at estimated ingested doses of roughly 30–60 mg — listing 60–120 mg as "common" and up to 200 mg as "strong" dramatically overstates safe/typical use and presents a serious harm-reduction hazard
- **Severity**: BLOCKER

### A-PIHP
- **Route / Field**: inhalation / afterglow duration
- **Shown**: afterglow 6h–12h
- **Expected**: ≤1h–2h; α-PiHP is a short-acting pyrovalerone/cathinone whose total active duration is approximately 1–3h by inhalation — an afterglow of 6–12h (equalling or exceeding the entire active window of the parent class) is pharmacologically inconsistent and likely a data-entry error or misattribution from a different compound
- **Severity**: MAJOR


# Empathogen_02

### MDMA

- **Route / Field**: insufflation / duration onset
- **Shown**: onset 20m–1.16667h
- **Expected**: onset 5m–20m — insufflated MDMA reaches peak plasma rapidly; 70 minutes is the oral onset ceiling, not intranasal. The fractional hour (1.16667h) also signals a unit-conversion artifact (70 min ÷ 60).
- **Severity**: MAJOR

---

### PMA

- **Route / Field**: oral / doses (no strong/heavy tier shown)
- **Shown**: threshold 10 mg, light 20–40 mg, common 40–60 mg
- **Expected**: common ceiling should be ≤50 mg with an explicit "no strong dose — toxic threshold" note; 60 mg approaches the reported lethal range (fatalities documented at 50–130 mg). Displaying 60 mg as the top of "common" without a heavy/danger tier normalises a potentially lethal dose.
- **Severity**: BLOCKER

---

### PMMA

- **Route / Field**: oral / doses (single tier, no context)
- **Shown**: common 100–120 mg
- **Expected**: PMMA fatalities are documented at doses as low as 50–100 mg; 100–120 mg is within the range of reported lethal doses. No threshold or light tier is shown, and no heavy/danger ceiling, making this presentation misleading. The common range should not extend to 120 mg without explicit danger framing, or the range should be capped lower.
- **Severity**: BLOCKER

---

### MDEA

- **Route / Field**: oral / duration afterglow
- **Shown**: afterglow 12h–48h
- **Expected**: afterglow 2h–8h — MDEA has a shorter action and quicker resolution than MDMA; 48-hour afterglow is an MDMA value that appears to have bled across. Community reports consistently place MDEA afterglow under 12 hours.
- **Severity**: MAJOR

---

### Mephedrone

- **Route / Field**: oral / duration peak
- **Shown**: peak 2h–4h
- **Expected**: peak 30m–1.5h — oral mephedrone peaks rapidly (~1 h); a 4-hour peak window is inconsistent with its short half-life (~2 h) and community dose-timeline data.
- **Severity**: MAJOR


# Endocrine

No findings.

# Eugeroic

# Eugeroic Verification Findings

### Adrafinil
- **Oral / Common dose**
- **Shown**: 600–900 mg
- **Expected**: ~150–300 mg common. Both PsychonautWiki and TripSit agree on 250–400 mg; piru-curated overrides to nearly 3× that. Published harm-reduction and nootropic community consensus places common at 150–300 mg, with 600 mg being the upper bound of strong use. The piru-curated common tier is misaligned by ~2–3×.
- **Severity**: BLOCKER

### Adrafinil
- **Oral / Strong and Heavy thresholds**
- **Shown**: strong 900–1200 mg, heavy ≥1500 mg
- **Expected**: strong ≤600 mg, heavy ≤900 mg. Adrafinil is a prodrug with known hepatotoxicity; doses above 900 mg carry meaningful liver risk and are not documented as "recreational" in any harm-reduction source. Listing 1500 mg as merely "heavy" normalises a hepatotoxic dose range.
- **Severity**: BLOCKER

### Modafinil
- **Oral / Strong tier lower bound**
- **Shown**: strong starts at 200 mg
- **Expected**: strong should start at ≥300 mg. The WHO-approved and FDA-approved clinical dose for narcolepsy/shift-work disorder is 200 mg; labelling the standard therapeutic dose "strong" will mislead users into thinking they are taking more than a normal dose.
- **Severity**: MAJOR


# GABAergic

### Gabapentin
- **Route / Field**: oral / common dose
- **Shown**: 900–1500 mg (psychonautwiki)
- **Expected**: ~600–1200 mg. Harm-reduction community consensus (Erowid, drug.community: 300–900 mg, Bluelight) places recreational common well below 900 mg for most users; the 900–1500 mg range maps more accurately to "strong." The alternate source (drug.community common 300–900 mg) is more representative.
- **Severity**: MAJOR

### Pregabalin
- **Route / Field**: oral / total duration upper bound
- **Shown**: total 9h–17h (psychonautwiki)
- **Expected**: total ~6h–12h. Pregabalin elimination t½ is ~6h; recreational experience consistently reported as 6–10h in community literature (Erowid, Bluelight). A 17h upper bound is inconsistent with this PK profile and is not corroborated by clinical or community sources.
- **Severity**: MAJOR


# Gastrointestinal

### Droperidol
- **IV / Heavy threshold**
- **Shown**: heavy ≥10 mg
- **Expected**: ≥5 mg; droperidol carries an FDA Black Box Warning for dose-dependent QTc prolongation/torsades — current clinical practice caps IV doses at 2.5 mg for antiemesis and rarely exceeds 5 mg even for sedation; ≥10 mg represents a genuinely dangerous dose, not merely a "heavy" recreational threshold.
- **Severity**: BLOCKER

### Metoclopramide
- **Oral / Duration total**
- **Shown**: total 5h–8h
- **Expected**: total 1h–3h; pharmacodynamic GI effect duration per dose is ~1–2h (consistent with standard 3–4×/day dosing schedules); the 5.5h half-life governs plasma concentration, not clinical action duration.
- **Severity**: MAJOR

### Metoclopramide
- **Oral / Strong dose**
- **Shown**: strong 20–40 mg
- **Expected**: strong ≤20 mg; the FDA-labeled maximum single dose is 10–20 mg and maximum daily dose is 40 mg — 40 mg as a single-dose upper bound of "strong" conflates daily maximum with single-dose ceiling and substantially elevates tardive dyskinesia risk.
- **Severity**: MAJOR


# Nootropic

# Nootropic — Verification Findings

### Citicoline
- **oral / duration (total)**
- **Shown**: total 58h–74h (onset 1h–2h, comeup 2h–3h, peak 2.5h–3.5h, offset 30h–40h)
- **Expected**: total ~4h–8h. Citicoline's half-life is ~8h and its subjective/cognitive effects are typically reported as 4–6h; an offset of 30–40h and total of 58–74h appears to be a data-entry error — likely confusing cumulative choline-loading kinetics with a single-dose effect window.
- **Severity**: BLOCKER

### Bromantane
- **oral / duration (peak and total)**
- **Shown**: peak 4h–10h, total 16h–24h
- **Expected**: peak ~2h–5h, total ~6h–12h. Bromantane's reported half-life is ~10–12h, but subjective effects in community consensus and the limited published pharmacology are 6–10h total. The 16–24h total appears to be confusing elimination half-life (or terminal-phase AUC coverage) with subjective effect duration.
- **Severity**: MAJOR

### Noopept
- **oral / common dose**
- **Shown**: common 20–30 mg (piru-curated) — note: alternate source shown as tripsit: common 10 mg
- **Expected**: common 10 mg. The 10 mg oral dose is the universally established standard in every published human study, TripSit, PsychonautWiki, and community data. Doubling to 20–30 mg as the "common" value contradicts all reference sources and may mislead users into taking higher than established doses of a potent dipeptide.
- **Severity**: MAJOR


# Opioid_01

# Opioid_01 Verification Findings

### Acetylfentanyl
- **Sublingual / Common dose**
- **Shown**: common 10–15 mg, strong 15–20 mg (psychonautwiki)
- **Expected**: common ~0.25–0.75 mg, strong ~0.75–1.5 mg. Acetylfentanyl is ~15× more potent than morphine; documented fatal overdoses have occurred at doses of ~1–2 mg. A sublingual common of 10–15 mg is equivalent to ~150–225 mg oral morphine equivalents and is acutely lethal in opioid-naive individuals.
- **Severity**: BLOCKER

### Acetylfentanyl
- **Oral / Common dose**
- **Shown**: common 3–5 mg, strong 5–7 mg (tripsit)
- **Expected**: common ~0.5–2 mg, strong ~2–4 mg. Oral bioavailability is low but acetylfentanyl remains highly potent. Multiple overdose deaths have been documented at oral doses in the 2–5 mg range. Presenting 3–5 mg as "common" normalises a dose at the upper boundary of reported lethal exposures.
- **Severity**: BLOCKER

### Heroin
- **Intravenous / Peak duration**
- **Shown**: peak 1h–4h (psychonautwiki)
- **Expected**: peak 15–30 min. IV heroin (diacetylmorphine) has an extremely short peak owing to rapid deacetylation to 6-MAM and morphine; the rush is 5–15 min, subjective peak effect is 15–30 min. A 1–4 h peak is pharmacologically inconsistent with IV diacetylmorphine kinetics and is characteristic of oral/slow-release opioids.
- **Severity**: MAJOR

### Morphine
- **Intravenous / Onset**
- **Shown**: onset 0s–30s (psychonautwiki)
- **Expected**: onset ~1–5 min. IV morphine requires pulmonary circulation time (~30–60 s) plus CNS penetration; analgesia onset is clinically measured at 1–5 min. Zero-second onset is physically impossible for any intravenously administered drug.
- **Severity**: MAJOR

### Hydromorphone
- **Oral / Peak**
- **Shown**: comeup 1h–2h, peak 15m–20m (psychonautwiki)
- **Expected**: peak 30–60 min. The stated peak (15–20 min) is shorter than the stated comeup (1–2 h), which is logically impossible — peak cannot precede the end of the rise phase. Hydromorphone oral Tmax is 30–60 min per pharmacokinetic literature.
- **Severity**: MAJOR

### Furanylfentanyl
- **Oral / Common dose**
- **Shown**: common 500–900 µg, strong 900–1600 µg (tripsit)
- **Expected**: common ~100–300 µg. Furanylfentanyl potency is broadly comparable to fentanyl (perhaps 2–3× less potent). Oral fentanyl common is ~50–100 µg in this dataset. Oral furanylfentanyl at 500–900 µg common implies an ~10× potency discount vs. fentanyl with no established pharmacokinetic basis; community reports of overdose at sub-500 µg oral doses exist.
- **Severity**: MAJOR


# Opioid_02

# Opioid_02 Verification Findings

### Oxycodone
- **Route / Field**: intravenous / peak duration
- **Shown**: peak 3h–5h (psychonautwiki)
- **Expected**: ~5–15 min. IV oxycodone peak plasma concentration and clinical effect occur within minutes; 3–5h is the oral ER profile, not IV. The total and peak fields being identical (3h–5h) reinforces this is a copy-paste of the oral duration profile.
- **Severity**: MAJOR

---

### Propoxyphene
- **Route / Field**: oral / total duration
- **Shown**: total 1h–3h (tripsit)
- **Expected**: 4–6h. Propoxyphene has a t½ of 6–12h (norpropoxyphene active metabolite t½ ~30–36h); clinical duration of analgesia is 4–6h. 1–3h is about one-quarter of the true duration and could mislead users into re-dosing dangerously early.
- **Severity**: BLOCKER

---

### Sufentanil
- **Route / Field**: oral / total duration
- **Shown**: total 5m–10m (tripsit)
- **Expected**: 2–4h minimum. The 5–10 min duration is correct for IV sufentanil (ultra-short acting parenterally), not oral. Oral BA is ~12%; what reaches systemic circulation does so over 30–90 min and persists for hours. This entry appears to have inherited the IV duration profile verbatim. A user seeing 5–10 min total could fatally re-dose.
- **Severity**: BLOCKER

---

### Pethidine
- **Route / Field**: oral / peak duration
- **Shown**: peak 4h–6h (psychonautwiki)
- **Expected**: 1–2h. Meperidine oral peak plasma level and subjective effect occur at 1–2h post-dose (t½ ~3–5h). The 4–6h figure describes total duration, not peak — these fields appear swapped or duplicated. Afterglow 2–10h is plausible.
- **Severity**: MAJOR


# Other

# Verification Findings — Other

### APAP
- **Route / Field**: oral / common dose
- **Shown**: 200–500 mg
- **Expected**: 325–1000 mg — standard single therapeutic dose is 325 mg (low), 500 mg (regular), up to 1000 mg (max single); 200 mg is sub-therapeutic and not a recognized dose tier
- **Severity**: MINOR

### Apomorphine
- **Route / Field**: sublingual / threshold
- **Shown**: threshold 10 mg, light 10–15 mg
- **Expected**: threshold ~1–2 mg, light 2–4 mg — approved sublingual/buccal apomorphine (Kynmobi) is 10 mg as the *starting clinical dose for established Parkinson's patients*, not a threshold; naive-user threshold is far lower (~1–2 mg); listing 10 mg as threshold conflates a titrated maintenance dose with a true perceptual threshold
- **Severity**: MAJOR

### Naloxone
- **Route / Field**: oral / all dose tiers + duration
- **Shown**: threshold 4 mg, light 4–8 mg, common 8–16 mg, strong 16–28 mg, heavy ≥28 mg; onset 5m–15m, total 1h–2h
- **Expected**: oral naloxone bioavailability is ~2% due to near-complete first-pass metabolism; it has no meaningful systemic opioid-antagonist effect at these doses via oral route (it is used orally specifically *because* it is inactive, e.g., in Suboxone). A 5–15 min onset and 1–2h duration for oral dosing is pharmacokinetically impossible for a systemic effect. The entire oral dose block should be flagged or removed.
- **Severity**: BLOCKER

### Theobromine
- **Route / Field**: oral / total duration
- **Shown**: 30h–40h
- **Expected**: 6–10h — theobromine half-life is ~6–10h in humans; a 30–40h total duration would imply ~3–4 half-lives of accumulated effect, which is not consistent with single-dose subjective effects. Community reports and pharmacology literature describe effects lasting 6–10h. The 30–40h figure appears to be a confabulated value, possibly confused with theobromine's full metabolic clearance time rather than perceived effect duration.
- **Severity**: BLOCKER

### α-Pyrrolidinopropiophenone (α-PPP)
- **Route / Field**: intravenous / threshold and common dose
- **Shown**: threshold 20 mg, common 50–100 mg
- **Expected**: threshold ~2–5 mg, common ~10–25 mg — IV route for cathinones delivers full bioavailability with rapid CNS entry; IV doses are consistently 3–5× lower than oral for this drug class (cf. α-PVP, MDPV IV reports). A 20 mg IV threshold and 50–100 mg IV common dose mirror the *oral* dose ranges listed for the same substance, suggesting the IV tier was not adjusted for route. At these IV doses, cardiovascular toxicity and overdose risk would be extreme.
- **Severity**: MAJOR


# Peptide

# Peptide Verification Findings

### Semaglutide
- **Oral / Strong & Heavy doses**
- **Shown**: strong 14–25 mg, heavy ≥25 mg
- **Expected**: strong ≤14 mg, heavy tier should not exist or sit at ≥14 mg — the FDA-approved ceiling for oral semaglutide (Rybelsus) is 14 mg/day; the SNAC absorption-enhancer formulation is specifically engineered for ≤14 mg tablets, and no clinical data supports oral dosing above 14 mg
- **Severity**: BLOCKER

### Epitalon
- **Subcutaneous / Total duration**
- **Shown**: total 72h–168h (offset 48h–168h)
- **Expected**: total duration ≤12h — Epitalon is an unprotected tetrapeptide (Ala-Glu-Asp-Gly) with plasma half-life of ~1–2 min due to rapid peptidase cleavage; it has no known depot mechanism, sustained-release formulation, or receptor-mediated prolonged effect that would produce multi-day durations; the 72–168h total is inconsistent with the listed 30 min half-life and all available PK analogies for peptides of this class
- **Severity**: MAJOR

### CJC-1295
- **Subcutaneous / Heavy dose**
- **Shown**: heavy ≥2000 µg (gap: strong upper bound is 1000 µg)
- **Expected**: heavy ≥1000 µg — the strong tier ends at 1000 µg but heavy skips to ≥2000 µg, a 2× discontinuity not seen in any other peptide entry; research/clinical doses top out at 1000–2000 µg and ≥1000 µg is already "heavy" by convention
- **Severity**: MINOR


# Psychedelic_01

# Verification Findings — Psychedelic_01

### 25C-NBOH
- **sublingual / afterglow duration**
- **Shown**: 72h–144h (3–6 days)
- **Expected**: 4h–24h. NBOMe/NBOH afterglows are typically hours, not multi-day. 72–144h afterglow is inconsistent with the compound's short-to-moderate elimination profile and all community/harm-reduction reports. Compare 25I-NBOME sublingual afterglow on PsychonautWiki: 72h–144h — that value appears to have been copied incorrectly onto 25C-NBOH.
- **Severity**: MAJOR

### 25E-NBOH
- **sublingual / afterglow duration**
- **Shown**: 120h–240h (5–10 days)
- **Expected**: 4h–24h. Five to ten days of afterglow is pharmacologically implausible for any serotonergic phenethylamine; no elimination half-life mechanism could produce this. Likely a data entry error (hours confused with minutes, or field misassigned from a different row).
- **Severity**: BLOCKER

### 25I-NBOH
- **sublingual / afterglow duration**
- **Shown**: 72h–288h (3–12 days)
- **Expected**: 8h–48h. Even granting that 25I compounds can produce extended afterglows relative to other NBOHs, 12 days is not pharmacologically coherent. Community-reported afterglows for 25I-NBOH are hours to at most 1–2 days. The upper bound of 288h appears to be a magnitude error.
- **Severity**: BLOCKER

### 2C-F
- **oral / threshold and full range**
- **Shown**: threshold 100 mg, light 250–350 mg, common 350–500 mg, strong 500–750 mg, heavy ≥750 mg
- **Expected**: threshold ~10–20 mg, common ~25–75 mg. 2C-F (2,5-dimethoxy-4-fluorophenethylamine) is a Shulgin compound from PIHKAL with activity in the 10–40 mg range (PIHKAL #26: "10 to 40 mg"). The values shown are 10–20× too high; a 500 mg oral dose would be severely toxic. This appears to be a mg→µg confusion or source data error.
- **Severity**: BLOCKER

### 2C-G
- **oral / total duration**
- **Shown**: total 15h–35h
- **Expected**: 10h–20h. Shulgin's PIHKAL reports 2C-G lasting 18–30 hours at higher doses, which is unusually long but not entirely implausible given Shulgin's own notes. However, 35h at the upper bound exceeds even the longest anecdotal reports. MINOR concern — may reflect outlier reports.
- **Severity**: MINOR


# Psychedelic_02

# Verification Findings — Psychedelic_02

### 2C-N
- **Route / Field**: oral / dose
- **Shown**: light 100 mg, common 100–125 mg, strong 125–150 mg
- **Expected**: light ~50–75 mg, common ~75–100 mg — PIHKAL gives active range 100–150 mg for common but the "light" tier should be below the common floor, not equal to it; light = common here is a tier-collision artifact, not a genuine pharmacological error, but the absolute values are consistent with Shulgin's report so the common dose range itself is plausible. Skipping.

### 2C-T (the unsubstituted 2C-T)
- **Route / Field**: oral / duration peak
- **Shown**: peak 30m–1.91667h
- **Expected**: peak is a display artifact from a fractional-hours conversion (1h 55m → 1.91667h); should render as ~2h. Not a pharmacological error but a formatting bug. Skipping (out of scope for this pass).

### 2C-T-21
- **Route / Field**: oral / total duration
- **Shown**: total 10h–12h (psychonautwiki)
- **Expected**: 2C-T-21 is reported as a relatively short-acting thio-2C with most trip reports citing 4–6 h total; 10–12 h is implausibly long and ~2× community consensus.
- **Severity**: MAJOR

### 4-Aco-Det (inhalation)
- **Route / Field**: inhalation / total duration
- **Shown**: total 30m–1.5h (drug.community)
- **Expected**: 4-AcO-DET is a prodrug of 4-HO-DET; vaporized tryptamines typically last 1–3 h. A lower bound of 30 minutes is extremely short — Erowid and community reports consistently show 1–2 h minimum even by inhalation. 30 min lower bound is plausible only for a brief peak, not total duration.
- **Severity**: MINOR

### 4-HO-DMT / Psilocin (oral)
- **Route / Field**: oral / common dose
- **Shown**: common 10–20 mg (erowid-tihkal)
- **Expected**: Shulgin's own TIHKAL entry for psilocin lists active doses starting around 6–10 mg with a common range of 10–15 mg; 20 mg upper bound pushes into strong territory for most users. The range is defensible but slightly generous — not a clear blocker.
- **Severity**: MINOR

### 4-HO-DPT (oral)
- **Route / Field**: oral / threshold and dose tiers
- **Shown**: threshold 20 mg, light 40–60 mg, common 60–90 mg, strong 90–130 mg, heavy ≥130 mg (psychonautwiki)
- **Expected**: 4-HO-DPT threshold is consistent with trip reports (~15–25 mg), but the common dose of 60–90 mg oral is very high. Community data (Erowid, drug.community) places common oral at 20–40 mg; 60–90 mg is squarely in "strong to overwhelming" territory. The psychonautwiki figures appear to be systematically inflated by ~2×.
- **Severity**: MAJOR

### 3C-BZ (oral)
- **Route / Field**: oral / common dose range
- **Shown**: common 25–200 mg (erowid-pihkal)
- **Expected**: An 8× spread within a single "common" tier (25–200 mg) is not a dose range — it spans threshold to heavy for virtually any psychedelic. PIHKAL describes 3C-BZ as highly variable but the range as presented is too wide to be useful and likely collapses multiple tiers into one. Flagging as a data-quality issue.
- **Severity**: MINOR

### 4-Fluorophenylpiperazine
- **Route / Field**: oral / category classification
- **Shown**: listed under Psychedelic category
- **Expected**: 4-Fluorophenylpiperazine (4-FPP / pFPP) is a piperazine with primarily serotonergic/adrenergic activity; it is typically classified as a stimulant or entactogen, not a psychedelic. The dose ranges shown (40–80 mg common oral) are consistent with stimulant/piperazine literature. Misclassification under Psychedelic is an error, but dose values themselves are plausible for the compound.
- **Severity**: MAJOR


# Psychedelic_03

# Verification Findings — Psychedelic_03

### 4-HO-MET
- **Route / Field**: intravenous / duration total
- **Shown**: total 3h–7h
- **Expected**: ~1h–2h (possibly less). IV 4-HO-MET is extremely rarely documented; the few reports indicate a short, intense experience far shorter than oral. A 3–7h total for IV tryptamine is inconsistent with the route — IV tryptamines peak and resolve rapidly. Even oral 4-HO-MET is 4–6h; IV should be substantially shorter.
- **Severity**: MAJOR

### 5-MEO-MIPT
- **Route / Field**: inhalation / duration total
- **Shown**: total 5h–8h (psychonautwiki)
- **Expected**: ~30m–2h. Inhaled 5-MeO-MiPT (freebase volatilized) produces a short-duration experience analogous to other inhaled 5-MeO-tryptamines — typically under 2h. A 5–8h total duration for inhalation is implausible and contradicts TIHKAL data (3–6h oral). The [also: erowid-tihkal: common 4–6 mg] oral doses confirm this is likely a copy-paste of oral duration data into the inhalation route.
- **Severity**: BLOCKER

### 5-MEO-PYR-T
- **Route / Field**: oral / doses
- **Shown**: light 0.5–1 mg, common 1–1.5 mg, strong 1.5–2 mg
- **Expected**: TIHKAL reports active range 0.5–2 mg, consistent. However, the afterglow of 1h–36h is extremely wide; 36h afterglow for a compound with a ~2h total is implausible.
- **Route / Field**: oral / afterglow
- **Shown**: 1h–36h
- **Expected**: afterglow is typically proportional to experience length; a 36h ceiling for a sub-2mg, short-duration pyrrolidyl tryptamine is implausible. Same issue on inhalation route.
- **Severity**: MAJOR

### 5-MES-DMT
- **Route / Field**: oral / duration total
- **Shown**: total 15m
- **Expected**: 5-MeS-DMT (5-methylthio-DMT) is oral-route active per TIHKAL at 15–30 mg with a duration of ~1–2h. A 15-minute total oral duration is implausible — this appears to be a unit error (likely 15 minutes was meant to be 1.5h or the value was truncated).
- **Severity**: BLOCKER

### 5-Meo-Dibf
- **Route / Field**: oral / common dose
- **Shown**: common 80–110 mg (psychonautwiki) [also: tripsit: common 20–40 mg]
- **Expected**: 5-MeO-DIBF community reports cluster around 20–60 mg oral. The psychonautwiki 80–110 mg common dose is roughly 2–4× higher than tripsit and most documented experiences. The discrepancy is flagged by the [also:] note. The lower tripsit range is more consistent with the actual community data.
- **Severity**: MAJOR

### a-MT (alpha-methyltryptamine)
- **Route / Field**: oral / duration total
- **Shown**: total 12h–16h
- **Expected**: α-MT is well-documented in TIHKAL at 12–16h total duration. This is correct and should NOT be flagged — consistent with Shulgin's data and community experience.
- **Note**: No issue.

### AEM
- **Route / Field**: oral / doses
- **Shown**: threshold 220 mg
- **Expected**: AEM (4-acetoxy-N-ethyl-N-methyltryptamine or the phenethylamine AEM) — if this is the phenethylamine AEM (alpha-ethyl mescaline) from PIHKAL, doses in the 100–200 mg range are plausible. A threshold-only entry of 220 mg with no common/strong is sparse but not necessarily wrong. Insufficient data to flag.
- **Note**: Skip.


# Psychedelic_04

# Verification Findings — Psychedelic_04

### Changa
- **Route / Field**: oral / all dose fields
- **Shown**: light 5–15 mg, common 15–30 mg, strong 30–50 mg
- **Expected**: Changa is a smoking blend (DMT-infused herbs) — it is not taken orally. Oral dose fields are a categorical error; the route should be inhalation/smoking only.
- **Severity**: BLOCKER

### Changa
- **Route / Field**: oral / duration onset & total
- **Shown**: onset 0s–2m, total 6m–12m
- **Expected**: These durations match smoked Changa, not oral administration. Oral DMT-containing preparations with MAOI (ayahuasca model) have onset 20–60 min and total 4–8 h. The values here are simply the smoked values mis-assigned to the oral route.
- **Severity**: BLOCKER

### Cyclopropylmescaline
- **Route / Field**: oral / duration total
- **Shown**: total 12h–18h
- **Expected**: CPM is a mescaline analogue; community reports (Erowid, Shulgin analogues) consistently place total duration at 8–12 h. 12–18 h is implausibly long and not supported by any documented source.
- **Severity**: MAJOR

### DMT
- **Route / Field**: oral / common dose (drug.community winning)
- **Shown**: common 50–75 mg (with MAOI)
- **Expected**: Oral DMT with MAOI (ayahuasca equivalent) — common dose of 50–75 mg pure DMT is plausible and well-supported (Strassman, Riba). The erowid-tihkal alternate of 262.5–437.5 mg is almost certainly a unit/transcription error (those values make no pharmacological sense for pure freebase DMT). The winning value is correct; noting the alternate source is clearly wrong.
- **Severity**: MINOR (winning value is fine; alternate [also:] value is egregiously wrong — flag for data hygiene)

### DMPEA (3,4-Dimethoxyphenethylamine)
- **Route / Field**: oral / common dose
- **Shown**: common 750–1250 mg
- **Expected**: DMPEA (3,4-DMPEA) is essentially inactive as a psychedelic; Shulgin (PIHKAL #78) reports doses up to 1500 mg with no effects. The value is not pharmacologically implausible *per Shulgin's own data* but displaying it alongside active psychedelics without a note that it is essentially inert is misleading. If the intent is to flag active dose, there is none.
- **Severity**: MINOR

### DOET
- **Route / Field**: oral / duration afterglow
- **Shown**: afterglow 12h–72h
- **Expected**: DOET (Shulgin PIHKAL) has a total duration of 12–30 h. An afterglow of up to 72 h is extreme and not documented in PIHKAL or community sources; 12–24 h afterglow would be the outer limit.
- **Severity**: MAJOR

### DPT
- **Route / Field**: oral / threshold and dose range
- **Shown**: threshold 50 mg, light 75–150 mg, common 150–250 mg, strong 250–350 mg, heavy ≥350 mg
- **Expected**: Oral DPT has poor and unpredictable bioavailability; the primary active routes are insufflation, IM, and inhalation. While some sources list oral doses at these levels, the route is generally considered pharmacologically inefficient. More critically, a common oral dose of 150–250 mg is at the high end of what any source documents and the heavy threshold of ≥350 mg oral is not well-supported. Community consensus (Erowid, TiHKAL) places oral activity thresholds much lower (~75–100 mg). The common range shown is ~2× higher than expected.
- **Severity**: MAJOR

### Bufotenin
- **Route / Field**: inhalation / duration comeup
- **Shown**: comeup 15s–30s
- **Expected**: For smoked bufotenin, a comeup of 15–30 s is physiologically reasonable (similar to DMT inhalation). No issue here — skipping.

### BOB (4-Bromo-2,5-dimethoxybenzylamine / PIHKAL)
- **Route / Field**: oral / duration total
- **Shown**: total 10h–20h
- **Expected**: Shulgin reports BOB duration as 10–20 h in PIHKAL. Value is consistent with source.

No further findings.


# Psychedelic_05

### HARMINE

- **Route / Field**: oral / common dose
- **Shown**: 225–375 mg
- **Expected**: ~100–250 mg — Harmine is pharmacologically more potent than harmaline as a standalone psychedelic (higher CNS penetrance, direct 5-HT2A agonism, lower protein binding). Shulgin's TIHKAL notes harmine producing psychedelic effects at lower doses than harmaline; having harmine common (225–375 mg) exceed harmaline common (150–300 mg) inverts the potency relationship.
- **Severity**: MAJOR


# Psychedelic_06

# Verification Findings — Psychedelic_06

### MEE

- **Oral / Common dose**
- **Shown**: 3.45–5.75 mg
- **Expected**: ~1000–1500 mg. PIHKAL #100 (MEE, 3,4-dimethoxy-β-methylphenethylamine) is a phenethylamine active in the gram range, consistent with other PIHKAL entries in this series (MDPEA ~225–375 mg, MEPEA ~225–375 mg). 3.45–5.75 mg is roughly 300× too low and appears to be a unit-conversion or scaling artifact.
- **Severity**: BLOCKER

---

### Met (oral)

- **Oral / Common dose**
- **Shown**: 120–150 mg (psychonautwiki winning over tripsit 20–25 mg)
- **Expected**: 10–30 mg common. "Met" in this psychedelic context is methamphetamine. Oral recreational common dosing is well-established at 10–30 mg; 120–150 mg oral is approaching acute toxicity territory, not a common recreational dose. The tripsit value (20–25 mg) is pharmacologically correct and should be the winner given the 6× discrepancy rule.
- **Severity**: BLOCKER

---

### MiPLA (duration)

- **Oral / Total duration**
- **Shown**: total 4h–6h
- **Expected**: 8h–12h. MiPLA (N-isopropyl-N-methyl-d-lysergamide) is a lysergamide. All characterized lysergamides (LSD, ETH-LAD, AL-LAD, PRO-LAD, 1P-LSD) have total durations of 6–12h; 4–6h is at the very short end and inconsistent with the class. Community trip reports for MiPLA consistently describe 8–12h experiences. The 4–6h figure likely reflects an erroneously short source.
- **Severity**: MAJOR

---

### PARGY-LAD (oral / common dose)

- **Oral / Common dose**
- **Shown**: common 275–500 µg
- **Expected**: ~100–200 µg common. Pargy-LAD is a potent lysergamide with potency comparable to AL-LAD and ETH-LAD. Community reports and harm-reduction sources place the common recreational dose at 75–200 µg. 275–500 µg sits firmly in strong–heavy territory and would be an unusually high common dose for any lysergamide.
- **Severity**: MAJOR

---

### Para-Methoxyamphetamine (duration)

- **Oral / Total duration**
- **Shown**: 6h–24h
- **Expected**: 6h–8h (rarely up to 10h). PMA has a well-documented narrow therapeutic index and delayed onset (1–3h), but its total duration in survivors is 6–8h. A 24h upper bound is not pharmacologically supported and conflates prolonged toxicity/recovery with normal duration; it could lead users to dangerously underestimate residual serotonergic load.
- **Severity**: MAJOR

---

### T (tryptamine) — intravenous

- **Intravenous / Common dose**
- **Shown**: 187.5–312.5 mg IV
- **Expected**: 5–30 mg IV. TIHKAL describes tryptamine IV doses of approximately 5–20 mg producing effects; Szara's original 1956 experiments used ~0.7 mg/kg IM (≈50 mg for a 70 kg person at the high end). 187.5–312.5 mg IV would be an extreme overdose. This value appears to be a scaling artifact (likely taken from an oral phenethylamine formula and misapplied).
- **Severity**: BLOCKER

---

### Psilocin — insufflation / comeup (duration)

- **Insufflation / Duration breakdown**
- **Shown**: (no comeup listed — noted as absent, total via afterglow 3h–12h)
- **Note**: No direct duration issue with insufflation route. Passing.

---

### Psilocin — oral comeup

- **Oral / Comeup**
- **Shown**: 1.5h–3h
- **Expected**: 30m–1h. Psilocin (4-HO-DMT) does not require enzymatic dephosphorylation like psilocybin; it is the active compound directly. Oral comeup of 1.5–3h is characteristic of psilocybin mushrooms (where conversion is rate-limiting), not free psilocin. Free psilocin oral comeup is 20–45 min in clinical and community data.
- **Severity**: MAJOR


# Psychedelic_07

# Verification Findings — Psychedelic_07

### Truffles
- **Route / Field**: other / duration total
- **Shown**: total 3h–6h
- **Expected**: 4h–7h. Magic truffles (Psilocybe sclerotia) contain psilocybin; the experience onset-to-resolution is consistently 4–6h at common doses across Erowid, TripSit, and PsychonautWiki, with 3h being implausibly short even at the listed light dose of 0.5–1.5 g. Lower bound should be 4h.
- **Severity**: MINOR


# Stimulant_01

# Verification Findings — Stimulant_01

### 4-Methylaminorex (oral)
- **Route / Field**: oral / common dose
- **Shown**: 5–10 mg (tripsit)
- **Expected**: ~10–20 mg; community data shows common 10–25 mg and tripsit's own onset listed at 5m–15m (inconsistent with oral BA); 4-methylaminorex oral common is well-documented in the 10–20 mg range, with 5–10 mg being a light-to-threshold bracket in most reports.
- **Severity**: MAJOR

### 4-Methylaminorex (oral duration)
- **Route / Field**: oral / total duration
- **Shown**: 14h–18h (tripsit)
- **Expected**: 8h–14h; 4-methylaminorex half-life is ~7–9 h and experiential reports consistently place total duration at 8–14 h. 14–18 h is at the extreme outer edge and would only apply with very high doses; as a general "total" it is an overestimate.
- **Severity**: MINOR

### 2-Fa / 2-Fluoroamphetamine (oral peak)
- **Route / Field**: oral / peak duration
- **Shown**: 1h–2h (2-FA psychonautwiki entry)
- **Expected**: 2h–4h; 2-FA is consistently reported as having a notably longer peak than d-amphetamine (~3–5 h total, peak ~2–4 h). A 1–2 h peak is consistent with d-amphetamine, not 2-FA.
- **Severity**: MAJOR

### 3,4-CTMP (oral total duration)
- **Route / Field**: oral / total duration
- **Shown**: 6h–18h (psychonautwiki)
- **Expected**: 8h–24h (often 12–24 h); 3,4-CTMP is a long-acting phenidate with half-life estimated ~3–7 h but with prolonged CNS effects; community experience places total duration routinely at 12–24 h. The lower bound of 6 h significantly understates the drug's persistence and is a harm-reduction concern (re-dosing risk).
- **Severity**: MAJOR

### 4-CMC (oral common dose)
- **Route / Field**: oral / common dose
- **Shown**: 50 mg (tripsit — listed as just "50 mg" with no upper bound before heavy ≥100 mg)
- **Expected**: 50–100 mg common range; the entry shows `common 50 mg, heavy ≥100 mg` which creates no strong band between common and heavy. Based on cathinone class comparables and community reports, oral common for 4-CMC is ~60–100 mg. A point value of 50 mg with heavy starting at 100 mg leaves the common band undefined.
- **Severity**: MINOR

### 4-Fluoromethylphenidate (oral afterglow)
- **Route / Field**: oral / afterglow duration
- **Shown**: 5h–10h (tripsit)
- **Expected**: 1h–4h; 4F-MPH total duration is ~4–8 h; an afterglow of 5–10 h would extend past the total duration window, which is self-contradictory. Afterglow cannot exceed or nearly match total duration.
- **Severity**: BLOCKER


# Stimulant_02

# Verification Findings — Stimulant_02

### 4-Methylthioamphetamine (4-MTA)

- **Route / Field**: oral / duration total
- **Shown**: 8h–20h
- **Expected**: 4h–8h. 4-MTA is a potent irreversible MAO-B inhibitor with amphetamine-type stimulation; the psychoactive duration in human reports and case literature is 4–8 h. An upper bound of 20 h is implausible and conflates the MAO-B inhibition window (days) with subjective duration.
- **Severity**: MAJOR

---

### Cocaine (IV)

- **Route / Field**: intravenous / common dose
- **Shown**: 5–10 mg (psychonautwiki) [also: drug.community: 30–60 mg]
- **Expected**: 25–50 mg is the community-consensus IV common dose. The winning PsychonautWiki value of 5–10 mg is far below what experienced users self-administer intravenously; 5 mg IV cocaine is a threshold/light dose, not common. The drug.community alternate (30–60 mg) is closer to clinical and harm-reduction literature. The winning source should be reconsidered.
- **Severity**: MAJOR

---

### Caffeine (insufflation)

- **Route / Field**: insufflation / offset duration
- **Shown**: offset 6h–10h
- **Expected**: ~1h–2h. The offset phase for insufflated caffeine should be short (pharmacokinetics are fast intranasal); a 6–10 h offset is the systemic elimination half-life being mis-mapped to the "offset" phase field. Total duration of 1h–2.5h is correct, making an offset of 6–10 h internally inconsistent (longer than total).
- **Severity**: BLOCKER

---

### Caffeine (oral)

- **Route / Field**: oral / offset duration
- **Shown**: offset 6h–10h
- **Expected**: ~2h–3h. Same issue as insufflation: the caffeine elimination half-life (~5–6 h) is being placed in the offset field rather than informing the total. Oral total is listed as 2h–5h, so an offset of 6–10 h is self-contradictory.
- **Severity**: BLOCKER

---

### Buphedrone

- **Route / Field**: insufflation / threshold
- **Shown**: threshold 25 mg (piru-curated)
- **Expected**: ≤10 mg. Community reports and structural analogy to butylone/methylone place the insufflation threshold at 5–10 mg. A 25 mg threshold is implausibly high for a cathinone active by insufflation — that value is closer to a light dose.
- **Severity**: MAJOR

---

### Butylone

- **Route / Field**: oral / common dose
- **Shown**: 150–250 mg (piru-curated)
- **Expected**: 75–150 mg. The winning piru-curated value conflicts with the cited TripSit alternate (common 70–100 mg). Community harm-reduction consensus and structural analogy to MDMA place common oral butylone at 75–150 mg; 150–250 mg encroaches on heavy territory and mis-sets user expectations.
- **Severity**: MAJOR

---

### Desoxypipradrol (2-DPMP)

- **Route / Field**: insufflation / onset
- **Shown**: onset 15m–4h
- **Expected**: 15m–45m. A 4-hour upper bound on onset is an extreme outlier. While 2-DPMP is notoriously long-duration, onset after insufflation is typically within 15–45 minutes; the 4 h figure likely reflects a rare delayed-absorption edge case being treated as the upper bound of normal onset.
- **Severity**: MINOR



# Stimulant_03

### Focalin (Dexmethylphenidate)
- **Oral / Total Duration**
- **Shown**: total 9h–12h
- **Expected**: 4h–6h. Focalin IR (dexmethylphenidate) has a t½ ~2–3 h and clinical duration of 4–6 h. The 9–12 h figure belongs to Focalin XR, not the IR formulation that community dose sources describe.
- **Severity**: MAJOR

### Kratom
- **Oral / Total Duration**
- **Shown**: offset 3h–6h, total 2h–4h
- **Expected**: total should be ≥4h–6h (offset cannot exceed total). The stated offset window (3–6 h) is longer than the stated total duration (2–4 h), which is internally incoherent and undersells actual duration; community and clinical reports consistently place kratom oral total at 4–6 h.
- **Severity**: MAJOR

### Methcathinone
- **Oral / Common Dose**
- **Shown**: common 100–200 mg (psychonautwiki) [also: drug.community: common 25–50 mg]
- **Expected**: common 25–75 mg. Methcathinone is a potent cathinone stimulant; 100–200 mg oral is a heavy/toxic range. The drug.community figure of 25–50 mg is more consistent with published harm-reduction literature and EMCDDA reports.
- **Severity**: MAJOR

### Methylphenidate
- **Oral / Total Duration**
- **Shown**: total 2.5h–4h
- **Expected**: total 3h–5h (IR). Standard-release methylphenidate clinical duration is 3–5 h; 2.5 h as a lower bound is slightly short but borderline. The peak window (1h–1.5h) combined with offset (45m–1h) arithmetically sums to well under the stated total, suggesting the total field is already compressed. Minor inconsistency only.
- **Severity**: MINOR

### Pentedrone
- **Insufflation / Common Dose**
- **Shown**: common 75–125 mg (piru-curated), overriding psychonautwiki/tripsit common 5–10 mg
- **Expected**: common 10–40 mg insufflated. Pentedrone is a potent nor-cathinone; the two independent sources (PsychonautWiki and TripSit) both cite common insufflation at 5–10 mg. Piru-curated value of 75–125 mg is 7–12× higher and would place a common dose in territory associated with severe cardiovascular toxicity and psychosis in case reports.
- **Severity**: BLOCKER

### N-Methylbisfluoromodafinil
- **Oral / Total Duration**
- **Shown**: total 5h–8h
- **Expected**: 10h–20h+. Bisfluoromodafinil (flmodafinil/CRL-40,940) has a substantially longer half-life than modafinil (~10–15 h); the N-methyl derivative is not shorter. Community reports consistently place total duration at 12–20 h. A 5–8 h total is implausible and would lead users to re-dose unsafely.
- **Severity**: BLOCKER

### Nm-2-ai
- **Oral / Threshold vs Light Dose**
- **Shown**: threshold 5 mg, light 50–100 mg
- **Expected**: there is a ~10× gap between threshold (5 mg) and the bottom of the light range (50 mg) with no common range filling it. If threshold is correct at 5 mg, light should begin around 10–20 mg. Alternatively if light 50 mg is correct, threshold should be ~20–30 mg. The current gap is pharmacologically incoherent.
- **Severity**: MAJOR


# Stimulant_04

### Phentermine
- **Oral / Onset**
- **Shown**: onset 4h–6h
- **Expected**: onset 30m–2h. Phentermine reaches peak plasma in ~3–4h but CNS onset of appetite suppression/stimulation begins within 30–60min of oral dosing; a 4–6h onset is implausibly delayed and almost certainly a copy-paste of the absorption half-life.
- **Severity**: MAJOR

### Sibutramine
- **Oral / Total duration**
- **Shown**: 18h–30h
- **Expected**: 12h–20h. Sibutramine's active metabolites (M1/M2) have t½ ~14–16h giving effective duration of roughly 12–20h. A lower bound of 18h is plausible but an upper bound of 30h overstates it; the published norepinephrine/serotonin reuptake inhibition duration does not extend to 30h in clinical PK data.
- **Severity**: MINOR

### Troparil
- **Oral / Total duration**
- **Shown**: 45m–1.16667h
- **Expected**: expressed cleanly as 45m–1h10m or 45m–1.25h; the value 1.16667h is a raw decimal conversion of 70 minutes (70/60) and was not rounded before display — this is a data-formatting defect that surfaces an implausibly precise figure to users.
- **Severity**: MINOR

### Vyvanse
- **Oral / Strong dose**
- **Shown**: strong 50–100 mg
- **Expected**: strong 50–70 mg. Lisdexamfetamine (Vyvanse) is limited to a maximum prescribed dose of 70 mg/day; 100 mg would represent ~140% of the clinical ceiling and yields a d-amphetamine load (~29 mg) well into cardiovascular risk territory. A strong ceiling of 100 mg is pharmacologically implausible for a general-population harm-reduction reference and likely reflects a data entry error.
- **Severity**: BLOCKER


# Supplement_01

# Verification Findings — Supplement_01

### CoQ10
- **oral / half-life**
- **Shown**: 96h
- **Expected**: ~33–52h — multiple plasma kinetic studies (Tomono et al. 2009; Miles et al. 2002) converge on a T½ of ~33–34h, with upper-range estimates ~52h after oral ubiquinol/ubiquinone loading. 96h (4 days) has no clinical literature support.
- **Severity**: MAJOR

### Vitamin A
- **oral / half-life**
- **Shown**: 576h (24 days)
- **Expected**: ~2880–3696h (120–154 days) — retinol whole-body T½ is consistently reported as 128–154 days in stable-isotope dilution studies (Furr et al.; Ross & Harrison). 576h is roughly 5–6× too short and would cause the app to vastly underestimate accumulation risk for a fat-soluble, teratogenic vitamin.
- **Severity**: BLOCKER

### Vitamin B1 (Thiamine)
- **oral / half-life**
- **Shown**: 18h
- **Expected**: ~216–444h (9–18.5 days) — plasma thiamine T½ from pharmacokinetic studies is 9–18.5 days, not 18 hours. At 18h the app will fail to warn users that high-dose thiamine accumulates over weeks and will underestimate any tissue saturation.
- **Severity**: MAJOR

### Vitamin B6
- **oral / half-life**
- **Shown**: 24h
- **Expected**: ~360–600h (15–25 days) — pyridoxal-5-phosphate (the active form) has a tissue T½ of ~25 days; even plasma pyridoxine clears on a multi-day timescale. 24h would dramatically underestimate accumulation risk, which is safety-relevant given B6's known peripheral neuropathy risk at chronic high doses (>200 mg/day).
- **Severity**: BLOCKER

### Vitamin E
- **oral / half-life**
- **Shown**: 24h
- **Expected**: ~48–52h — alpha-tocopherol plasma T½ is consistently reported as 48–52h (Burton et al.; Traber). 24h is approximately half the established value and will underestimate accumulation for this fat-soluble vitamin.
- **Severity**: MINOR

### L-Theanine
- **oral / half-life**
- **Shown**: 1h
- **Expected**: ~3–5h — human PK studies (Türközü & Şanlier review; Higashiyama et al. 2011) report plasma T½ of ~3–5h after 200 mg oral doses. 1h reflects the absorption-phase half-life, not the elimination T½, and will cause the duration display to cut off well before effects dissipate.
- **Severity**: MINOR

### PQQ
- **oral / half-life**
- **Shown**: 4h
- **Expected**: ~7–8h — Smidt et al. (1991, J Nutr) measured a plasma elimination T½ of ~7.5h in humans after oral PQQ. 4h is roughly half the measured value.
- **Severity**: MINOR


# Supplement_02

### Vitamin K2

- **oral / duration — offset**
- **Shown**: 72h–168h
- **Expected**: ~4h–24h. The offset phase duration of 3–7 days conflates pharmacokinetic half-life (MK-7 t½ ≈ 72h) with experiential duration; a supplement has no meaningful pharmacodynamic "offset" lasting a week.
- **Severity**: MAJOR

- **oral / duration — total**
- **Shown**: 120h–240h (5–10 days)
- **Expected**: ~8h–36h total. A 5–10 day total duration window is not clinically meaningful as a dose-tracking duration; again reflects confusion between elimination half-life and duration of effect.
- **Severity**: MAJOR

---

### Zinc Picolinate

- **oral / common dose**
- **Shown**: 25–50 mg
- **Expected**: 10–25 mg. The established tolerable upper intake level (UL) for zinc is 40 mg/day; placing 25–50 mg in the "common" band normalises doses that partially exceed the safety threshold.
- **Severity**: MAJOR

- **oral / strong dose**
- **Shown**: 50–100 mg
- **Expected**: ≤40 mg ceiling for strong; anything above 40 mg should carry a heavy/caution label given the UL. Labelling 50–100 mg as merely "strong" understates toxicity risk (nausea, copper depletion begin at 50+ mg chronically).
- **Severity**: MAJOR


# Uncategorized

### Blue Lotus
- **Oral / Onset duration**
- **Shown**: 10s–1m
- **Expected**: 15–45 min — oral absorption of aporphine alkaloids (nuciferine) through GI mucosa cannot produce effects in seconds; sub-minute onset is physically impossible for this route.
- **Severity**: BLOCKER
