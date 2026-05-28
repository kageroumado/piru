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
