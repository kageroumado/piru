# Verification Findings — Psychedelic_04

### Changa
- **Route / Field**: oral / all dose fields
- **Shown**: light 5–15 mg, common 15–30 mg, strong 30–50 mg
- **Expected**: Changa is a smoking blend (DMT-infused herbs) — it is not taken orally. Oral dose fields are a categorical error; the route should be inhalation/smoking only.
- **Severity**: BLOCKER

### Changa
- **Route / Field**: oral / duration onset & total
- **Shown**: onset 0s–2m, total 6m–12m
- **Expected**: These durations match smoked Changa, not oral administration. Oral DMT-containing preparations with MAOI (ayahuasca model) have onset 20–60 min and total 4–8 h. The values here are simply the smoked values mis-assigned to the oral route.
- **Severity**: BLOCKER

### Cyclopropylmescaline
- **Route / Field**: oral / duration total
- **Shown**: total 12h–18h
- **Expected**: CPM is a mescaline analogue; community reports (Erowid, Shulgin analogues) consistently place total duration at 8–12 h. 12–18 h is implausibly long and not supported by any documented source.
- **Severity**: MAJOR

### DMT
- **Route / Field**: oral / common dose (drug.community winning)
- **Shown**: common 50–75 mg (with MAOI)
- **Expected**: Oral DMT with MAOI (ayahuasca equivalent) — common dose of 50–75 mg pure DMT is plausible and well-supported (Strassman, Riba). The erowid-tihkal alternate of 262.5–437.5 mg is almost certainly a unit/transcription error (those values make no pharmacological sense for pure freebase DMT). The winning value is correct; noting the alternate source is clearly wrong.
- **Severity**: MINOR (winning value is fine; alternate [also:] value is egregiously wrong — flag for data hygiene)

### DMPEA (3,4-Dimethoxyphenethylamine)
- **Route / Field**: oral / common dose
- **Shown**: common 750–1250 mg
- **Expected**: DMPEA (3,4-DMPEA) is essentially inactive as a psychedelic; Shulgin (PIHKAL #78) reports doses up to 1500 mg with no effects. The value is not pharmacologically implausible *per Shulgin's own data* but displaying it alongside active psychedelics without a note that it is essentially inert is misleading. If the intent is to flag active dose, there is none.
- **Severity**: MINOR

### DOET
- **Route / Field**: oral / duration afterglow
- **Shown**: afterglow 12h–72h
- **Expected**: DOET (Shulgin PIHKAL) has a total duration of 12–30 h. An afterglow of up to 72 h is extreme and not documented in PIHKAL or community sources; 12–24 h afterglow would be the outer limit.
- **Severity**: MAJOR

### DPT
- **Route / Field**: oral / threshold and dose range
- **Shown**: threshold 50 mg, light 75–150 mg, common 150–250 mg, strong 250–350 mg, heavy ≥350 mg
- **Expected**: Oral DPT has poor and unpredictable bioavailability; the primary active routes are insufflation, IM, and inhalation. While some sources list oral doses at these levels, the route is generally considered pharmacologically inefficient. More critically, a common oral dose of 150–250 mg is at the high end of what any source documents and the heavy threshold of ≥350 mg oral is not well-supported. Community consensus (Erowid, TiHKAL) places oral activity thresholds much lower (~75–100 mg). The common range shown is ~2× higher than expected.
- **Severity**: MAJOR

### Bufotenin
- **Route / Field**: inhalation / duration comeup
- **Shown**: comeup 15s–30s
- **Expected**: For smoked bufotenin, a comeup of 15–30 s is physiologically reasonable (similar to DMT inhalation). No issue here — skipping.

### BOB (4-Bromo-2,5-dimethoxybenzylamine / PIHKAL)
- **Route / Field**: oral / duration total
- **Shown**: total 10h–20h
- **Expected**: Shulgin reports BOB duration as 10–20 h in PIHKAL. Value is consistent with source.

No further findings.
