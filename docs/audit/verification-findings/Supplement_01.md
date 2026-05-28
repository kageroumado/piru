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
