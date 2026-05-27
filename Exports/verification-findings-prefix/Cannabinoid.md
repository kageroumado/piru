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
