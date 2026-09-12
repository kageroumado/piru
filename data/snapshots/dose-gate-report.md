# Dose gate report

Rows the build deleted because they fail a rule about themselves — a class ceiling from `data/curated/dose-class-gates.json`, or a phase too short for its route. Each is a row to report upstream; each rule is in `pipeline/build/dose_gates.py`.

7 row(s) deleted.

## absorption floor · phase under 1 min on an absorbed route

| substance | source | route | detail |
|---|---|---|---|
| Methamphetamine | freeodwiki | oral | comeup 0.0833333–0.166667 min |
| Nicotine | freeodwiki | oral | comeup 0.0833333–0.166667 min |

## class ceiling · benzimidazole-nitazenes ≤ 2 mg

| substance | source | route | detail |
|---|---|---|---|
| Clonitazene | tripsit | oral | strong_upper 15 mg — 6 tier(s) above the ceiling; etonitazene is ~1,000× morphine and the weakest nitazenes in circulation are still morphine-range per milligram (EMCDDA nitazene risk assessments), so a tier above 2 mg is not a dose |

## class ceiling · fentanyl-anilidopiperidines ≤ 2 mg

| substance | source | route | detail |
|---|---|---|---|
| Acetylfentanyl | dosewiki | insufflation | strong_upper 20 mg — 6 tier(s) above the ceiling; fentanyl is dosed in tens of micrograms and no anilidopiperidine in human use is more than ~100× weaker (PMID 40721041 ranks six analogs within a decade of fentanyl in vivo); a tier above 2 mg is a milligram written for a microgram |
| Acetylfentanyl | dosewiki | oral | strong_upper 7 mg — 6 tier(s) above the ceiling; fentanyl is dosed in tens of micrograms and no anilidopiperidine in human use is more than ~100× weaker (PMID 40721041 ranks six analogs within a decade of fentanyl in vivo); a tier above 2 mg is a milligram written for a microgram |
| Acetylfentanyl | dosewiki | sublingual | strong_upper 20 mg — 6 tier(s) above the ceiling; fentanyl is dosed in tens of micrograms and no anilidopiperidine in human use is more than ~100× weaker (PMID 40721041 ranks six analogs within a decade of fentanyl in vivo); a tier above 2 mg is a milligram written for a microgram |
| Valerylfentanyl | tripsit | oral | light_lower 50 mg — 2 tier(s) above the ceiling; fentanyl is dosed in tens of micrograms and no anilidopiperidine in human use is more than ~100× weaker (PMID 40721041 ranks six analogs within a decade of fentanyl in vivo); a tier above 2 mg is a milligram written for a microgram |
