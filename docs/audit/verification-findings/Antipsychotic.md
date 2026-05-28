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
