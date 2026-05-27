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
