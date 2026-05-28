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
