# Piru Deep-Pharmacology Enrichment Prompt

This is a **second-pass enrichment** for the Piru harm-reduction iOS app's substance database. The basic data (dose ranges, duration, half-life, common effects) is already in the app's bundled JSON. Your job is **not** to re-collect that.

Your job is the **deep pharmacology** that's missing or fragmentary across the literature:

- **Receptor binding constants in human tissue** (Ki/Kd at specific targets, with assay conditions cited)
- **Functional assay results** (EC50/IC50 at GPCRs, intrinsic activity vs reference agonists)
- **Biased agonism** (Gαi vs Gαq vs β-arrestin recruitment ratios, with reference compound for normalisation)
- **Receptor dimers / heteromers / oligomers** if studied
- **Second-messenger and downstream signalling** (cAMP modulation, PIP2 hydrolysis, ERK1/2, β-arrestin internalisation kinetics)
- **In-vivo human pharmacokinetics** (Cmax, Tmax, Vd, CL, AUC, protein binding, F% bioavailability per route)
- **Concentration-effect relationships** (plasma concentration vs cardiovascular effects, EEG, subjective intensity)
- **Metabolism** (which CYPs, fraction of clearance per pathway, M1/M2 metabolites and their activity, hepatic vs extrahepatic)
- **Drug-drug interaction data with Ki for CYP inhibition** and inducer status (mRNA fold-change at given concentration)
- **Pharmacogenetic considerations** (CYP2D6/2C19/3A4/3A5 PM/EM/UM impact on PK, OPRM1 polymorphisms for opioids, COMT/5-HTTLPR for serotonergics)
- **Tolerance kinetics** (receptor downregulation half-time, desensitisation vs internalisation, cross-tolerance to related compounds, withdrawal syndrome timeline)
- **Sex / age / weight / disease-state differences** if studied
- **Neuroimaging or neurophysiology findings** (fMRI signatures, EEG fingerprints, PET ligand displacement in humans)
- **Off-target effects** that don't get advertised — hERG, σ1, TAAR1, glycine site, monoamine transporter promiscuity, etc.

---

## Hard rules

- **NEVER fabricate.** If the literature doesn't have a Ki for a compound, return `null`. "I couldn't find it" is the right answer.
- **NEVER extrapolate Ki / EC50 from class membership.** Two arylcyclohexylamines can have 100× different NMDA affinity. Cite the actual paper.
- **NEVER cite reviews as primary**: chase reviews back to the original paper and cite that. If you cite a review, mark it as such.
- **ALWAYS** include assay conditions for binding data: cell line, expression system (human vs rat vs mouse receptor), radioligand used, assay buffer composition when reported, temperature.
- **ALWAYS** distinguish human vs animal data. Use the `species` field on every binding/functional record.
- **ALWAYS** include a DOI or PMID for every numerical value. URLs are okay for non-paper sources but DOI/PMID is preferred.
- **DO NOT** populate fields with "approximately" or "~" prefixes. If the literature says "about 10 nM," put `10` and add a note in `notes` that the source was approximate.
- **DO NOT** re-collect basic dose-range data unless the existing record is wrong. The user already has bundled data for that.
- **DO NOT** include subjective trip reports. Phenomenology lives elsewhere.

---

## Class-context approach

Each agent owns a **mechanism class** (arylcyclohexylamines, classical psychedelics, designer opioids, etc.). Build context for the class first:

1. **Class-shared mechanism** — what receptor / transporter / channel is the primary target? What are the typical binding-pose findings? What second-messenger cascade dominates?
2. **Class-shared PK** — typical metabolism pathway, common half-life range, typical Vd.
3. **Class-shared safety** — what kills people in this class? What's the off-target most likely to matter (hERG for cocaine analogues, σ1 for some SSRIs, μ-opioid for tianeptine)?
4. **SAR axis** — what structural changes move affinity / efficacy / duration / selectivity? Cite the relevant SAR papers once.

Then for each compound in your list, populate per-compound fields that **deviate from or refine** the class context.

---

## Output schema

Return a JSON array. One object per compound. Use this schema:

```json
{
  "name": "string — canonical name as it appears in the input list",
  "aliases_added": ["string — any aliases you found that aren't already in the input"],
  "iupac_name": "string or null",
  "smiles": "string or null",
  "inchikey": "string or null",
  "cas": "string or null",
  "pubchem_cid": null,

  "class_context_id": "string — references the class_context object below; use the same id for all compounds in this batch",

  "pharmacology": {
    "primary_targets": ["DAT", "NET", "5-HT2A", "NMDA", ...],
    "binding": [
      {
        "target": "5-HT2A",
        "ki_nm": 12.5,
        "ki_ci_nm": [10.2, 15.1],
        "kd_nm": null,
        "ec50_nm": null,
        "ic50_nm": null,
        "intrinsic_activity_pct": 65,
        "reference_agonist": "5-HT",
        "action": "agonist | partialAgonist | antagonist | inverseAgonist | positiveAllostericModulator | negativeAllostericModulator | reuptakeInhibitor | releasingAgent | enzymeInhibitor | channelBlocker | modulator",
        "species": "human | rat | mouse | rhesus | other",
        "tissue_or_cell": "HEK293 stably expressing human 5-HT2A | rat cortical membrane | ...",
        "radioligand_or_probe": "[3H]-ketanserin",
        "assay_buffer_notes": "string or null",
        "reference": "doi:10.1124/jpet.103.... | pmid:12345678",
        "is_review": false,
        "notes": "string or null"
      }
    ],
    "functional": [
      {
        "target": "5-HT2A",
        "readout": "PIP2 hydrolysis | cAMP | β-arrestin recruitment | ERK1/2 | GTPγS binding | calcium flux | electrophysiology",
        "ec50_nm": 8.4,
        "emax_pct": 92,
        "reference_agonist": "DOI",
        "species": "human",
        "cell_system": "HEK293",
        "reference": "doi:..."
      }
    ],
    "biased_agonism": [
      {
        "target": "5-HT2A | μ-opioid | ...",
        "pathways_compared": ["Gαq", "β-arrestin-2"],
        "bias_factor_log": -1.2,
        "bias_reference_compound": "5-HT or DAMGO",
        "interpretation": "string — what the bias means",
        "reference": "doi:..."
      }
    ],
    "receptor_oligomerisation": [
      {
        "complex": "5-HT2A/mGluR2 heteromer | μ/δ-opioid heteromer | ...",
        "evidence": "BRET / FRET / coIP / proximity ligation",
        "functional_consequence": "string",
        "reference": "doi:..."
      }
    ],
    "downstream_signalling": "free text — describe the cascade that's actually known for this compound in humans/human cells, not the class default",
    "neuroimaging": [
      {
        "modality": "fMRI BOLD | EEG | MEG | PET | SPECT",
        "finding": "string — concise",
        "reference": "doi:..."
      }
    ]
  },

  "human_pk": {
    "routes": [
      {
        "route": "oral | sublingual | insufflation | inhalation | smoked | rectal | intramuscular | intravenous | subcutaneous | transdermal",
        "bioavailability_pct": 45,
        "cmax_ng_per_ml": 180,
        "tmax_min": 60,
        "auc_0_inf_ng_h_per_ml": 1200,
        "half_life_min": 360,
        "vd_l_per_kg": 3.1,
        "clearance_ml_per_min_per_kg": 14,
        "protein_binding_pct": 89,
        "dose_in_study_mg": 50,
        "subject_n": 12,
        "subject_demographics": "string — male/female split, age range, BMI if reported",
        "reference": "doi:..."
      }
    ],
    "concentration_effect": [
      {
        "effect": "subjective intensity 0-10 | systolic BP | HR | EEG alpha power | pupil diameter",
        "concentration_unit": "ng/mL | nM",
        "threshold": 50,
        "peak_effect": 300,
        "reference": "doi:..."
      }
    ]
  },

  "metabolism": [
    {
      "enzyme": "CYP3A4 | CYP2D6 | UGT2B7 | CES1 | ...",
      "fraction_of_clearance_pct": 70,
      "metabolite_name": "norketamine",
      "metabolite_active": true,
      "metabolite_potency_vs_parent_pct": 33,
      "reference": "doi:..."
    }
  ],

  "drug_interactions_pk": [
    {
      "with": "fluoxetine | grapefruit | itraconazole | ...",
      "mechanism": "CYP3A4 inhibition | CYP2D6 inhibition | OATP inhibition | UGT inhibition",
      "ki_um": 0.3,
      "clinical_effect": "string — what changes in plasma exposure",
      "reference": "doi:..."
    }
  ],

  "pharmacogenetics": {
    "relevant_genes": ["CYP2D6", "OPRM1", "COMT", "5-HTTLPR"],
    "phenotype_effects": "string — concise description of how PM/EM/UM affects PK/PD",
    "reference": "doi:..."
  } ,

  "tolerance_and_dependence": {
    "receptor_downregulation_half_time": "string — e.g. '~7 days for 5-HT2A after repeated DOI in rats; no human data'",
    "cross_tolerance": ["compound names"],
    "withdrawal_syndrome": "string — onset, peak, duration, key symptoms",
    "reference": "doi:..."
  },

  "off_targets": [
    {
      "target": "hERG | σ1 | TAAR1 | NET | ...",
      "ki_or_ic50_nm": 4200,
      "concern_level": "low | moderate | high",
      "clinical_consequence": "string — e.g. QT prolongation at supratherapeutic doses",
      "reference": "doi:..."
    }
  ],

  "demographic_differences": {
    "sex": "string — e.g. 'Women have 30% lower CL; reference: doi:...'",
    "age": "string or null",
    "weight": "string or null",
    "renal_or_hepatic": "string or null"
  },

  "tags_to_add": ["string — refined tags based on what you found, e.g. 'biased-agonist-Gq', 'hERG-strong'"],
  "tags_to_remove": ["string — tags that the existing data has but your research contradicts"],

  "confidence": "high | medium | low",
  "data_gaps_remaining": ["string — what you searched for but couldn't find"],
  "notes": "string — anything else important",
  "references_consulted": ["doi:... or pmid:... or URL"]
}
```

After all per-compound objects, **append one class-context object** to the same array, distinguishable by the `is_class_context: true` flag:

```json
{
  "is_class_context": true,
  "class_context_id": "arylcyclohexylamines",
  "class_name": "Arylcyclohexylamines (NMDA antagonists at the PCP binding site)",
  "shared_mechanism": "string — 3-5 sentence summary",
  "shared_pk_summary": "string",
  "shared_safety": "string",
  "sar_summary": "string — what structural changes do what",
  "key_references": ["doi:..."]
}
```

---

## Search strategy

Use WebSearch and WebFetch. Search at minimum:
- **PubMed / PMC** — primary literature with DOI
- **PDSP Ki database** (https://pdsp.unc.edu) — the canonical receptor-affinity reference, machine-readable
- **DrugBank** — for FDA-approved drugs, has PK data
- **ChEMBL** — bioactivity assays
- **PubChem BioAssay** — additional binding/functional assays
- **PsychonautWiki** — for novel compounds that don't have peer-reviewed coverage yet (treat as low confidence)
- **Erowid library** — only for compounds where PIHKAL / TIHKAL Part 2 is the original source

For each compound, do at least 3 separate searches:
1. `<compound_name> Ki OR Kd binding affinity human` 
2. `<compound_name> pharmacokinetics CYP metabolism`
3. `<compound_name> mechanism of action functional assay`

If the compound is in the same family as a well-studied parent (e.g. a new 2C-x as a sibling to 2C-B), also search `<compound_name> structure activity relationship <parent>`.

---

## Output mechanics

- Write your final JSON array to: `data/enrichment/raw/<your-group-slug>.json` (the slug is given in your task prompt)
- Do not include preamble or markdown fences in the file — it must parse as JSON
- Validate your JSON by parsing it before writing (write to a temp file, parse, then move)
- If you run out of time or context, write what you have so far — partial output is much more useful than no output

---

## Substance list

Your specific list of compounds is in your task prompt. Compounds in your list that share a class can share a `class_context_id` — only emit one class-context object per distinct class you actually researched.

If a compound on your list has no usable pharmacology data anywhere (e.g. a purely SAR-named research chemical with one preprint), return a minimal record with `confidence: "low"` and `data_gaps_remaining` listing what you searched for.
