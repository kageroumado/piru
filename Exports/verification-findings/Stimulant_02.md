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
