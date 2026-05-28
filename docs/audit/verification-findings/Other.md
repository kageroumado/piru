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
