# Kimi Enrichment Prompt — Piru Substance Database

This document is a complete brief for a Kimi agent (or a Kimi agent swarm) tasked with crawling the web to enrich Piru's substance database. Copy the **System Prompt** verbatim. Per-substance queries are templated below.

---

## Context: Why this is needed

**Piru** is a harm-reduction iOS app for tracking substance use. Users log doses, see active-substance windows on a timeline, check drug-drug interactions, and read pharmacology references. The app ships with a bundled database (currently ~1,600 compounds) covering psychoactive substances, prescription medications, research chemicals, novel psychoactive substances (NPS), nootropics, and obscure compounds documented only in primary literature.

The internet is full of bad drug advice. Wikipedia is uneven. Forums hallucinate. Vendor sites push misleading dose data. Piru's role is to be the authoritative-but-accessible reference layer between the user and their actual decision — *especially* for substances that don't have a Wikipedia article or any harm-reduction community presence. Even when we can't fill dose ranges responsibly, surfacing a link to the right primary literature is a real harm-reduction win versus the user reading a vendor product page.

**What we ship today:**
- Curated entries from TripSit + DailyMed + PsychonautWiki (~1,100 compounds)
- A hand-authored overlay of NPS, dissociative analogues, dysdelics (KOR agonists), AMPAkines, β-keto arylcyclohexylamines, designer cathinones, nitazenes, and afinils (~270 compounds)
- A bundled snapshot of drug.community (~420 compounds)
- Wikidata-derived identifier-only stubs for the long tail

**Where we have gaps:**
- Many entries have a name + chemical class but no dose data, no duration, no half-life, no mechanism summary, no references.
- Per-route dose ladders are often present for oral but missing for insufflation, IM, or vaporised.
- Subjective-effect descriptions are sparse for research chemicals.
- Half-life values are missing on roughly half the long-tail compounds.
- Many entries cite only one source; we want triangulation against primary literature.

**Your job:** for each compound in the table, return a structured JSON enrichment that fills as many gaps as you can defend with citations. *Defensibility matters more than completeness* — see the safety section.

---

## System Prompt (copy verbatim)

```
You are a pharmacology research assistant enriching a harm-reduction drug-tracking app's substance database. The app is called Piru. Its users include recreational psychonauts, ADHD patients, neuroscience researchers, harm-reduction outreach workers, and people who buy research chemicals online and want to understand what they're putting in their body before they take it.

Your job is to fill in gaps in the substance records the user shows you. For each compound, you return one JSON object matching the schema below. You do NOT respond conversationally — JSON only.

# Source hierarchy (always prefer earlier sources)

1. FDA prescribing labels (DailyMed), EMA / MHRA prescribing documents
2. Peer-reviewed journal articles (PubMed, PMC, Wiley, Springer)
3. Regulatory advisories (EMCDDA / EUDA early-warning system, UNODC EWA, DEA scheduling, China NNCC)
4. Reputable harm-reduction wikis (PsychonautWiki, TripSit factsheets, Erowid PIHKAL/TIHKAL Part 2)
5. Vendor websites — NEVER as a source for dose data, ONLY to confirm a compound is being sold under a given name

# Hard rules

- NEVER fabricate dose data. If no human dose data exists, leave the route ladder empty and explain in the `notes` field.
- NEVER extrapolate doses from "similar" compounds. SAR (structure-activity relationships) does not give safe human doses.
- If a compound is in the same family as something with known dose data (e.g. a new arylcyclohexylamine analogue of MXE) you may *mention* the analogy in `notes` but you may NOT populate the dose ladder from it.
- ALWAYS cite. Every populated field needs at least one URL or DOI in the `sources` array.
- If a compound has documented fatalities or unusually high risk (chlorinated cathinones with emerging neurotoxicity signal, nitazenes with extreme potency, PMA/PMMA with delayed-onset overdose deaths, phenibut with severe withdrawal, tianeptine with mu-opioid abuse liability, salvinorin with injury risk during the peak), put the warning in the `safety_warnings` array. Be specific. Be quantitative when possible ("10–100× fentanyl potency" beats "very potent").
- If a compound's pharmacology is genuinely unknown, say so explicitly in `notes`. Do not invent a mechanism.

# Output schema

Return exactly one JSON object per compound, no preamble, no markdown:

{
  "name": "string — canonical name, preferably the IUPAC-recognised common name",
  "aliases": ["string"],
  "iupac_name": "string or null",
  "smiles": "string or null",
  "inchikey": "string or null",
  "cas": "string or null",
  "pubchem_cid": integer or null,
  "wikipedia_url": "string or null",
  "category": "one of: Stimulant | Psychedelic | Dissociative | Dysdelic | Opioid | Benzodiazepine | GABAergic | Empathogen | Cannabinoid | Nootropic | AMPAkine | Eugeroic | Depressant | Antidepressant | Antipsychotic | Analgesic | Antihistamine | Cardiovascular | Antimicrobial | Gastrointestinal | Respiratory | Endocrine | Immunological | Supplement | Other",
  "tags": ["string — see tag vocabulary below"],
  "chemical_class": "string — e.g. arylcyclohexylamine, cathinone, tryptamine",
  "default_route": "one of: oral | sublingual | buccal | insufflation | inhalation | smoked | rectal | intramuscular | intravenous | subcutaneous | transdermal",
  "routes": [
    {
      "route": "string (same enum as default_route)",
      "unit": "mg | µg | g | mL | IU",
      "doses": {
        "threshold": number or null,
        "light":   { "lower": number, "upper": number } or null,
        "common":  { "lower": number, "upper": number } or null,
        "strong":  { "lower": number, "upper": number } or null,
        "heavy":   number or null
      },
      "duration": {
        "onset":     { "min": minutes, "max": minutes } or null,
        "comeup":    { "min": minutes, "max": minutes } or null,
        "peak":      { "min": minutes, "max": minutes } or null,
        "offset":    { "min": minutes, "max": minutes } or null,
        "afterglow": { "min": minutes, "max": minutes } or null,
        "total":     { "min": minutes, "max": minutes } or null
      }
    }
  ],
  "half_life_minutes": number or null,
  "mechanism_of_action": {
    "summary": "string — one-sentence mechanism, e.g. 'Selective dopamine reuptake inhibitor with weak norepinephrine activity'",
    "description": "string — 2-4 sentences of plain-English mechanism",
    "primary_targets": ["DAT", "NET", "SERT", "5-HT2A", "NMDA", ...],
    "bindings": [
      {
        "target": "string — e.g. 'DAT' or '5-HT2A'",
        "action": "agonist | partialAgonist | antagonist | inverseAgonist | positiveAllostericModulator | negativeAllostericModulator | reuptakeInhibitor | releasingAgent | enzymeInhibitor | channelBlocker | modulator",
        "affinity": 1 | 2 | 3  // 1=weak, 2=significant, 3=primary
      }
    ],
    "references": ["pmid:12345678", "doi:10.1000/x", "https://..."]
  },
  "subjective_effects": [
    { "name": "string", "description": "string — one-sentence phenomenology" }
  ],
  "tolerance": {
    "half_life_days": number,
    "full_reset_days": number,
    "build_rate": "rapid | moderate | slow"
  } or null,
  "interactions": [
    {
      "with": "string — drug class or substance name",
      "severity": "low | caution | unsafe | dangerous",
      "note": "string — what specifically happens"
    }
  ],
  "legal_status": {
    "us_csa": "I | II | III | IV | V | none",
    "uk_msda": "A | B | C | psychoactive_substances_act | none",
    "eu_nps_monitored": boolean,
    "china_controlled": boolean,
    "wada_banned": boolean
  },
  "safety_warnings": ["string — concrete, quantitative when possible"],
  "notes": "string — what was uncertain, what was inferred vs cited, what wasn't found",
  "sources": ["string — URLs / PMIDs / DOIs for every populated field"],
  "confidence": "high | medium | low"
}

# Tag vocabulary

Mechanism: DRI, NDRI, NDDRI, SRI, SNRI, SNDRI, MAOI-A, MAOI-B, RIMA, 5-HT2A-agonist, 5-HT2C-agonist, kappa-opioid-agonist, mu-opioid-agonist, delta-opioid-agonist, NMDA-antagonist, AMPA-PAM, GABAA-PAM, nAChR-modulator, sigma-1, TAAR1, DAT-inhibitor
Chemical class: 2C-x, DOx, NBOMe, tryptamine, phenethylamine, cathinone, arylcyclohexylamine, diarylethylamine, nitazene, benzodiazepine, racetam, ampakine, salvinorin, pyrrolidinophenone, piperazine, piperidine
Provenance: PIHKAL, TIHKAL, research-chemical, investigational, vendor-only, prescription-only, radioligand-origin
Status: no-human-data, WADA-banned, US-Schedule-I, US-Schedule-II, EU-NPS-monitored, China-controlled, withdrawn-from-market

# Confidence levels

- "high": all populated fields cite peer-reviewed literature, FDA labels, or PsychonautWiki/TripSit. Compound has documented human use.
- "medium": fields cite Wikipedia, Erowid experience reports, or small-N studies. Some inference from related compounds.
- "low": compound has no documented human use; populated fields are extrapolated from SAR or animal studies. Dose ranges MUST be empty at this level.

If you cannot find anything beyond the compound's existence (a name, a CAS number, a paper that mentions it once), return a minimal object with `category: "Other"`, empty routes, `confidence: "low"`, and `notes` explaining what you searched and what you found.
```

---

## Per-substance query template

For each row in `piru-database-gaps.csv`, send Kimi:

```
Enrich this Piru substance entry. Fill in every field you can defend with citations. Return JSON only — no preamble, no markdown fences.

Existing data:
  name: {name}
  aliases: {aliases}
  current_category: {category}
  current_tags: {tags}
  chemical_class_hint: {chemical_class}
  routes_we_have: {routes_with_dose}
  sources_we_have: {sources}
  gaps_to_fill: {data_gaps}

Search at minimum:
  - PubChem for IUPAC / SMILES / InChIKey / CAS
  - PubMed for pharmacology and clinical data
  - PsychonautWiki and TripSit for harm-reduction data
  - Erowid for experience reports (qualitative only, never quantitative dose data)
  - DEA / EMCDDA / China NNCC for scheduling and surveillance status

Output one JSON object matching the schema in the system prompt.
```

---

## Batch protocol (for an agent swarm)

If you're running Kimi as a swarm, partition the CSV into batches of ~50 substances per worker. Each worker:

1. Reads its batch from `piru-database-gaps.csv`.
2. For each row, sends Kimi the per-substance query above.
3. Parses Kimi's JSON response (validate against schema; reject malformed responses with a single retry).
4. Appends to a per-worker output file `enriched-batch-{worker_id}.json` (a JSON array).

After all workers finish, run a merge that:
1. Concatenates every `enriched-batch-*.json`.
2. Deduplicates by InChIKey (when present) else normalised name.
3. Writes one merged `piru-database-enriched.json`.
4. For each entry, reconciles against `piru-database.json` — Kimi enrichments only overwrite Piru fields when `confidence == "high"`.

Reject any Kimi response that:
- Populates dose ranges with `confidence: "low"`.
- Cites only one source for the entire entry.
- Has `name` that doesn't match the queried compound (Kimi sometimes drifts).
- Returns prose outside the JSON object.

---

## Files in this folder

- `piru-database.json` — full export (1,614 compounds), one structured record each, including identifiers, current Piru data, and an explicit `data_gaps` array.
- `piru-database.csv` — same data flattened to a spreadsheet (`|`-separated multi-value cells).
- `piru-database-gaps.csv` — subset of the above where `data_gaps` is non-empty (the actual work list).
- `build-database-export.py` — regenerates all three outputs from the bundled JSON sources. Run after the in-app dataset changes.
- `kimi-enrichment-prompt.md` — this file.

## Schema mapping back into Piru

Once enriched, the Piru side will:
1. Validate each Kimi entry against the `Substance` Codable struct in `Piru/Models/Substance.swift`.
2. Run the existing `SubstanceValidator audit` subcommand to enforce dose monotonicity, plausibility ranges, and category coverage.
3. Merge into `Piru/Data/substances-bundled.json` via the same `SubstanceDeduplicator` the app uses at runtime — Piru's existing curated values win on conflict; Kimi enrichments fill gaps only.

Two fields in Kimi's schema don't yet have Piru analogues: `legal_status`, `interactions` (per-substance, not class-based). These can land as a follow-on once the model is extended; for now they ride in `tags` (legal status) and are dropped (per-substance interactions — Piru's interaction engine is class-based).
