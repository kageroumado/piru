# Piru Substance Library — Research & Verification Report

**Date**: February 2026
**Scope**: All 680 substances cross-referenced against established pharmacological sources
**Result**: 672 substances verified, 8 discarded

---

## Table of Contents

1. [Drugs.com Cross-Reference](#1-drugscom-cross-reference)
   - [Stimulants](#stimulants)
   - [Antidepressants](#antidepressants)
   - [Benzodiazepines](#benzodiazepines)
   - [Opioids](#opioids)
   - [Common Medications](#common-medications)
   - [Antipsychotics](#antipsychotics)
2. [Source Verification Scan](#2-source-verification-scan)
   - [Research Chemicals — Other](#research-chemicals--other)
   - [Research Chemicals — Stimulants](#research-chemicals--stimulants)
   - [Research Chemicals — Psychedelics](#research-chemicals--psychedelics)
   - [Cannabinoids (Synthetic/Novel)](#cannabinoids-syntheticnovel)
   - [Dissociatives (Novel Analogs)](#dissociatives-novel-analogs)
   - [Psychedelics — Lysergamides](#psychedelics--lysergamides)
   - [Psychedelics — Phenethylamines](#psychedelics--phenethylamines)
   - [Psychedelics — Tryptamines](#psychedelics--tryptamines)
   - [Empathogens](#empathogens)
   - [Nootropics](#nootropics)
   - [GABAergics (Novel)](#gabergics-novel)
   - [Hormones](#hormones)
   - [Supplements](#supplements)
3. [Corrections Applied](#3-corrections-applied)
4. [Substances Discarded](#4-substances-discarded)
5. [Sources Referenced](#5-sources-referenced)

---

## 1. Drugs.com Cross-Reference

### Stimulants

| Substance | Parameter | App Value | Drugs.com Reference | Status |
|-----------|-----------|-----------|---------------------|--------|
| Caffeine | halfLife | 300 min (5h) | 3-7h avg, ~5h typical | CORRECT |
| Caffeine | Oral doses | threshold 10, light 20-100, common 100-300, strong 300-500, heavy 500 | Up to 400mg/day safe (EFSA) | CORRECT |
| Caffeine | Fatal dose | 5000 mg | 5-10g cited | CORRECT |
| Amphetamine | halfLife | 660 min (11h) | d-amph ~10h, l-amph ~13h | CORRECT (good midpoint) |
| Amphetamine | Oral doses | threshold 3, light 5-15, common 15-30, strong 30-60, heavy 60 | Therapeutic 5-30mg/day | CORRECT |
| Methylphenidate | halfLife | 150 min (2.5h) | IR: 2-3h (~2.1h mean) | CORRECT |
| Methylphenidate | Oral doses | threshold 5, light 5-20, common 20-40, strong 40-60, heavy 60 | Therapeutic 10-60mg/day | CORRECT |
| Lisdexamfetamine | halfLife | 660 min (11h) | Active d-amph: 10-11.3h | CORRECT |
| Lisdexamfetamine | Oral doses | threshold 10, light 10-30, common 30-50, strong 50-70, heavy 70 | 30-70mg/day, max 70mg | CORRECT |
| Modafinil | halfLife | 900 min (15h) | 12-15h, FDA label ~15h | CORRECT |
| Modafinil | Oral doses | threshold 25, light 50-100, common 100-200, strong 200-400, heavy 400 | 200mg once daily | CORRECT |
| Cocaine | halfLife | 60 min (1h) | IV ~41min, intranasal ~75min | ACCEPTABLE (slightly low for nasal) |
| Atomoxetine | halfLife | 300 min (5h) | Extensive metabolizers ~5h | CORRECT |
| Nicotine | halfLife | 120 min (2h) | Average ~2h (range 1-4h) | CORRECT |

**Notes**: All stimulant data verified as accurate. Cocaine half-life (60 min) could be increased to 75 min for intranasal route but is within acceptable range.

**Sources**: Adderall FDA Label, Adderall XR FDA Label, StatPearls (Dextroamphetamine-Amphetamine), Methylphenidate Pharmacokinetics (PubMed), Modafinil FDA Label, StatPearls (Modafinil), Cocaine Kinetics (PubMed), Caffeine StatPearls, Atomoxetine Clinical Pharmacokinetics (PubMed), Nicotine Chemistry Metabolism Kinetics (PMC2953858).

---

### Antidepressants

| Substance | Parameter | App Value | Drugs.com Reference | Status |
|-----------|-----------|-----------|---------------------|--------|
| Sertraline | halfLife | 1560 min (26h) | ~26h (range 13-45h) | CORRECT |
| Fluoxetine | halfLife | 5760 min (96h) | Single: 48h, Chronic: 96-144h | CORRECT (chronic dosing) |
| Escitalopram | halfLife | 1770 min (29.5h) | 27-33h | CORRECT (good midpoint) |
| Bupropion | halfLife | 1260 min (21h) | Mean after chronic dosing: 21h | CORRECT |
| Venlafaxine | halfLife | 300 min (5h) | IR: ~5h; metabolite ~11h | CORRECT (parent compound) |
| Duloxetine | halfLife | 720 min (12h) | ~12h (range 8-17h) | CORRECT |
| Trazodone | halfLife | 420 min (7h) | Biphasic: 5-9h typical | REASONABLE (within range) |
| Mirtazapine | halfLife | 1500 min (25h) | 20-40h; males ~26h | CORRECT (within range) |

**Key decision**: Fluoxetine uses the chronic-dosing half-life (96h/4 days) rather than single-dose (48h) because it is taken daily as an antidepressant. This is the clinically relevant value.

**Sources**: PharmGKB Sertraline, Fluoxetine StatPearls, Fluoxetine FDA Label, Escitalopram Clinical Pharmacokinetics (PubMed), Bupropion StatPearls, Bupropion FDA Label, Venlafaxine StatPearls, Duloxetine Clinical Pharmacokinetics (PubMed), Trazodone StatPearls, Mirtazapine StatPearls, Mirtazapine FDA Label.

---

### Benzodiazepines

| Substance | Parameter | App Value | Drugs.com Reference | Status | Action |
|-----------|-----------|-----------|---------------------|--------|--------|
| Alprazolam | halfLife | 720 min (12h) | ~11.2h mean (6.3-26.9h) | Slightly high | **Changed to 672 min (11.2h)** |
| Diazepam | halfLife | 2880 min (48h) | 20-50h parent, metabolite up to 100h | ACCEPTABLE | No change (effective half-life) |
| Clonazepam | halfLife | 2280 min (38h) | 30-40h | CORRECT (midrange) | No change |
| Lorazepam | halfLife | 720 min (12h) | ~12h mean | EXACT MATCH | No change |

**Notes**: Alprazolam corrected from 720 to 672 min to match drugs.com mean. Diazepam's 48h is defensible as an effective half-life considering the active metabolite N-desmethyldiazepam (up to 100h). Elderly half-lives increase significantly for all benzodiazepines.

**Sources**: Alprazolam Dosage Guide (Drugs.com), Alprazolam Monograph, Diazepam Monograph, Clonazepam Monograph, Lorazepam Dosage Guide.

---

### Opioids

| Substance | Parameter | App Value | Drugs.com Reference | Status | Action |
|-----------|-----------|-----------|---------------------|--------|--------|
| Morphine | halfLife | 180 min (3h) | 1.5-4.5h (mean ~2h IV/IM) | ACCEPTABLE | No change (oral route) |
| Oxycodone | halfLife | 240 min (4h) | ~3.2h mean, IR under 4h | ACCEPTABLE | No change |
| Hydrocodone | halfLife | 228 min (3.8h) | 3.8-4.5h (IR) | EXCELLENT | No change |
| Codeine | halfLife | 180 min (3h) | ~2.9h (some report ~4h) | CORRECT | No change |
| Tramadol | halfLife | 390 min (6.5h) | 6-8h parent, M1 ~13.7h | CORRECT | No change |
| Fentanyl | halfLife | 210 min (3.5h) | IV: 3.6h; Transdermal: ~17h | INCORRECT for default route | **Changed to 1020 min (17h)** |
| Methadone | halfLife | 1500 min (25h) | 8-59h (highly variable) | ACCEPTABLE | No change |
| Buprenorphine | halfLife | 2160 min (36h) | SL: 31-35h mean (24-42h range) | CORRECT | No change |

**Key correction**: Fentanyl's default route is transdermal, but the half-life was set to the IV value (3.5h). Changed to 1020 min (17h) to reflect the transdermal apparent half-life, which is what users of patches would experience.

**Sources**: Morphine Sulfate Monograph (Drugs.com), Oxycodone (Drugs.com), Hydrocodone Monograph, Codeine Monograph, Tramadol (Drugs.com), Fentanyl Transdermal Package Insert, Methadone Monograph, Buprenorphine Sublingual Package Insert.

---

### Common Medications

| Substance | Parameter | App Value | Drugs.com Reference | Status | Action |
|-----------|-----------|-----------|---------------------|--------|--------|
| Gabapentin | halfLife | 360 min (6h) | 5-7h (mean ~6.5h) | ACCEPTABLE | No change |
| Pregabalin | halfLife | 360 min (6h) | 6.3h | Slightly low | **Changed to 378 min (6.3h)** |
| Hydroxyzine | halfLife | 1200 min (20h) | 14-25h, mean ~20h | CORRECT | No change |
| Promethazine | halfLife | 960 min (16h) | 10-19h | ACCEPTABLE | No change |
| Diphenhydramine | halfLife | 480 min (8h) | 2.4-9.3h (mean ~4-8h) | Upper bound | **Changed to 360 min (6h)** |
| Ibuprofen | halfLife | 120 min (2h) | 1.8-2.0h | CORRECT | No change |
| Acetaminophen | halfLife | 180 min (3h) | 1.25-3h | ACCEPTABLE (upper end) | No change |
| Aspirin | halfLife | 180 min (3h) | Salicylate: 2-3h at low doses | CORRECT | No change |

**Sources**: Gabapentin Package Insert (Drugs.com), Pregabalin Package Insert, Hydroxyzine Dosage Guide, Promethazine Dosage Guide, Diphenhydramine Monograph, Ibuprofen Package Insert, Acetaminophen Monograph, Aspirin Monograph.

---

### Antipsychotics

| Substance | Parameter | App Value | Drugs.com Reference | Status |
|-----------|-----------|-----------|---------------------|--------|
| Quetiapine | halfLife | 390 min (6.5h) | 6-7h (IR ~6h, XR ~7h) | CORRECT |
| Olanzapine | halfLife | 1800 min (30h) | 21-54h | CORRECT (central estimate) |
| Risperidone | halfLife | 1200 min (20h) | Active moiety ~20h | CORRECT (uses clinically relevant active moiety) |
| Aripiprazole | halfLife | 4500 min (75h) | ~75h (metabolite 94h) | EXACT MATCH |

**Sources**: Quetiapine Monograph (Drugs.com), Seroquel Package Insert, Olanzapine Monograph, Risperidone Monograph, Aripiprazole Dosage Guide.

---

## 2. Source Verification Scan

### Research Chemicals — Other

| Substance | PsychonautWiki | Erowid | PubMed | EMCDDA/Gov | Verdict |
|-----------|---------------|--------|--------|------------|---------|
| **NENDCK** | NO | NO | NO | NO | **DISCARDED** |
| 3-Me-PCP | NO (Talk page) | NO | YES | YES (Hungary 2020) | KEEP |
| 3-Me-PCPy | YES (Summary) | YES | YES | YES | KEEP |
| 3-Cl-PCP | YES | NO | YES (PubChem) | YES (Slovenia 2020) | KEEP |
| PCE | YES | YES | YES | YES (Schedule I since 1970s) | KEEP |
| 2-BDCK | PARTIAL | NO | YES | YES (NADDI) | KEEP |
| AP-238 | PARTIAL (Talk) | NO | YES (multiple) | YES (EWS 2020) | KEEP |
| Metonitazene | PARTIAL | NO | YES (multiple) | YES (EMCDDA) | KEEP |
| Protonitazene | NO | NO | YES (multiple) | YES (WHO Critical Review) | KEEP |
| Dipyanone | NO | NO | YES (multiple) | YES (2021 market) | KEEP |
| 2F-Viminol | NO | NO | YES | YES (Sweden 2019) | KEEP |
| N-Desethyl Isotonitazene | NO | NO | YES | YES (DEA Schedule I) | KEEP |

---

### Research Chemicals — Stimulants

| Substance | PsychonautWiki | Erowid | PubMed | EMCDDA/Gov | Verdict |
|-----------|---------------|--------|--------|------------|---------|
| 2-FMA | YES | YES | YES | YES | KEEP |
| 3-FMA | YES | NO | YES | YES | KEEP |
| 2-FA | YES | YES | PARTIAL | YES | KEEP |
| 3-FA | YES | YES | PARTIAL | YES | KEEP |
| 2-FEA | YES | YES | NO | PARTIAL | KEEP |
| 3-FEA | YES | YES | YES | YES | KEEP |
| NEP | YES | YES | YES | YES | KEEP |
| Hexen | YES | YES | YES | YES | KEEP |
| A-PHP | YES | PARTIAL | YES | YES (UNODC/Schedule I) | KEEP |

---

### Research Chemicals — Psychedelics

| Substance | PsychonautWiki | Erowid | PubMed | EMCDDA/Gov | Verdict |
|-----------|---------------|--------|--------|------------|---------|
| 4-AcO-MALT | NO | YES | PARTIAL | NO | KEEP (CFSRE monograph) |
| 4-AcO-DALT | NO | YES | YES | YES (seized 2012) | KEEP |
| 5-Cl-AMT | NO | YES | YES (as PAL-542) | PARTIAL | KEEP |
| **O-Acetylbufotenin** | NO | NO | YES | NO | **DISCARDED** (never tested in humans) |
| **4-HO-DSBT** | NO | Mentioned in TiHKAL | PARTIAL | NO | **DISCARDED** (never assayed in humans) |
| 5-MeO-EIPT | PARTIAL (Talk) | NO | NO | YES (illegal in Japan, NZ) | KEEP |
| **5-MeO-NIPT** | NO | NO | PARTIAL | NO | **DISCARDED** (not orally active) |
| 4-Pro-DMT | NO | NO | YES | YES (Sweden 2019) | KEEP |
| **MCPT** | NO | NO | NO | PARTIAL (UK 2015) | **DISCARDED** (no human pharmacology) |
| 25E-NBOH | PARTIAL (stub) | YES | YES (multiple) | YES (Brazil 2018) | KEEP |
| 2C-B-AN | NO | NO | MINIMAL (Trachsel 2013) | YES (Europe 2016) | KEEP (with caution) |
| **2C-B-CB** | NO | NO | NO | NO | **DISCARDED** (fictitious compound) |
| 2C-G | NO | YES (PiHKAL #27) | MINIMAL | NO | KEEP (PiHKAL: 20-35mg, 18-30h) |
| 2C-N | NO | YES (PiHKAL #34) | YES (PubChem) | YES (Schedule I US) | KEEP (PiHKAL: 100-150mg) |
| **2C-O-4** | NO | YES (PiHKAL #35) | NO | NO | **DISCARDED** (single inconclusive trial) |
| 2C-T-4 | NO | YES (PiHKAL #41, 24 Erowid reports) | MINIMAL | NO | KEEP (PiHKAL: 8-20mg, 12-18h) |

---

### Cannabinoids (Synthetic/Novel)

| Substance | PsychonautWiki | Erowid | PubMed | EMCDDA/Gov | Verdict |
|-----------|---------------|--------|--------|------------|---------|
| Delta-8-THC | YES | NO | YES (extensive) | FDA warnings | KEEP |
| THCV | Partial (Cannabis pg) | NO | YES (extensive) | DrugBank DB11755 | KEEP |
| HHC | YES | NO | YES (multiple) | YES (EMCDDA tech report) | KEEP |
| THCO | YES | NO | YES (limited) | Monitored | KEEP |
| THCP | YES | NO | YES (Sci Reports 2019, CB1 Ki=1.2nM) | Monitored | KEEP |
| THCa | Partial | NO | YES (extensive) | Not monitored (natural) | KEEP |
| HHCO | NO | NO | YES (CB1 activation) | YES (EMCDDA HHC report) | KEEP |
| THCB | NO | NO | YES (J Nat Prod, CB1 Ki=15nM) | NO | KEEP (weakest, 1 paper) |
| JWH-018 | YES | YES | YES (dozens) | YES (Schedule I, EMCDDA) | KEEP |
| JWH-073 | YES | YES | YES (multiple) | YES (EMCDDA) | KEEP |
| JWH-210 | Partial | NO | YES (multiple) | YES (Schedule I) | KEEP |
| AM-2201 | Partial | YES | YES | YES (Schedule I) | KEEP |
| 5F-AKB48 | YES | NO | YES | YES (WHO ECDD review) | KEEP |
| AB-FUBINACA | YES | YES | YES (extensive) | YES (WHO ECDD, Schedule I) | KEEP |
| AB-CHMINACA | NO | NO | YES | YES (EMCDDA risk assessment) | KEEP |
| MDMB-4en-PINACA | NO | NO | YES (extensive) | YES (EMCDDA, WHO ECDD) | KEEP |
| CUMYL-PINACA | NO | NO | YES (ACS Chem Neurosci) | YES (DEA Schedule I) | KEEP |
| ADB-BUTINACA | Listed (no article) | NO | YES | YES (WHO ECDD) | KEEP |
| MDMB-FUBINACA | NO | NO | YES | YES (WHO ECDD, "most deadly SC") | KEEP |

---

### Dissociatives (Novel Analogs)

| Substance | PsychonautWiki | Erowid | PubMed | EMCDDA/Gov | Verdict |
|-----------|---------------|--------|--------|------------|---------|
| 3-MeO-PCP | YES | YES (vault) | YES (multiple) | YES (WHO ECDD) | KEEP |
| 3-HO-PCP | YES | YES | YES (NMDA Ki=30nM, mu Ki=39nM) | Monitored | KEEP |
| 3-MeO-PCE | YES | YES (reports) | YES | Monitored | KEEP |
| 3-HO-PCE | YES | YES | YES (metabolism, toxicity) | Monitored | KEEP |
| O-PCE | YES | YES | LIMITED | Monitored | KEEP |
| MXE | YES | YES (vault) | YES (extensive) | YES (WHO ECDD) | KEEP |
| MXiPr | YES | Partial | YES (identification) | Monitored | KEEP (weakest, but sufficient) |

---

### Psychedelics — Lysergamides

| Substance | PsychonautWiki | Erowid | PubMed | Verdict |
|-----------|---------------|--------|--------|---------|
| 1P-LSD | YES | YES | YES (pharmacokinetics) | KEEP |
| 1cP-LSD | YES | YES (11 reports) | YES (analytical/behavioural) | KEEP |
| 1V-LSD | YES | YES (7 reports) | YES (Return of Lysergamides VII) | KEEP |
| 1B-LSD | YES | YES | YES (1-acyl LSD derivatives) | KEEP |
| **1D-LSD** | PARTIAL (Talk only) | YES (3 reports) | WEAK (mislabeling found) | **DISCARDED** |
| ALD-52 | YES | YES (article + vault) | YES (Hofmann 1957) | KEEP |
| AL-LAD | YES | YES (TiHKAL #1) | YES (Hoffman & Nichols 1984) | KEEP |
| ETH-LAD | YES | YES (TiHKAL #12, 24 reports) | YES (Niwaguchi 1976) | KEEP |

---

### Psychedelics — Phenethylamines

| Substance | PsychonautWiki | Erowid/PiHKAL | PubMed | Verdict |
|-----------|---------------|---------------|--------|---------|
| 2C-B | YES | YES (PiHKAL #20, "magical half-dozen") | YES (extensive) | KEEP |
| 2C-C | YES | YES (PiHKAL #22) | YES | KEEP |
| 2C-D | YES | YES (PiHKAL #23, vault) | YES | KEEP |
| 2C-E | YES | YES (PiHKAL #24, "magical half-dozen") | YES | KEEP |
| 2C-I | YES | YES (PiHKAL #33, vault) | YES | KEEP |
| 2C-P | YES | YES (PiHKAL #36, vault) | YES | KEEP |
| 2C-T-2 | YES | YES (PiHKAL #40, "magical half-dozen") | YES | KEEP |
| 2C-T-7 | YES | YES (PiHKAL #43, "magical half-dozen", vault) | YES | KEEP |
| 2C-T-21 | YES | YES (PiHKAL #49) | YES (fatality documented) | KEEP |
| 2C-B-FLY | YES | YES (vault, Shulgin Index) | YES | KEEP |

---

### Psychedelics — Tryptamines

| Substance | PsychonautWiki | Erowid/TiHKAL | PubMed | Verdict |
|-----------|---------------|---------------|--------|---------|
| Psilocin | YES | YES (TiHKAL #18) | YES (extensive, Hofmann 1958) | KEEP |
| 4-AcO-DMT | YES | YES (vault) | YES (Hofmann & Troxler 1963) | KEEP |
| 4-HO-MET | YES | YES (TiHKAL) | YES (recreational use study) | KEEP |
| 4-AcO-MET | YES | YES (vault) | LIMITED (prodrug of 4-HO-MET) | KEEP |
| 4-HO-MiPT | YES | YES (TiHKAL) | YES (Repke 1981, patent) | KEEP |
| 4-HO-DiPT | YES | YES (TiHKAL) | YES (Repke 1977, clinical trials for prodrug) | KEEP |

---

### Empathogens

| Substance | PsychonautWiki | Erowid | PubMed | Verdict |
|-----------|---------------|--------|--------|---------|
| MDA | YES | YES (vault) | YES (extensive, first synth 1910) | KEEP |
| MDEA | YES | YES (vault + reports) | YES (neuropsychopharm review) | KEEP |
| 6-APB | YES | YES (vault + reports) | YES (monoamine transmission) | KEEP |
| 5-APB | YES | YES (reports) | YES (Nichols 1993, monoamine study) | KEEP |
| 5-MAPB | YES | YES (vault + doses) | YES (monoamine release) | KEEP |
| 6-MAPB | NO | YES (reports) | YES (benzofuran study) | KEEP (weakest benzofuran) |
| 4-FA | YES | YES (vault, 77 reports) | YES (first-in-man clinical, PK) | KEEP |
| Methylone | YES | YES (vault) | YES (Jacob & Shulgin 1996, human comparison) | KEEP |

---

### Nootropics

| Substance | Sources | Verdict |
|-----------|---------|---------|
| Piracetam | DrugBank DB09210, PubMed (numerous), prescribed in Europe | KEEP |
| Aniracetam | DrugBank DB04599, PubMed, prescribed in Japan/Europe | KEEP |
| Oxiracetam | DrugBank DB13601, PubMed (PK studies) | KEEP |
| Pramiracetam | DrugBank DB13247, PubMed, prescribed in Italy/Eastern Europe | KEEP |
| Phenylpiracetam | PubMed, approved in Russia (Phenotropil) | KEEP |
| Coluracetam | DrugBank DB21278, PubChem, Phase IIa for MDD | KEEP |
| Fasoracetam | DrugBank DB16163, PubMed (Phase III ADHD), mGluR/GABA-B mechanism | KEEP |
| Noopept | DrugBank DB19956 (Omberacetam), PubMed (clinical trials), prescribed in Russia | KEEP |
| Semax | PubMed (ACTH 4-10 analog studies), prescribed in Russia | KEEP |
| Selank | PubMed (GABAergic mechanism), Frontiers in Pharmacology, prescribed in Russia | KEEP |
| Alpha-GPC | PubMed (systematic review/meta-analysis), prescription drug in Europe | KEEP |
| CDP-Choline | PubMed (extensive), prescription drug in some countries | KEEP |

---

### GABAergics (Novel)

| Substance | Sources | Verdict |
|-----------|---------|---------|
| GBL | PubMed (toxicology, pharmacology), DEA drug info, CDC MMWR | KEEP |
| 1,4-Butanediol | PubMed (clinical PK in healthy volunteers), DEA drug info | KEEP |
| Phenibut | DrugBank DB13455, PubMed (extensive), Examine.com, prescribed in Russia since 1960s | KEEP |
| F-Phenibut | PubMed (Irie 2020 GABA-B agonism), PubChem, EC50 values documented | KEEP |

---

### Hormones

| Substance | Sources | Verdict |
|-----------|---------|---------|
| Estradiol | FDA-approved (Estrace), DailyMed, DrugBank DB00783 | KEEP |
| Estradiol Valerate | FDA-approved (Delestrogen), DailyMed | KEEP |
| Estradiol Cypionate | FDA-approved (Depo-Estradiol), DailyMed | KEEP |
| Estradiol Enanthate | DrugBank DB13955, PubMed (PK), marketed internationally (Perlutal) | KEEP |
| Ethinylestradiol | FDA-approved since 1943, DrugBank DB00977 | KEEP |
| Conjugated Estrogens | FDA-approved since 1942 (Premarin), DailyMed | KEEP |
| Spironolactone | FDA-approved since 1960 (Aldactone), DrugBank DB00421 | KEEP |
| Cyproterone Acetate | DrugBank DB04839, PubMed (extensive), approved in Europe/Canada | KEEP |
| Bicalutamide | FDA-approved 1995 (Casodex), DailyMed | KEEP |
| Finasteride | FDA-approved 1992 (Proscar), DrugBank DB01216 | KEEP |
| Dutasteride | FDA-approved 2001 (Avodart), DrugBank DB01126 | KEEP |

---

### Supplements

All 73 supplements verified. Source tiers:

**Tier 1 — FDA-approved or major regulatory**: NAC (Mucomyst), Melatonin (EU drug), Fish Oil (Lovaza)

**Tier 2 — NIH ODS Fact Sheets**: Vitamins D3, C, B1-B12, A, E, K2. Minerals: Magnesium, Zinc, Iron, Potassium, Selenium, Calcium, Chromium, Iodine.

**Tier 3 — Examine.com + PubMed clinical trials**: Ashwagandha, Rhodiola, Valerian, St. John's Wort, Ginkgo, Turmeric, Milk Thistle, Tongkat Ali, Ginseng, Echinacea, Saw Palmetto, Creatine, CoQ10, Berberine, Quercetin, Resveratrol, Alpha-Lipoic Acid, L-Tryptophan, 5-HTP, L-Tyrosine, NAC, Beta-Alanine, Taurine, L-Citrulline, Glycine, L-Arginine, GABA, L-Glutamine, Maca Root, Black Seed Oil, Collagen, MCT Oil, Probiotics, Glucosamine, Fish Oil.

**Tier 4 — PubMed only (limited but real)**: Blue Lotus, Kanna (Zembrin), Wild Dagga, Mulungu, Damiana, Skullcap, PQQ, Astaxanthin, Cordyceps, Reishi, Turkey Tail, Chamomile, Passionflower, Lemon Balm, Gotu Kola, Elderberry, Apple Cider Vinegar.

---

## 3. Corrections Applied

| Substance | Parameter | Before | After | Reason |
|-----------|-----------|--------|-------|--------|
| Alprazolam | halfLifeMinutes | 720 (12h) | 672 (11.2h) | Match drugs.com mean |
| Fentanyl | halfLifeMinutes | 210 (3.5h) | 1020 (17h) | Default route is transdermal; was using IV value |
| Pregabalin | halfLifeMinutes | 360 (6h) | 378 (6.3h) | Match drugs.com |
| Diphenhydramine | halfLifeMinutes | 480 (8h) | 360 (6h) | Was at upper bound; moved to central value |

---

## 4. Substances Discarded

8 substances removed from the library (680 → 672):

| # | Substance | File | Reason |
|---|-----------|------|--------|
| 1 | NENDCK | ResearchChemicalsOther.swift | Zero established sources. All documentation is about 2F-NENDCK (a different fluorinated compound) or O-PCE (also different). |
| 2 | 1D-LSD | PsychedelicsLysergamides.swift | No PsychonautWiki article (only Talk page), no dedicated PubMed pharmacology. Published evidence that products sold as "1D-LSD" were actually mislabeled 1T-LSD (PMID 37421500). |
| 3 | O-Acetylbufotenin | ResearchChemicalsPsychedelics.swift | Shulgin explicitly states in TiHKAL that this compound was never tested in humans. All dosing data was speculative with no basis. |
| 4 | 4-HO-DSBT | ResearchChemicalsPsychedelics.swift | Shulgin notes in TiHKAL it was synthesized as an oil that "never crystallized" and was never assayed in humans. Only in vitro binding data exists. |
| 5 | 5-MeO-NIPT | ResearchChemicalsPsychedelics.swift | Described in literature as "not active orally" and "generally regarded as not worth the time." No verifiable human dosing data from any source. |
| 6 | MCPT | ResearchChemicalsPsychedelics.swift | Only forensic identification data (UK, August 2015). No human pharmacological or dosing studies. Derivatives (4-HO-McPT, 4-AcO-McPT) are documented but not the parent compound. |
| 7 | 2C-B-CB | ResearchChemicalsPsychedelics.swift | Fictitious compound. "2C-B-cyclobenzyl" does not appear in any pharmacological database, PsychonautWiki, Erowid, PiHKAL, PubMed, or EMCDDA. Dosing data was entirely fabricated. |
| 8 | 2C-O-4 | ResearchChemicalsPsychedelics.swift | While it exists in PiHKAL (#35), Shulgin's single trial at 60mg produced only threshold effects (+1). He deemed the 2C-O series unpromising. PiHKAL lists dose as ">60mg" and duration as "unknown." The app's dose-response curve was fabricated and contradicts the source. |

---

## 5. Sources Referenced

### Clinical / Regulatory
- **Drugs.com** — Drug monographs, dosage guides, package inserts
- **FDA DailyMed** — FDA-approved drug labeling
- **StatPearls (NCBI Bookshelf)** — Peer-reviewed clinical pharmacology summaries
- **DrugBank** — Comprehensive drug database with pharmacokinetic data
- **PubMed / PMC** — Peer-reviewed biomedical literature
- **PubChem** — Chemical compound database (NIH)
- **NIH Office of Dietary Supplements** — Supplement fact sheets
- **NIH NCCIH** — National Center for Complementary and Integrative Health
- **Examine.com** — Evidence-based supplement and nutrition database
- **WHO ECDD** — Expert Committee on Drug Dependence critical reviews
- **EMCDDA/EUDA** — European drug monitoring agency technical reports
- **DEA** — Drug Enforcement Administration scheduling and drug information
- **UNODC** — United Nations Office on Drugs and Crime substance listings
- **CFSRE** — Center for Forensic Science Research & Education monographs

### Harm Reduction / Community
- **PsychonautWiki** — Community pharmacology wiki with dosage and effects data
- **Erowid** — Experience vaults, substance information, and chemical libraries
- **TiHKAL** (Shulgin & Shulgin, 1997) — Tryptamines I Have Known And Loved
- **PiHKAL** (Shulgin & Shulgin, 1991) — Phenethylamines I Have Known And Loved
- **The Shulgin Index, Vol. 1** (Shulgin, 2011) — Psychedelic phenethylamines and related compounds

### Specific Papers Cited
- Alprazolam pharmacokinetics: Drugs.com monograph (mean 11.2h, range 6.3-26.9h)
- Fentanyl transdermal PK: Drugs.com package insert (apparent t½ ~17h)
- Fluoxetine chronic dosing: FDA Label (4-6 day half-life at steady state)
- 1P-LSD pharmacokinetics: PMID 32415750
- 1cP-LSD characterization: PMID 32180350
- 1V-LSD characterization: PMC9191648
- 1D-LSD mislabeling: PMID 37421500
- 2C review ("2C or Not 2C"): PMC3657019
- 4-AcO-DMT metabolism: PMID 35312166
- 4-FA first-in-man: PMID 30676284
- Methylone vs MDMA human study: PMC8389614
- THCP discovery (CB1 Ki=1.2nM): PMID 31889124
- Benzofuran monoamine release: PMID 27193726
- Cocaine IV/intranasal kinetics: PMID 6839006
- Nicotine metabolism: PMC2953858
- Sertraline pharmacokinetics: PMC7008964
- Bupropion FDA Label: 018644s043
- Modafinil FDA Label: 020717s030
