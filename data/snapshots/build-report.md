# Piru SQLite build report

Built 2026-09-11.6 → `Piru/Data/piru-substances.sqlite` (19,365,888 bytes, sha256 `b3cbde7fe64d845920c3eda3d11d1300c0c1833fde681d248732c645e3a3bee3`)

## Row counts

| Table | Rows |
|---|---|
| substances | 1,689 |
| aliases | 5,716 |
| sources | 18 |
| source_field_priority | 2 |
| citations | 2,886 |
| categories | 1,560 |
| tags | 7,050 |
| dose_ranges | 2,765 |
| durations | 10,554 |
| half_lives | 703 |
| mechanisms_summary | 1,146 |
| effects | 2,952 |
| subjective_effects | 23,503 |
| subjective_effect_concepts | 506 |
| subjective_effect_concept_aliases | 1,178 |
| tolerance | 322 |
| indications | 1,133 |
| contraindications | 1,412 |
| diazepam_equivalents | 32 |
| bindings | 1,460 |
| functional_assays | 179 |
| biased_agonism | 23 |
| receptor_oligomers | 8 |
| downstream_signalling | 678 |
| neuroimaging | 52 |
| pk_routes | 434 |
| concentration_effects | 23 |
| metabolism | 560 |
| drug_interactions_pk | 205 |
| pharmacogenetics | 305 |
| off_targets | 209 |
| class_contexts | 50 |
| substance_classes | 680 |
| molecule_shapes | 958 |
| class_reference_compounds | 40 |
| class_representatives | 7 |
| substance_flags | 13 |
| regional_names | 5 |
| opioid_mme | 11 |
| interaction_rules | 99 |
| substance_interaction_classes | 213 |
| category_interaction_classes | 29 |
| tolerance_modulation | 0 |
| enzyme_modulators | 11 |
| combination_metabolites | 2 |
| tag_enzyme_interactions | 285 |
| pharmacology_matchers | 47 |
| withdrawal_timing_bands | 3 |
| withdrawal_acting_class | 9 |
| taper_interventions | 16 |
| by_volume_dosing | 2 |
| drink_presets | 4 |
| zero_order_kinetics | 1 |
| saturable_kinetics | 6 |
| bioavailability_by_dose | 10 |
| attenuation_bands | 1 |
| coded_products | 15,987 |
| product_codes | 103,591 |

## Identifier corrections

Identifier columns a source was allowed to overwrite because the stored row contradicted itself (`dosewiki_identity_corrections` in `pipeline/build/sqlite.py`).

| substance | column | rule | was | now |
|---|---|---|---|---|
| 1P-LSD | inchikey | key_from_own_smiles | `JSMQOVGXBIDBIE-UHFFFAOYSA-N` | `JSMQOVGXBIDBIE-OXQOHEQNSA-N` |
| 4-EMC | inchikey | key_from_own_smiles | `FUYPDKFWOHBUFT-VIFPVBQESA-N` | `FUYPDKFWOHBUFT-UHFFFAOYSA-N` |
| Buprenorphine | smiles | smiles_regains_stereo | `COC12CCC3(CC1C(C)(O)C(C)(C)C)C1Cc4ccc(O)c5OC2C3(CCN1CC1CC1)c45` | `CO[C@]12CC[C@@]3(C[C@@H]1[C@](C)(O)C(C)(C)C)[C@H]1CC4=C5C(O[C@@H]2[C@@]35CCN1CC1CC1)=C(O)C=C4` |
| ETH-LAD | inchikey | key_from_own_smiles | `MYNOUXJLOHVSMQ-UHFFFAOYSA-N` | `MYNOUXJLOHVSMQ-DNVCBOLYSA-N` |
| 1P-ETH-LAD | smiles | smiles_regains_stereo | `CCN(CC)C(=O)C1CN(CC)C2Cc3cn(C(=O)CC)c4cccc(C2=C1)c34` | `CCN1C[C@@H](C=C2[C@H]1Cc1cn(c3c1c2ccc3)C(=O)CC)C(=O)N(CC)CC` |
| Dihydrocodeine | smiles | smiles_regains_stereo | `COc1ccc2CC3N(C)CCC45C3CCC(O)C5Oc1c24` | `[H][C@@]12OC3=C4C(C[C@H]5N(C)CC[C@@]14[C@@]5([H])CC[C@@H]2O)=CC=C3OC` |
| Ethylmorphine | smiles | smiles_regains_stereo | `CCOc1ccc2CC3N(C)CCC45C3C=CC(O)C5Oc1c24` | `CCOc1ccc2c3c1O[C@@H]1[C@@]43CCN([C@H](C2)[C@@H]4C=C[C@@H]1O)C` |
| LSA | inchikey | key_from_own_smiles | `GENAHGKEFJLNJB-UHFFFAOYSA-N` | `GENAHGKEFJLNJB-QMTHXVAHSA-N` |
| Meclonazepam | inchikey | key_from_own_smiles | `LMUVYJCAFWGNSY-UHFFFAOYSA-N` | `LMUVYJCAFWGNSY-VIFPVBQESA-N` |
| Nicomorphine | smiles | smiles_regains_stereo | `O=C(OC1C=CC2C3Cc4ccc(OC(=O)c5cccnc5)c5OC1C2(CCN3C)c45)c1cccnc1` | `CN1CC[C@]23[C@@H]4[C@H]1CC5=C2C(=C(C=C5)OC(=O)C6=CN=CC=C6)O[C@H]3[C@H](C=C4)OC(=O)C7=CN=CC=C7` |
| Nitemazepam | smiles | freebase_replaces_salt | `O=N(=O)c1ccc2N(C)C(=O)C(O)N=C(c3ccccc3)c2c1.[H+]` | `CN1C2=C(C=C(C=C2)[N+](=O)[O-])C(=NC(C1=O)O)C3=CC=CC=C3` |
| Nitemazepam | inchikey | freebase_replaces_salt | `QRWVNMAJJIQCEG-UHFFFAOYSA-O` | `QRWVNMAJJIQCEG-UHFFFAOYSA-N` |
| Nitemazepam | formula | freebase_replaces_salt | `` | `` |
| Thiopropamine | smiles | freebase_replaces_salt | `[Cl-].CC(N)Cc1cccs1.[H+]` | `CC(CC1=CC=CS1)N` |
| Thiopropamine | inchikey | freebase_replaces_salt | `MJRDCJBNRNAXIK-UHFFFAOYSA-N` | `NYVQQTOGYLBBDQ-UHFFFAOYSA-N` |
| Thiopropamine | formula | freebase_replaces_salt | `` | `` |
| Desomorphine | smiles | smiles_regains_stereo | `CN1CCC23C4CCCC3C1Cc1ccc(O)c(O4)c12` | `CN1CC[C@@]23[C@@H]4[C@H]1Cc1c3c(O[C@H]2CCC4)c(cc1)O` |

## Dose gates

7 row(s) deleted by `pipeline/build/dose_gates.py`; the rows are in `data/snapshots/dose-gate-report.md`.

## Per-source coverage

| Source | Dose ranges | Bindings | Categories | Tags |
|---|---|---|---|---|
| piru-curated | 220 | 442 | 649 | 2,264 |
| peer-review-primary | 0 | 1,006 | 0 | 1,582 |
| drug.community | 839 | 0 | 0 | 125 |
| psychonautwiki | 374 | 0 | 63 | 316 |
| tripsit | 580 | 0 | 411 | 1,266 |
| dailymed | 0 | 0 | 0 | 0 |
| erowid-pihkal | 103 | 0 | 167 | 426 |
| erowid-tihkal | 35 | 0 | 48 | 121 |
| pdsp | 0 | 0 | 0 | 0 |
| pubchem | 0 | 0 | 0 | 0 |
| wikidata | 0 | 0 | 94 | 338 |
| dea-orange-book | 0 | 0 | 0 | 0 |
| pyrls | 0 | 0 | 100 | 612 |
| medtap | 0 | 0 | 0 | 0 |
| benzos-cited | 0 | 0 | 0 | 0 |
| nps-datahub | 0 | 0 | 0 | 0 |
| freeodwiki | 320 | 0 | 28 | 0 |
| dosewiki | 294 | 12 | 0 | 0 |