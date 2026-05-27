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
