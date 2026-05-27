# Verification Findings — Supplement_02.txt

### Zinc Picolinate
- **Route / Field**: oral / half-life
- **Shown**: 24h
- **Expected**: ~1–2h plasma half-life (zinc redistributes rapidly into erythrocytes and tissues after absorption; plasma Zn t½ measured in healthy adults is 1–2h, not a day)
- **Severity**: MAJOR (off by ~12–24×; will make the app's "active window" visualization wildly incorrect)

### Zinc Picolinate
- **Route / Field**: oral / strong dose and heavy dose
- **Shown**: strong 50–100 mg, heavy ≥100 mg
- **Expected**: strong ~40 mg, heavy ≥50 mg — the NIH tolerable upper intake level (UL) for elemental zinc in adults is 40 mg/day; 50–100 mg regularly causes nausea/vomiting and copper deficiency; ≥100 mg is medically significant acute toxicity territory
- **Severity**: BLOCKER (labelling a dose well above the established UL as merely "strong" normalises harmful intake; a user could interpret this as a reasonable upper-recreational range)
