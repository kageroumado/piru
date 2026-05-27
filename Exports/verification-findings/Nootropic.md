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
