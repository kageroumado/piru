# Verification Findings — Psychedelic_03

### 4-Ho-Mpmi
- **Route / Field**: oral / dose range unit inconsistency
- **Shown**: threshold 500, light 750 µg, common 1–2 µg
- **Expected**: common 1–2 **mg**. The threshold (500 µg) and light (750 µg) are in micrograms, but common drops to 1–2 µg — which is *lower* than threshold, pharmacologically impossible. Almost certainly a unit encoding error: common should be 1–2 mg (i.e., 1000–2000 µg), consistent with the ascending threshold → light → common sequence.
- **Severity**: BLOCKER (common dose shown as 1–2 µg is sub-threshold by its own scale; if a user interprets this as micrograms they may radically overdose trying to "reach" the stated common dose)

---

### 5-Bromo-DMT
- **Route / Field**: inhalation / total duration
- **Shown**: total 15h–90h
- **Expected**: ~15 min–2 h. Vaporized tryptamines characteristically produce short-duration experiences (minutes to ~1–2 h). A 15–90 hour inhaled duration is pharmacologically implausible for any tryptamine; this figure may have been erroneously copied from a speculative oral/enteral dataset or confused with half-life data.
- **Severity**: BLOCKER (a user could believe an hours-long crisis is still within expected duration and delay seeking help, or conversely panic unnecessarily)

---

### 5-Meo-Dalt
- **Route / Field**: inhalation / total duration
- **Shown**: total 15m–20m
- **Expected**: ~30 min–1 h. 5-MeO-DALT is a long-chain tryptamine; community reports for vaporized administration consistently indicate 30–60 min total. The 15–20 min figure matches vaporized DMT or 5-MeO-DMT, not 5-MeO-DALT, suggesting DMT duration data was applied here.
- **Severity**: MAJOR (undershoots by ~2×; user may re-dose prematurely thinking the experience has ended)

---

### 5-MEO-MIPT
- **Route / Field**: inhalation / total duration
- **Shown**: onset 20m–1h, peak 1h–2h, offset 1h–2h, total 5h–8h
- **Expected**: total ~1–3 h for vaporized route. 5-MeO-MiPT inhaled produces a short, intense experience; a 5–8 hour total duration matches the *oral* profile, not inhalation. Onset of 20 min–1 h for an inhaled substance is also implausible (should be seconds to minutes).
- **Severity**: MAJOR (oral duration data appears to be displayed for the inhalation route; onset and total duration are both wrong for this ROA)
