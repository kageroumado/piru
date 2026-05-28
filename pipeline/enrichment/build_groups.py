#!/usr/bin/env python3
"""Partition the Piru bundled substance list into mechanism-class groups
for the enrichment agent swarm. One JSON file per group is written to
data/enrichment/groups/, listing the substance names that group's
agent is responsible for researching.
"""

import json
import re
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BUNDLED = REPO / "data/intermediate/substances-bundled.json"
DC = REPO / "data/sources/drug-community.json"
OUT = REPO / "data/enrichment/groups"


# --- Group routing ---------------------------------------------------------

# Each group is (slug, human-readable name). Order in PATTERNS matters:
# first match wins. Tag-based matches are tried before name-based.

GROUPS = {
    "serotonergic-tryptamines-and-lsd":     "Serotonergic psychedelics — tryptamines and LSD/ergolines",
    "serotonergic-phenethylamine-psychedelics": "Serotonergic psychedelics — 2C-x, DOx, mescaline, NBOMe",
    "mdma-and-entactogens":                 "MDMA family and entactogens",
    "stimulants-amphetamines":              "Amphetamines and monoamine releasers",
    "stimulants-cathinones":                "Cathinones (β-keto stimulants)",
    "stimulants-dat-inhibitors":            "DAT inhibitors (cocaine analogues, RTI/WIN, modafinil family, methylphenidate)",
    "arylcyclohexylamines":                 "Arylcyclohexylamines (ketamine and PCP families)",
    "other-dissociatives":                  "Other dissociatives (DXM, memantine, diarylethylamines, N2O)",
    "dysdelics-and-kor-ligands":            "Dysdelics and κ-opioid ligands (salvinorin family)",
    "classical-opioids":                    "Classical opioids (medical and kratom)",
    "designer-opioids":                     "Designer opioids (fentanyl analogues, nitazenes, brorphine, U-series)",
    "benzos-and-z-drugs":                   "Benzodiazepines (classical + designer) and Z-drugs",
    "gaba-depressants-other":               "Other GABAergic depressants (alcohol, GHB, gabapentinoids, barbiturates)",
    "cannabinoids":                         "Cannabinoids (natural + synthetic)",
    "ampakines-and-racetams":               "AMPAkines and racetams",
    "nootropics-other":                     "Other nootropics (peptides, cholinergics, novel mechanisms)",
    "prescription-psychiatrics":            "Prescription psychiatrics (SSRIs/SNRIs/TCAs/MAOIs, antipsychotics, mood stabilisers)",
    "deliriants-anticholinergics":          "Anticholinergic deliriants",
    "uncategorised-other":                  "Uncategorised — needs class-assignment pass",
}


def slugify(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def normalise(s: str) -> str:
    return re.sub(r"\s+", " ", s.lower().strip())


def route_substance(entry: dict) -> str:
    """Assign a substance to a group. Returns slug."""
    name = normalise(entry.get("name", ""))
    aliases = [normalise(a) for a in (entry.get("aliases") or [])]
    all_names = [name] + aliases
    tags = set(entry.get("tags") or [])
    category = entry.get("category", "")
    chemical_class = normalise(entry.get("chemical_class", "") or "")

    def has_name(*patterns) -> bool:
        for p in patterns:
            p = normalise(p)
            for n in all_names:
                if p in n:
                    return True
        return False

    # 1. Salvinorin / KOR — must check before opioid routing
    if "salvinorin" in tags or "kappa-opioid-agonist" in tags or category == "Dysdelic":
        return "dysdelics-and-kor-ligands"
    if has_name("salvinorin", "herkinorin", "u-50488", "u-69593", "u-50,488"):
        return "dysdelics-and-kor-ligands"

    # 2. Designer opioids — nitazenes, fentanyls, U-series, brorphine
    if "nitazene" in tags or "fentanyl-stronger" in tags or "benzimidazole-opioid" in tags:
        return "designer-opioids"
    if has_name("nitazene", "fentanyl", "carfentanil", "sufentanil", "alfentanil",
                "remifentanil", "lofentanil", "ocfentanil", "acetylfentanyl",
                "furanylfentanyl", "butyrfentanyl", "cyclopropylfentanyl",
                "valerylfentanyl", "methoxyacetylfentanyl", "isobutyrfentanyl",
                "u-47700", "u-49900", "u-48800", "u-50488", "brorphine",
                "ah-7921", "mt-45"):
        return "designer-opioids"
    if has_name("isotonitazene", "metonitazene", "protonitazene", "etonitazene",
                "etodesnitazene", "metodesnitazene", "butonitazene", "flunitazene",
                "pyrrolidino"):
        if any("nitazene" in n or "etazene" in n for n in all_names):
            return "designer-opioids"

    # 3. Classical opioids
    if category == "Opioid":
        return "classical-opioids"
    if "mu-opioid-agonist" in tags and category != "Antidepressant":
        return "classical-opioids"
    if has_name("morphine", "oxycodone", "hydromorphone", "hydrocodone", "codeine",
                "tramadol", "tapentadol", "methadone", "buprenorphine", "naloxone",
                "naltrexone", "nalmefene", "nalbuphine", "butorphanol",
                "mitragynine", "7-oh-mitragynine", "kratom",
                "loperamide", "diphenoxylate", "heroin", "diamorphine",
                "etorphine", "dihydrocodeine", "dihydromorphine", "oxymorphone",
                "levorphanol", "dextropropoxyphene", "propoxyphene", "pentazocine",
                "tilidine", "thebaine", "papaverine"):
        return "classical-opioids"

    # 4. Arylcyclohexylamines + PCP family (dissociatives — narrow)
    if "arylcyclohexylamine" in tags or "PCP-analog" in tags:
        return "arylcyclohexylamines"
    if has_name("ketamine", "esketamine", "arketamine", "norketamine",
                "deschloroketamine", "dck", "2-f-dck", "2-fl-dck", "2-br-dck",
                "2-cl-dck", "tiletamine", "o-pce", "o-pcm", "o-pcpr", "o-pcipr",
                "o-pca", "o-pcal", "o-pccp", "o-pcetoh", "eticyclidone",
                "methoxetamine", "mxe", "mxm", "mxpr", "mxipr", "dmxe", "dmxm",
                "fxe", "hxe", "fluorexetamine", "hydroxetamine",
                "pcp", "phencyclidine", "3-meo-pcp", "3-meo-pce", "3-ho-pcp",
                "3-f-pcp", "btcp", "rolicyclidine", "tcp", "tenocyclidine",
                "ethylketamine", "propylketamine", "cyclopropylketamine",
                "cyclobutylketamine", "allylketamine", "methylketamine"):
        return "arylcyclohexylamines"

    # 5. Other dissociatives
    if "NMDA-antagonist" in tags and category == "Dissociative":
        return "other-dissociatives"
    if "diarylethylamine" in tags:
        return "other-dissociatives"
    if has_name("dextromethorphan", "dxm", "memantine", "amantadine",
                "methoxphenidine", "mxp", "diphenidine", "ephenidine",
                "fluorolintane", "nitrous oxide", "n2o", "xenon",
                "dizocilpine", "mk-801", "mk801", "ketobemidone",
                "ibogaine", "noribogaine"):
        return "other-dissociatives"

    # 6. Cathinones (β-keto stimulants)
    if "cathinone" in tags or "pyrrolidinophenone" in tags:
        return "stimulants-cathinones"
    if has_name("mephedrone", "methylone", "ethylone", "butylone",
                "pentylone", "dibutylone", "eutylone", "mdpv", "α-pvp",
                "alpha-pvp", "alpha-pihp", "alpha-php", "α-php", "α-pihp",
                "naphyrone", "buphedrone", "pentedrone", "hexedrone",
                "methcathinone", "cathinone", "ephylone",
                "4-mmc", "3-mmc", "2-mmc", "4-cmc", "3-cmc", "2-cmc",
                "4-mec", "3-mec", "4-emc", "3-fmc", "4-fmc", "2-fmc",
                "flephedrone", "clephedrone", "mdpbp", "mdppp", "mppp",
                "n-ethylcathinone"):
        return "stimulants-cathinones"

    # 7. Eugeroics / afinils / DAT inhibitors
    if category == "Eugeroic" or "afinil" in tags or "eugeroic" in tags:
        return "stimulants-dat-inhibitors"
    if has_name("modafinil", "armodafinil", "adrafinil", "fladrafinil",
                "flmodafinil", "fluorenol", "hydrafinil", "bisfluoromodafinil",
                "lauflumide", "crl-40", "solriamfetol",
                "cocaine", "rti-55", "rti-150", "rti-113", "rti-133",
                "win-35428", "win 35428", "wins-35428",
                "mazindol", "indatraline", "tropoxane", "amfonelic acid",
                "jjc8-088", "jjc-8-088", "jjc8", "ahn-1055", "ahn 1-055",
                "sep-225289", "sori-20041", "jnj-7925476", "jhw-007",
                "brasofensine", "tametraline", "lr-5182", "lr-1111",
                "dasotraline", "indriline", "indanorex", "ce-123",
                "phenmetrazine", "phendimetrazine",
                "methylphenidate", "dexmethylphenidate", "ethylphenidate",
                "isopropylphenidate", "propylphenidate", "4-fluoro-methylphenidate",
                "4f-mph", "4-meo-mph", "naphyridate",
                "lisdexamfetamine", "vyvanse", "atomoxetine", "viloxazine",
                "bupropion", "amineptine", "nomifensine",
                "pridefine", "pridefin", "lefetamine"):
        return "stimulants-dat-inhibitors"

    # 8. Amphetamines + releasers (not entactogens, not cathinones)
    if has_name("amphetamine", "methamphetamine", "dextroamphetamine",
                "levoamphetamine", "amfetamine", "n-methylamphetamine",
                "4-fa", "4-fma", "2-fa", "2-fma", "3-fma", "3-fa",
                "4-fluoroamphetamine", "4-fluoromethamphetamine",
                "para-methylamphetamine", "pma", "pmma", "4-mta",
                "4-methylamphetamine", "4-mar", "aminorex",
                "pemoline", "fenethylline", "fencamine",
                "phenethylamine", "n-methylphenethylamine", "tyramine",
                "selegiline", "rasagiline",  # MAOIs but stimulant-effect
                "ephedrine", "pseudoephedrine", "synephrine",
                "norephedrine", "cathine", "1,3-dimethylamylamine",
                "dmaa", "octodrine", "phenylpropanolamine",
                "fenfluramine", "norfenfluramine", "chlorphentermine",
                "phentermine", "diethylpropion", "benzphetamine",
                "mephentermine", "methylphenethylamine",
                "1-phenylpropylamine", "alpha-ethylphenethylamine"):
        # MDMA and family go to entactogens — but a search for "methamphetamine" matches "methylenedioxymethamphetamine"; guard
        if has_name("methylenedioxy", "mdma", "mda", "mde", "mdoh", "mdpr",
                    "mbdb", "bdb", "ethylone", "methylone"):
            pass  # fall through to entactogen
        else:
            return "stimulants-amphetamines"

    # 9. MDMA / entactogens
    if category == "Empathogen" or "empathogen-adjacent" in tags or "MDMA-analog" in tags:
        return "mdma-and-entactogens"
    if has_name("mdma", "mda", "mde", "mdoh", "mdpr", "mbdb", "bdb",
                "methylenedioxy", "5-apb", "6-apb", "5-apdb", "6-apdb",
                "5-mapb", "6-mapb", "5-eapb", "6-eapb",
                "4-mta", "para-methoxyamphetamine", "ariadne"):
        return "mdma-and-entactogens"

    # 10. NBOMe / NBOH / NBF — phenethylamine psychedelics
    if "NBOMe" in tags or "NBOH" in tags or "NBF" in tags or "NBMD" in tags:
        return "serotonergic-phenethylamine-psychedelics"
    if has_name("nbome", "nboh", "nbf", "nbmd", "25i", "25c", "25b",
                "25e", "25h", "25n", "25t-2", "25t-7", "25d", "25g", "25p"):
        return "serotonergic-phenethylamine-psychedelics"

    # 11. 2C-x and DOx
    if "2C-x" in tags or "DOx" in tags:
        return "serotonergic-phenethylamine-psychedelics"
    if re.search(r"\b2c-[a-z0-9]", name) or re.search(r"\bdo[a-z]\b", name):
        return "serotonergic-phenethylamine-psychedelics"
    if has_name("dom", "doi", "dob", "doc", "don", "doef", "doet", "dopr",
                "doam", "dotfm", "tma-2", "tma-6", "mem", "mmda",
                "lophophine", "flea", "psi-", "ψ-"):
        return "serotonergic-phenethylamine-psychedelics"

    # 12. Mescaline analogues
    if has_name("mescaline", "escaline", "proscaline", "isoproscaline",
                "allylescaline", "methallylescaline", "buscaline",
                "homomescaline", "methylenedioxymescaline"):
        return "serotonergic-phenethylamine-psychedelics"

    # 13. LSD and ergolines
    if "ergot-derivative" in tags:
        return "serotonergic-tryptamines-and-lsd"
    if has_name("lsd", "lsa", "al-lad", "ald-52", "eth-lad", "lsz",
                "1p-lsd", "1cp-lsd", "1b-lsd", "pro-lad",
                "ergometrine", "ergotamine", "ergocristine",
                "lysergic acid", "lysergamide", "methylergometrine",
                "methysergide", "bromocriptine", "cabergoline", "pergolide"):
        return "serotonergic-tryptamines-and-lsd"

    # 14. Tryptamines
    if "tryptamine" in tags or "tryptamine-halogen" in tags or "TIHKAL" in tags:
        return "serotonergic-tryptamines-and-lsd"
    if has_name("dmt", "5-meo-dmt", "5-meo-mipt", "5-meo-dalt", "5-meo-dipt",
                "5-meo-amt", "5-meo-dpt", "5-meo-det",
                "4-ho-dmt", "psilocin", "psilocybin", "4-aco-dmt", "4-aco-met",
                "4-aco-mipt", "4-aco-det", "4-aco-dpt", "4-aco-dipt",
                "4-ho-met", "4-ho-mipt", "4-ho-det", "4-ho-dpt", "4-ho-dipt",
                "4-meo-dmt", "4-meo-mipt", "4f-dmt", "4f-5-meo-dmt",
                "4-cl-dmt", "4-br-dmt", "5-br-dmt", "5-f-dmt", "6-f-dmt",
                "7-cl-dmt", "amt", "α-mt", "alpha-mt", "α-et", "alpha-et",
                "det", "dpt", "dipt", "mipt", "miprt",
                "harmine", "harmaline", "harmalol", "tetrahydroharmine",
                "ayahuasca", "yopo", "bufotenine", "bufotenin",
                "ibogamine", "tabernanthine", "ndma-tryptamine"):
        return "serotonergic-tryptamines-and-lsd"

    # 15. Benzodiazepines / Z-drugs
    if (category == "Benzodiazepine" or "benzodiazepine" in tags
            or "designer-benzo" in tags or "thienodiazepine" in tags
            or "triazolobenzodiazepine" in tags):
        return "benzos-and-z-drugs"
    if has_name("alprazolam", "diazepam", "clonazepam", "lorazepam",
                "midazolam", "triazolam", "temazepam", "oxazepam",
                "flurazepam", "estazolam", "chlordiazepoxide", "bromazepam",
                "etizolam", "deschloroetizolam", "clonazolam", "flubromazolam",
                "bromazolam", "flualprazolam", "diclazepam", "norflurazepam",
                "flubromazepam", "phenazepam", "3-hydroxyphenazepam",
                "adinazolam", "nifoxipam", "pyrazolam", "nitrazolam",
                "zolpidem", "zopiclone", "eszopiclone", "zaleplon",
                "remimazolam", "metizolam"):
        return "benzos-and-z-drugs"

    # 16. Other GABAergic depressants
    if (category == "GABAergic" or category == "Depressant"
            or "GABAA-PAM" in tags or "GABA-B-agonist" in tags
            or "GABA-A-NAM" in tags):
        return "gaba-depressants-other"
    if has_name("alcohol", "ethanol", "ghb", "gbl", "1,4-butanediol",
                "gabapentin", "pregabalin", "phenibut", "baclofen",
                "f-phenibut", "picamilon", "pyrazinoylguanidine",
                "valnoctamide", "phenobarbital", "secobarbital",
                "amobarbital", "pentobarbital", "thiopental",
                "barbital", "mephobarbital", "butabarbital",
                "meprobamate", "carisoprodol", "methaqualone", "etaqualone",
                "glutethimide", "methyprylon", "chloral hydrate",
                "paraldehyde", "ramelteon", "tasimelteon", "agomelatine"):
        return "gaba-depressants-other"

    # 17. Cannabinoids
    if category == "Cannabinoid" or "synthetic-cannabinoid" in tags or "aminoalkylindole" in tags:
        return "cannabinoids"
    if has_name("thc", "tetrahydrocannabinol", "delta-8", "delta-9", "delta-10",
                "thcv", "thcp", "thco", "thch", "cbd", "cbn", "cbg", "cbc",
                "cannabidiol", "cannabinol", "cannabichromene", "cannabigerol",
                "cannabidivarin", "cbdv", "hhc", "hhcp", "hu-210", "hu-308",
                "jwh-", "am-2201", "am-694", "am-1248", "am-1220",
                "adb-", "mdmb-", "5f-", "cumyl-", "fubinaca",
                "anandamide", "2-ag", "palmitoylethanolamide", "pea-cannabinoid",
                "yohimbine"):  # NOTE yohimbine is α2-antagonist; will check
        if "yohimbine" not in name:
            return "cannabinoids"

    # 18. AMPAkines + racetams
    if category == "AMPAkine" or "racetam" in tags or "ampakine" in tags or "AMPA-PAM" in tags:
        return "ampakines-and-racetams"
    if has_name("idra-21", "cx-516", "cx-546", "cx-614", "cx-691",
                "cx-717", "cx-1739", "cx-1942",
                "ly-404187", "ly-451646", "ly-503430", "org 26576",
                "pepa", "s-18986", "sunifiram", "dm-235", "unifiram", "dm-232",
                "piracetam", "aniracetam", "oxiracetam", "pramiracetam",
                "phenylpiracetam", "phenotropil", "coluracetam", "fasoracetam",
                "nefiracetam", "brivaracetam", "levetiracetam", "seletracetam",
                "rolziracetam", "nebracetam", "imuracetam", "dimiracetam",
                "etiracetam"):
        return "ampakines-and-racetams"

    # 19. Other nootropics
    if category == "Nootropic":
        return "nootropics-other"
    if has_name("semax", "selank", "nsi-189", "noopept", "alpha-gpc",
                "huperzine", "tianeptine", "j-147", "p21", "bpc-157",
                "bromantane", "methylene blue", "centrophenoxine", "meclofenoxate",
                "dmae", "vinpocetine", "hydergine", "idebenone", "sulbutiamine",
                "9-me-bc", "agmatine", "cerebrolysin", "cytisine", "varenicline",
                "ispronicline", "evp-6124", "encenicline",
                "tropisetron", "prl-8-53", "abt-418", "abt-126",
                "polygala", "rg3487", "rg-3487"):
        return "nootropics-other"

    # 20. Prescription psychiatrics
    if category in ("Antidepressant", "Antipsychotic"):
        return "prescription-psychiatrics"
    if has_name("sertraline", "fluoxetine", "paroxetine", "citalopram",
                "escitalopram", "fluvoxamine", "venlafaxine", "duloxetine",
                "desvenlafaxine", "milnacipran", "levomilnacipran",
                "amitriptyline", "nortriptyline", "imipramine", "clomipramine",
                "desipramine", "doxepin", "trimipramine", "protriptyline",
                "phenelzine", "tranylcypromine", "isocarboxazid",
                "moclobemide", "selegiline", "rasagiline",
                "mirtazapine", "mianserin", "trazodone", "nefazodone",
                "vortioxetine", "vilazodone", "bupropion", "tianeptine",
                "haloperidol", "chlorpromazine", "fluphenazine", "thiothixene",
                "loxapine", "perphenazine", "thioridazine",
                "risperidone", "olanzapine", "quetiapine", "aripiprazole",
                "clozapine", "ziprasidone", "lurasidone", "paliperidone",
                "asenapine", "iloperidone", "brexpiprazole", "cariprazine",
                "lithium", "lamotrigine", "valproate", "divalproex",
                "carbamazepine", "oxcarbazepine", "topiramate"):
        return "prescription-psychiatrics"

    # 21. Anticholinergic deliriants
    if category == "Antihistamine" or "AChE-inhibitor" in tags:
        return "deliriants-anticholinergics"
    if has_name("diphenhydramine", "doxylamine", "dimenhydrinate",
                "scopolamine", "atropine", "hyoscyamine", "hyoscine",
                "datura", "henbane", "mandragora", "deadly nightshade",
                "belladonna", "benztropine", "trihexyphenidyl", "biperiden",
                "promethazine", "chlorpheniramine", "hydroxyzine",
                "cyclizine", "meclizine", "buclizine"):
        return "deliriants-anticholinergics"

    # If we got here, slot to uncategorised
    return "uncategorised-other"


def main() -> int:
    OUT.mkdir(exist_ok=True)
    substances: list[dict] = []
    if BUNDLED.exists():
        substances.extend(json.loads(BUNDLED.read_text()))
    if DC.exists():
        for entry in json.loads(DC.read_text()):
            name_field = entry.get("drug_name", "")
            if "(" in name_field and name_field.endswith(")"):
                name, parens = name_field.split("(", 1)
                name = name.strip()
                inner = parens.rstrip(")")
                aliases = [a.strip() for a in inner.split(",") if a.strip()]
            else:
                name = name_field
                aliases = []
            alts = entry.get("alternative_names") or []
            aliases = list({a for a in aliases + alts if a and a.lower() != name.lower()})
            substances.append({
                "name": name,
                "aliases": aliases,
                "category": entry.get("psychoactive_class") or "",
                "tags": [],
                "chemical_class": entry.get("chemical_class") or "",
                "_source": "drug.community",
            })

    # Dedup by normalised name
    seen: set[str] = set()
    unique: list[dict] = []
    for s in substances:
        key = normalise(s.get("name", ""))
        if not key or key in seen:
            continue
        seen.add(key)
        unique.append(s)

    by_group: dict[str, list[dict]] = defaultdict(list)
    for s in unique:
        slug = route_substance(s)
        by_group[slug].append({
            "name": s.get("name"),
            "aliases": s.get("aliases", []),
            "category": s.get("category", ""),
            "tags": s.get("tags", []),
            "chemical_class": s.get("chemical_class", ""),
        })

    summary: list[dict] = []
    for slug, name in GROUPS.items():
        items = by_group.get(slug, [])
        items.sort(key=lambda x: x["name"].lower())
        out_path = OUT / f"{slug}.json"
        out_path.write_text(json.dumps({
            "slug": slug,
            "name": name,
            "count": len(items),
            "substances": items,
        }, indent=2, ensure_ascii=False))
        summary.append({"slug": slug, "name": name, "count": len(items)})

    # Print summary to stderr
    print(f"Partitioned {len(unique)} substances into {len(GROUPS)} groups:", file=sys.stderr)
    total_routed = 0
    for s in summary:
        print(f"  {s['count']:4d}  {s['slug']}  ({s['name']})", file=sys.stderr)
        total_routed += s['count']
    print(f"Total routed: {total_routed}", file=sys.stderr)
    print(f"Group files: {OUT}/", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
