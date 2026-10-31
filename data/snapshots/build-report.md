# Piru SQLite build report

Built 2026-10-31.7 → `Piru/Data/piru-substances.sqlite` (21,581,824 bytes, sha256 `a679995ecf9ca82c5062017e34cae3cbee7ab3023bd45722868a62aa17d6bf24`)

## Row counts

| Table | Rows |
|---|---|
| substances | 1,674 |
| aliases | 6,005 |
| sources | 18 |
| source_field_priority | 2 |
| citations | 2,725 |
| categories | 1,577 |
| tags | 7,059 |
| dose_ranges | 2,794 |
| durations | 10,736 |
| drug_community_timelines | 755 |
| half_lives | 710 |
| mechanisms_summary | 1,228 |
| effects | 2,952 |
| subjective_effects | 23,653 |
| subjective_effect_concepts | 506 |
| subjective_effect_concept_aliases | 1,178 |
| tolerance | 0 |
| diazepam_equivalents | 32 |
| bindings | 1,457 |
| functional_assays | 179 |
| biased_agonism | 23 |
| receptor_oligomers | 8 |
| downstream_signalling | 677 |
| neuroimaging | 52 |
| pk_routes | 433 |
| concentration_effects | 25 |
| metabolism | 560 |
| drug_interactions_pk | 205 |
| pharmacogenetics | 284 |
| off_targets | 209 |
| class_contexts | 50 |
| substance_classes | 680 |
| molecule_shapes | 962 |
| class_reference_compounds | 40 |
| class_representatives | 7 |
| substance_flags | 13 |
| regional_names | 5 |
| localized_names | 1,615 |
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
| food_effects | 15 |
| saturable_kinetics | 6 |
| bioavailability_by_dose | 10 |
| attenuation_bands | 1 |
| coded_products | 15,778 |
| product_codes | 103,206 |

## Identifier corrections

Identifier columns a source was allowed to overwrite because the stored row contradicted itself (`dosewiki_identity_corrections` in `pipeline/build/sqlite.py`).

| substance | column | rule | was | now |
|---|---|---|---|---|
| 1D-LSD | smiles | smiles_regains_stereo | `CCN(CC)C(=O)C1CN(C)C2Cc3cn(C(=O)C4(C)CCC4C)c4cccc(C2=C1)c34` | `CC1(C(CC1)C)C(=O)N1C=C2C[C@H]3N(C[C@@H](C=C3C=3C=CC=C1C32)C(=O)N(CC)CC)C` |
| 1P-LSD | inchikey | key_from_own_smiles | `JSMQOVGXBIDBIE-UHFFFAOYSA-N` | `JSMQOVGXBIDBIE-OXQOHEQNSA-N` |
| 4-EMC | inchikey | key_from_own_smiles | `FUYPDKFWOHBUFT-VIFPVBQESA-N` | `FUYPDKFWOHBUFT-UHFFFAOYSA-N` |
| Buprenorphine | smiles | smiles_regains_stereo | `COC12CCC3(CC1C(C)(O)C(C)(C)C)C1Cc4ccc(O)c5OC2C3(CCN1CC1CC1)c45` | `CO[C@]12CC[C@@]3(C[C@@H]1[C@](C)(O)C(C)(C)C)[C@H]1CC4=C5C(O[C@@H]2[C@@]35CCN1CC1CC1)=C(O)C=C4` |
| ETH-LAD | inchikey | key_from_own_smiles | `MYNOUXJLOHVSMQ-UHFFFAOYSA-N` | `MYNOUXJLOHVSMQ-DNVCBOLYSA-N` |
| 1P-ETH-LAD | smiles | smiles_regains_stereo | `CCN(CC)C(=O)C1CN(CC)C2Cc3cn(C(=O)CC)c4cccc(C2=C1)c34` | `CCN1C[C@@H](C=C2[C@H]1Cc1cn(c3c1c2ccc3)C(=O)CC)C(=O)N(CC)CC` |
| 3,4-CTMP | inchikey | key_from_own_smiles | `JUKMAYKVHWKRKY-CHWSQXEVSA-N` | `JUKMAYKVHWKRKY-UHFFFAOYSA-N` |
| Amfecloral | inchikey | key_from_own_smiles | `VBZDETYCYXPOAK-OVCLIPMQSA-N` | `VBZDETYCYXPOAK-UHFFFAOYSA-N` |
| Dextropropoxyphene | smiles | smiles_regains_stereo | `CCC(=O)OC(Cc1ccccc1)(C(C)CN(C)C)c1ccccc1` | `CCC(=O)O[C@@](CC1=CC=CC=C1)([C@H](C)CN(C)C)C1=CC=CC=C1` |
| Dihydrocodeine | smiles | smiles_regains_stereo | `COc1ccc2CC3N(C)CCC45C3CCC(O)C5Oc1c24` | `[H][C@@]12OC3=C4C(C[C@H]5N(C)CC[C@@]14[C@@]5([H])CC[C@@H]2O)=CC=C3OC` |
| Ethylmorphine | smiles | smiles_regains_stereo | `CCOc1ccc2CC3N(C)CCC45C3C=CC(O)C5Oc1c24` | `CCOc1ccc2c3c1O[C@@H]1[C@@]43CCN([C@H](C2)[C@@H]4C=C[C@@H]1O)C` |
| LSA | inchikey | key_from_own_smiles | `GENAHGKEFJLNJB-UHFFFAOYSA-N` | `GENAHGKEFJLNJB-QMTHXVAHSA-N` |
| Meclonazepam | inchikey | key_from_own_smiles | `LMUVYJCAFWGNSY-UHFFFAOYSA-N` | `LMUVYJCAFWGNSY-VIFPVBQESA-N` |
| Nicomorphine | smiles | smiles_regains_stereo | `O=C(OC1C=CC2C3Cc4ccc(OC(=O)c5cccnc5)c5OC1C2(CCN3C)c45)c1cccnc1` | `CN1CC[C@]23[C@@H]4[C@H]1CC5=C2C(=C(C=C5)OC(=O)C6=CN=CC=C6)O[C@H]3[C@H](C=C4)OC(=O)C7=CN=CC=C7` |
| Nitemazepam | smiles | freebase_replaces_salt | `O=N(=O)c1ccc2N(C)C(=O)C(O)N=C(c3ccccc3)c2c1.[H+]` | `CN1C2=C(C=C(C=C2)[N+](=O)[O-])C(=NC(C1=O)O)C3=CC=CC=C3` |
| Nitemazepam | inchikey | freebase_replaces_salt | `QRWVNMAJJIQCEG-UHFFFAOYSA-O` | `QRWVNMAJJIQCEG-UHFFFAOYSA-N` |
| Nitemazepam | formula | freebase_replaces_salt | `` | `` |
| Proscaline | inchikey | key_from_own_smiles | `HYWLMSUAZVDUFW-UHFFFAOYSA-O` | `HYWLMSUAZVDUFW-UHFFFAOYSA-N` |
| Thiopropamine | smiles | freebase_replaces_salt | `[Cl-].CC(N)Cc1cccs1.[H+]` | `CC(CC1=CC=CS1)N` |
| Thiopropamine | inchikey | freebase_replaces_salt | `MJRDCJBNRNAXIK-UHFFFAOYSA-N` | `NYVQQTOGYLBBDQ-UHFFFAOYSA-N` |
| Thiopropamine | formula | freebase_replaces_salt | `` | `` |
| Desomorphine | smiles | smiles_regains_stereo | `CN1CCC23C4CCCC3C1Cc1ccc(O)c(O4)c12` | `CN1CC[C@@]23[C@@H]4[C@H]1Cc1c3c(O[C@H]2CCC4)c(cc1)O` |

## Dose gates

100 row(s) deleted by `pipeline/build/dose_gates.py`; the rows are in `data/snapshots/dose-gate-report.md`.

## Row citations

535 row(s) cited from `data/curated/row-citations.json`; 0 entries not applied.

## Upstream values the build could not read

548 dose or duration value(s) refused, or read only in part; each is listed in `data/snapshots/unparsed-upstream.json` for reporting upstream (`pipeline/audit/upstream_report.py`).

| source | reason | values |
|---|---|---|
| dosewiki | dose_ranges_duplicate_dropped | 4 |
| dosewiki | dropped_regressed_tiers | 1 |
| dosewiki | dropped_unquantified_unit | 1 |
| dosewiki | duration_afterglow_implausible | 5 |
| dosewiki | duration_profile_contradictory | 2 |
| dosewiki | stage_unit_unknown_or_half_open | 11 |
| drug.community | degenerate_after_unreadable_tiers | 7 |
| drug.community | dose_ranges_duplicate_dropped | 12 |
| drug.community | dropped_ambiguous_unit | 3 |
| drug.community | dropped_regressed_tiers | 3 |
| drug.community | duration_afterglow_implausible | 3 |
| drug.community | duration_profile_contradictory | 7 |
| drug.community | extra_numbers_ignored | 14 |
| drug.community | foreign_characters | 5 |
| drug.community | no_activity_reported | 1 |
| drug.community | range_in_single_value_tier | 390 |
| drug.community | unparsed | 15 |
| freeodwiki | dropped_inverted_tiers | 7 |
| freeodwiki | dropped_regressed_tiers | 2 |
| freeodwiki | duration_afterglow_implausible | 5 |
| freeodwiki | duration_onset_impossible | 2 |
| freeodwiki | duration_profile_contradictory | 9 |
| piru-curated | dose_ranges_duplicate_dropped | 1 |
| piru-curated | dropped_regressed_tiers | 1 |
| psychonautwiki | dropped_inverted_tiers | 1 |
| psychonautwiki | dropped_regressed_tiers | 2 |
| psychonautwiki | duration_afterglow_implausible | 5 |
| psychonautwiki | duration_onset_impossible | 1 |
| psychonautwiki | duration_profile_contradictory | 6 |
| tripsit | dose_ranges_duplicate_dropped | 7 |
| tripsit | dropped_daily_unit | 1 |
| tripsit | dropped_inverted_tiers | 5 |
| tripsit | dropped_regressed_tiers | 4 |
| tripsit | dropped_unquantified_unit | 1 |
| tripsit | duration_afterglow_implausible | 3 |
| tripsit | duration_onset_impossible | 1 |

## Per-source coverage

| Source | Dose ranges | Bindings | Categories | Tags |
|---|---|---|---|---|
| piru-curated | 220 | 446 | 650 | 2,269 |
| peer-review-primary | 0 | 999 | 0 | 1,580 |
| dosewiki | 292 | 12 | 0 | 0 |
| drug.community | 826 | 0 | 0 | 126 |
| psychonautwiki | 376 | 0 | 63 | 316 |
| tripsit | 572 | 0 | 410 | 1,267 |
| dailymed | 0 | 0 | 0 | 0 |
| erowid-pihkal | 93 | 0 | 168 | 430 |
| erowid-tihkal | 37 | 0 | 47 | 119 |
| pdsp | 0 | 0 | 0 | 0 |
| pubchem | 0 | 0 | 0 | 0 |
| wikidata | 0 | 0 | 95 | 340 |
| dea-orange-book | 0 | 0 | 0 | 0 |
| pyrls | 0 | 0 | 99 | 612 |
| medtap | 0 | 0 | 0 | 0 |
| benzos-cited | 0 | 0 | 0 | 0 |
| nps-datahub | 0 | 0 | 0 | 0 |
| freeodwiki | 378 | 0 | 45 | 0 |