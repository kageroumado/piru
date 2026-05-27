### Cannabis
- **Route / Field**: inhalation / common dose
- **Shown**: 2–4 mg (THC)
- **Expected**: ~5–20 mg THC; community consensus (Erowid, PsychonautWiki community data, TripSit) places a common inhaled cannabis dose at roughly 5–25 mg THC for most users. The 2–4 mg range is closer to a light/threshold experience for most people.
- **Severity**: MAJOR

---

### THC
- **Route / Field**: inhalation / light dose
- **Shown**: 2–5 mg, common 10–25 mg
- **Expected**: The gap between light (2–5 mg) and common (10–25 mg) is unusually large — common should start closer to 5 mg. However the common range itself (10–25 mg) is plausible for experienced users; the lower bound of the light range being the same as oral threshold is internally consistent. Not flagging the range itself, but noting the discontinuity between light top (5 mg) and common bottom (10 mg) leaves 5–10 mg with no tier.
- **Severity**: MINOR

---

### Nabilone
- **Route / Field**: oral / half-life
- **Shown**: 2h
- **Expected**: ~35h (nabilone t½ is 35 hours per FDA prescribing information / Cesamet label; its active metabolite has an even longer t½ of ~80h). A 2h half-life is off by roughly 17×.
- **Severity**: BLOCKER

---

### JWH-073
- **Route / Field**: inhalation / offset duration
- **Shown**: offset 5m–10m
- **Expected**: ~20–45 min; for a synthetic cannabinoid with a 1–2h total duration, a 5–10 minute offset phase is implausibly short and internally inconsistent (onset is listed as 5–10m, meaning offset equals onset time, which compresses the descending limb to essentially nothing relative to the overall 1–2h total).
- **Severity**: MINOR

---

### THJ-2201
- **Route / Field**: inhalation / offset duration
- **Shown**: offset 0s
- **Expected**: non-zero; a 0-second offset is pharmacologically impossible — it implies instantaneous termination of effect with no come-down phase. Likely a data/ingester artifact (missing value parsed as zero).
- **Severity**: MAJOR

---

### AMB-CHMICA
- **Route / Field**: inhalation / threshold dose
- **Shown**: threshold 100 (unit ambiguous — appears to be µg given the range that follows is 100–250 µg)
- **Expected**: The threshold value of "100" with no unit, followed by "light 100–250 µg", suggests the threshold field is missing its unit label. The numeric value of 100 µg is itself pharmacologically plausible for AMB-CHMICA (a potent indazole-3-carboxamide), but the display will show "threshold 100" without a unit, which is dangerous — a user could interpret it as 100 mg.
- **Severity**: BLOCKER
