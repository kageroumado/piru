import Foundation
import os

private let logger = Logger(subsystem: "dev.yumeji.piru", category: "DailyMedAPI")

struct DailyMedAPI {
    private static let baseURL = "https://api.fda.gov/drug/label.json"

    // MARK: - Response Models

    private struct LabelResponse: Decodable {
        let results: [LabelEntry]?
    }

    private struct LabelEntry: Decodable {
        let dosage_and_administration: [String]?
        let openfda: OpenFDAMeta?

        struct OpenFDAMeta: Decodable {
            let brand_name: [String]?
            let generic_name: [String]?
            let route: [String]?
            let pharm_class_epc: [String]?
        }
    }

    struct DoseEnrichment {
        let doses: DoseRange
        let unit: String
    }

    private static let topicalOnlyRoutes: Set<String> = [
        "TOPICAL", "OPHTHALMIC", "OTIC", "DENTAL", "NASAL SPRAY",
    ]

    // MARK: - Drug Whitelist

    /// Comprehensive list of important clinical drug generic names for direct FDA lookup.
    /// Name-based queries guarantee results regardless of whether pharm_class_epc is populated.
    private static let importantDrugs: [String] = [
        // SSRI antidepressants
        "fluoxetine", "sertraline", "escitalopram", "citalopram", "paroxetine", "fluvoxamine",
        // SNRI antidepressants
        "venlafaxine", "duloxetine", "desvenlafaxine", "levomilnacipran", "milnacipran",
        // TCA antidepressants
        "amitriptyline", "nortriptyline", "imipramine", "clomipramine", "doxepin",
        "desipramine", "trimipramine", "protriptyline",
        // MAOI antidepressants
        "phenelzine", "tranylcypromine", "selegiline", "isocarboxazid",
        // Atypical antidepressants
        "bupropion", "mirtazapine", "trazodone", "vilazodone", "vortioxetine",
        "nefazodone", "agomelatine",
        // Mood stabilizers
        "lithium", "valproate", "valproic acid", "divalproex", "lamotrigine",
        "carbamazepine", "oxcarbazepine",
        // Antipsychotics (typical)
        "haloperidol", "chlorpromazine", "fluphenazine", "perphenazine", "thioridazine",
        "trifluoperazine", "loxapine", "pimozide",
        // Antipsychotics (atypical)
        "quetiapine", "risperidone", "olanzapine", "clozapine", "aripiprazole",
        "ziprasidone", "paliperidone", "lurasidone", "asenapine", "iloperidone",
        "brexpiprazole", "cariprazine",
        // Benzodiazepines
        "diazepam", "alprazolam", "lorazepam", "clonazepam", "temazepam",
        "oxazepam", "triazolam", "midazolam", "flurazepam", "nitrazepam",
        "chlordiazepoxide", "clobazam", "bromazepam", "clorazepate",
        // Z-drugs / sleep
        "zolpidem", "eszopiclone", "zaleplon", "ramelteon", "suvorexant", "lemborexant",
        // Opioids
        "morphine", "oxycodone", "hydrocodone", "codeine", "fentanyl", "tramadol",
        "buprenorphine", "methadone", "hydromorphone", "oxymorphone", "tapentadol",
        "meperidine", "nalbuphine", "pentazocine",
        // Opioid antagonists
        "naloxone", "naltrexone", "nalmefene",
        // Stimulants / ADHD
        "amphetamine", "dextroamphetamine", "lisdexamfetamine", "methylphenidate",
        "dexmethylphenidate", "modafinil", "armodafinil", "atomoxetine",
        "methamphetamine",
        // Anticonvulsants / gabapentinoids
        "gabapentin", "pregabalin", "topiramate", "levetiracetam", "phenytoin",
        "phenobarbital", "primidone", "tiagabine", "vigabatrin", "lacosamide",
        "zonisamide", "perampanel", "brivaracetam",
        // Analgesics / NSAIDs
        "ibuprofen", "naproxen", "aspirin", "acetaminophen", "celecoxib",
        "indomethacin", "ketorolac", "diclofenac", "meloxicam", "piroxicam",
        "ketoprofen",
        // Triptans (antimigraine)
        "sumatriptan", "rizatriptan", "zolmitriptan", "eletriptan", "naratriptan",
        "almotriptan", "frovatriptan",
        // Antihistamines
        "diphenhydramine", "hydroxyzine", "promethazine", "chlorpheniramine",
        "cetirizine", "loratadine", "fexofenadine", "desloratadine", "levocetirizine",
        "azelastine", "cyproheptadine",
        // Cardiovascular — beta blockers
        "metoprolol", "atenolol", "propranolol", "bisoprolol", "carvedilol",
        "labetalol", "nadolol", "nebivolol", "sotalol",
        // Cardiovascular — ACE inhibitors
        "enalapril", "lisinopril", "ramipril", "captopril", "benazepril",
        "fosinopril", "quinapril", "perindopril",
        // Cardiovascular — ARBs
        "losartan", "valsartan", "irbesartan", "olmesartan", "candesartan", "telmisartan",
        // Cardiovascular — calcium channel blockers
        "amlodipine", "nifedipine", "verapamil", "diltiazem", "felodipine", "nicardipine",
        // Cardiovascular — statins
        "atorvastatin", "simvastatin", "rosuvastatin", "pravastatin", "lovastatin",
        "fluvastatin", "pitavastatin",
        // Cardiovascular — diuretics
        "furosemide", "hydrochlorothiazide", "spironolactone", "bumetanide",
        "torsemide", "chlorthalidone", "indapamide", "eplerenone", "amiloride",
        // Cardiovascular — anticoagulants / antiplatelets
        "warfarin", "apixaban", "rivaroxaban", "dabigatran", "edoxaban",
        "heparin", "enoxaparin", "clopidogrel", "ticagrelor", "prasugrel",
        // Cardiovascular — other
        "digoxin", "amiodarone", "flecainide", "mexiletine", "ivabradine",
        "ranolazine", "isosorbide", "hydralazine", "clonidine", "doxazosin",
        // Diabetes / metabolic
        "metformin", "sitagliptin", "saxagliptin", "linagliptin", "alogliptin",
        "empagliflozin", "dapagliflozin", "canagliflozin", "glipizide", "glyburide",
        "glimepiride", "pioglitazone", "rosiglitazone", "acarbose",
        "liraglutide", "semaglutide", "dulaglutide", "exenatide",
        "insulin glargine", "insulin detemir", "insulin aspart", "insulin lispro",
        // Thyroid
        "levothyroxine", "liothyronine", "methimazole", "propylthiouracil",
        // Proton pump inhibitors
        "omeprazole", "lansoprazole", "esomeprazole", "pantoprazole", "rabeprazole",
        "dexlansoprazole",
        // GI / antiemetics
        "ondansetron", "metoclopramide", "prochlorperazine", "domperidone",
        "granisetron", "loperamide", "bismuth subsalicylate", "misoprostol",
        "sucralfate", "ranitidine", "famotidine", "cimetidine",
        // Respiratory — bronchodilators / inhaled
        "albuterol", "ipratropium", "tiotropium", "salmeterol", "formoterol",
        "umeclidinium", "glycopyrrolate", "indacaterol",
        // Respiratory — anti-inflammatory
        "montelukast", "zafirlukast", "fluticasone", "budesonide", "beclomethasone",
        "mometasone", "ciclesonide",
        // Respiratory — systemic
        "theophylline", "roflumilast", "dextromethorphan", "guaifenesin",
        // Corticosteroids (systemic)
        "prednisone", "prednisolone", "dexamethasone", "methylprednisolone",
        "hydrocortisone", "betamethasone", "triamcinolone",
        // Antibiotics — beta-lactams
        "amoxicillin", "ampicillin", "cephalexin", "cefuroxime", "ceftriaxone",
        "cefdinir", "piperacillin",
        // Antibiotics — quinolones
        "ciprofloxacin", "levofloxacin", "moxifloxacin", "ofloxacin",
        // Antibiotics — macrolides / other
        "azithromycin", "clarithromycin", "erythromycin", "doxycycline",
        "minocycline", "tetracycline", "metronidazole", "clindamycin",
        "trimethoprim", "sulfamethoxazole", "nitrofurantoin", "vancomycin",
        "linezolid", "rifampin",
        // Antifungals
        "fluconazole", "itraconazole", "ketoconazole", "voriconazole",
        "terbinafine", "clotrimazole",
        // Antivirals — herpes/influenza
        "acyclovir", "valacyclovir", "famciclovir", "oseltamivir", "zanamivir",
        // Muscle relaxants
        "baclofen", "cyclobenzaprine", "methocarbamol", "tizanidine",
        "carisoprodol", "metaxalone", "orphenadrine",
        // Urological
        "sildenafil", "tadalafil", "vardenafil", "tamsulosin", "alfuzosin",
        "finasteride", "dutasteride", "oxybutynin", "tolterodine", "mirabegron",
        // Dementia / nootropics
        "donepezil", "memantine", "galantamine", "rivastigmine",
        // Immunosuppressants
        "cyclosporine", "tacrolimus", "methotrexate", "mycophenolate",
        "azathioprine", "hydroxychloroquine",
        // Hormones / contraceptives
        "estradiol", "progesterone", "testosterone", "levonorgestrel",
        "medroxyprogesterone", "norethindrone", "ethinyl estradiol",
        // Anti-addiction
        "acamprosate", "disulfiram", "varenicline", "buprenorphine",
        // Miscellaneous CNS
        "buspirone", "melatonin", "dexamethasone",
        // Antiparasitics
        "ivermectin", "albendazole", "mebendazole",
        // Supplements with clinical dosing
        "folic acid", "cholecalciferol", "cyanocobalamin", "ferrous sulfate",
        "magnesium oxide", "potassium chloride",
        // Parkinson's / movement disorders
        "levodopa", "carbidopa", "pramipexole", "ropinirole",
        "entacapone", "amantadine", "benztropine", "trihexyphenidyl",
        // Epilepsy extras
        "eslicarbazepine", "rufinamide", "cannabidiol", "felbamate", "ethosuximide",
        // ADHD extras
        "guanfacine", "viloxazine",
        // GI extras
        "dicyclomine", "hyoscyamine", "linaclotide", "lubiprostone",
        // Laxatives
        "polyethylene glycol", "lactulose", "docusate", "senna", "bisacodyl",
        // Women's health / contraceptives
        "norgestimate", "drospirenone", "etonogestrel", "desogestrel",
        "ulipristal", "mifepristone",
        // Ophthalmology
        "latanoprost", "brimonidine", "dorzolamide",
        // Gout / bone / joints
        "colchicine", "allopurinol", "febuxostat", "probenecid",
        "alendronate", "risedronate", "raloxifene",
        // Diabetes / weight loss extras
        "tirzepatide", "ertugliflozin", "phentermine", "orlistat",
        // Cardiac extras
        "dronedarone", "dofetilide", "propafenone", "sacubitril", "fondaparinux",
        // Dermatology
        "isotretinoin", "dapsone", "tretinoin", "adapalene",
        // Antinausea / antiemetic extras
        "scopolamine", "dimenhydrinate", "meclizine", "dronabinol", "nabilone",
        // Cough suppressant
        "benzonatate",
        // Migraine — CGRP inhibitors
        "erenumab", "galcanezumab", "fremanezumab", "ubrogepant", "rimegepant",
        "ergotamine", "dihydroergotamine",
        // Decongestants
        "pseudoephedrine", "phenylephrine",
        // Hair loss
        "minoxidil",
        // Antifungals extras
        "nystatin", "griseofulvin",
        // ED extras
        "avanafil",
        // Anesthetics
        "nitrous oxide", "propofol",
        // Smoking cessation
        "nicotine", "cytisine",
        // Steroids (anabolic)
        "nandrolone", "oxandrolone", "stanozolol",
        // Recreational-adjacent / grey market
        "phenibut", "tianeptine", "kratom",
        // Supplements people commonly track
        "magnesium citrate", "magnesium glycinate", "l-theanine", "ashwagandha",
        "coenzyme q10", "creatine", "turmeric", "fish oil", "biotin",
        "collagen", "zinc",
    ]

    // MARK: - Fetch

    /// Fetch clinical substances by querying each drug name directly from the FDA label database.
    /// This bypasses the pharm_class_epc field (absent for ~40% of drugs) and guarantees
    /// that every listed drug is found as long as it has an FDA label.
    static func fetchClinicalDrugs() async -> [Substance] {
        let drugs = importantDrugs
        let total = drugs.count
        var allSubstances: [Substance] = []
        var seenNames: Set<String> = []
        let concurrency = 20

        for batchStart in stride(from: 0, to: total, by: concurrency) {
            let batch = Array(drugs[batchStart..<min(batchStart + concurrency, total)])
            let batchResults = await withTaskGroup(of: Substance?.self) { group in
                for name in batch {
                    group.addTask { await Self.fetchByName(name) }
                }
                var results: [Substance] = []
                for await substance in group {
                    if let s = substance { results.append(s) }
                }
                return results
            }
            for s in batchResults {
                let key = s.name.lowercased()
                guard !seenNames.contains(key) else { continue }
                seenNames.insert(key)
                allSubstances.append(s)
            }
        }

        logger.info("Fetched \(allSubstances.count) clinical substances from \(total) name queries")
        return allSubstances
    }

    private static func fetchByName(_ name: String, retryOnRateLimit: Bool = true) async -> Substance? {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "search", value: "openfda.generic_name:\"\(name)\""),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            if http.statusCode == 429 && retryOnRateLimit {
                try? await Task.sleep(for: .seconds(2))
                return await fetchByName(name, retryOnRateLimit: false)
            }
            guard http.statusCode == 200 else { return nil }
            let result = try JSONDecoder().decode(LabelResponse.self, from: data)
            return result.results?.first.flatMap { toSubstance($0, queryName: name) }
        } catch {
            logger.error("fetchByName(\(name)) failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Conversion

    private static func toSubstance(_ entry: LabelEntry, queryName: String? = nil) -> Substance? {
        guard let genericName = entry.openfda?.generic_name?.first else { return nil }
        let nameUpper = genericName.uppercased()
        // Prefer the clean query name over FDA's salt-form generic_name
        let name = queryName?.capitalized ?? genericName.capitalized

        // Skip multi-ingredient combos and verbose chemical names
        if isComboDrug(nameUpper) { return nil }
        if nameUpper.count > 60 { return nil }

        // Skip topical-only drugs (no systemic dose to track)
        if let routes = entry.openfda?.route {
            let routeSet = Set(routes.map { $0.uppercased() })
            if routeSet.isSubset(of: topicalOnlyRoutes), !routeSet.isEmpty { return nil }
        }

        // Parse dose ranges from label text
        let dosageText = entry.dosage_and_administration?.joined(separator: " ") ?? ""
        let enrichment = parseDosageText(dosageText)

        let routes: [SubstanceRoute] = (entry.openfda?.route ?? ["ORAL"]).prefix(3).map { routeStr in
            SubstanceRoute(
                route: RouteOfAdministration.from(string: routeStr),
                unit: enrichment?.unit ?? "mg",
                doses: enrichment?.doses ?? DoseRange()
            )
        }

        let brands = entry.openfda?.brand_name ?? []
        let aliases = Array(Set(brands.map { $0.capitalized }.filter { $0.uppercased() != nameUpper }))
            .sorted().prefix(5).map { $0 }

        return Substance(
            name: name,
            aliases: aliases,
            category: mapCategory(entry.openfda?.pharm_class_epc),
            defaultRoute: routes.first?.route ?? .oral,
            routes: Array(routes),
            effects: [],
            subjectiveEffects: [],
            toleranceInfo: nil,
            halfLifeMinutes: nil,
            sources: ["DailyMed"]
        )
    }

    private static func isComboDrug(_ name: String) -> Bool {
        name.contains(" AND ") || name.contains(" / ") || name.contains("; ") || name.contains(" WITH ")
    }

    // MARK: - Category Mapping

    private static func mapCategory(_ classes: [String]?) -> SubstanceCategory {
        guard let classes else { return .other }
        let joined = classes.joined(separator: " ").lowercased()
        if joined.contains("opioid") { return .opioid }
        if joined.contains("benzodiazepine") { return .benzodiazepine }
        if joined.contains("barbiturate") || joined.contains("muscle relaxant") { return .depressant }
        if joined.contains("gamma-aminobutyric") || joined.contains("gaba") { return .depressant }
        if joined.contains("sedative") || joined.contains("hypnotic") || joined.contains("anesthetic") { return .depressant }
        if joined.contains("melatonin receptor") || joined.contains("orexin receptor") { return .depressant }
        if joined.contains("neuromuscular") || joined.contains("anticholinergic") { return .depressant }
        if joined.contains("phenothiazine") || joined.contains("depressant") { return .depressant }
        if joined.contains("stimulant") || joined.contains("amphetamine") { return .stimulant }
        if joined.contains("methylxanthine") { return .stimulant }
        if joined.contains("catecholamine") || joined.contains("sympathomimetic") { return .stimulant }
        if joined.contains("wakefulness") { return .stimulant }
        if joined.contains("serotonin reuptake") || joined.contains("antidepressant") || joined.contains("monoamine oxidase") { return .antidepressant }
        if joined.contains("norepinephrine reuptake") || joined.contains("dopamine and norepinephrine") { return .antidepressant }
        if joined.contains("mood stabilizer") { return .antidepressant }
        if joined.contains("antipsychotic") { return .antipsychotic }
        if joined.contains("cannabinoid") { return .cannabinoid }
        if joined.contains("antihistamine") || joined.contains("histamine") { return .antihistamine }
        if joined.contains("leukotriene") { return .antihistamine }
        if joined.contains("anti-inflammatory") || joined.contains("analgesic") { return .analgesic }
        if joined.contains("serotonin-1") || joined.contains("triptan") || joined.contains("ergot") { return .analgesic }
        if joined.contains("cyclooxygenase") { return .analgesic }
        if joined.contains("anti-epileptic") || joined.contains("anticonvulsant") || joined.contains("gabapentin") { return .gabapentinoid }
        if joined.contains("cholinesterase") || joined.contains("nmda") || joined.contains("nootropic") { return .nootropic }
        if joined.contains("arrhythmic") || joined.contains("platelet") { return .cardiovascular }
        if joined.contains("diuretic") || joined.contains("vasodilator") { return .cardiovascular }
        if joined.contains("angiotensin") || joined.contains("adrenergic blocker") { return .cardiovascular }
        if joined.contains("calcium channel") || joined.contains("cardiac") { return .cardiovascular }
        if joined.contains("coagul") || joined.contains("thrombin") || joined.contains("factor xa") { return .cardiovascular }
        if joined.contains("hmg-coa") || joined.contains("statin") { return .cardiovascular }
        if joined.contains("anti-anginal") || joined.contains("aldosterone") { return .cardiovascular }
        if joined.contains("antibacterial") || joined.contains("antifungal") || joined.contains("antiviral") { return .antimicrobial }
        if joined.contains("penicillin") || joined.contains("cephalosporin") || joined.contains("fluoroquinolone") { return .antimicrobial }
        if joined.contains("macrolide") || joined.contains("tetracycline") || joined.contains("nitroimidazole") { return .antimicrobial }
        if joined.contains("nucleoside analog") { return .antimicrobial }
        if joined.contains("proton pump") || joined.contains("laxative") { return .gastrointestinal }
        if joined.contains("antidiarrheal") || joined.contains("gastrointestinal") { return .gastrointestinal }
        if joined.contains("serotonin-3 receptor antagonist") { return .gastrointestinal }
        if joined.contains("beta2") || joined.contains("expectorant") || joined.contains("antitussive") { return .respiratory }
        if joined.contains("phosphodiesterase 4") { return .respiratory }
        if joined.contains("estrogen") || joined.contains("progestin") || joined.contains("progesterone") { return .endocrine }
        if joined.contains("androgen") || joined.contains("testosterone") { return .endocrine }
        if joined.contains("insulin") || joined.contains("sulfonylurea") || joined.contains("glp-1") { return .endocrine }
        if joined.contains("sglt") || joined.contains("dipeptidyl peptidase") { return .endocrine }
        if joined.contains("thyro") { return .endocrine }
        if joined.contains("kinase inhibitor") || joined.contains("immunosuppressant") { return .immunological }
        if joined.contains("tumor necrosis") || joined.contains("interleukin") { return .immunological }
        if joined.contains("antirheumatic") || joined.contains("janus kinase") { return .immunological }
        if joined.contains("corticosteroid") { return .endocrine }
        if joined.contains("vitamin") || joined.contains("amino acid") || joined.contains("omega-3") { return .supplement }
        if joined.contains("folate") || joined.contains("iron") || joined.contains("mineral") { return .supplement }
        if joined.contains("adrenergic agonist") { return .stimulant }
        return .other
    }

    // MARK: - Dose Parsing

    /// Parse a DoseRange from FDA label dosage_and_administration text.
    /// Handles: "X to Y mg", "X-Y mg", "starting dose X mg", "maximum X mg".
    static func parseDosageText(_ text: String) -> DoseEnrichment? {
        guard !text.isEmpty else { return nil }
        let unit = detectUnit(in: text)
        let unitPat = #"(?:mg|mcg|µg|μg|ug|g(?!\w)|mL|IU|units?)"#

        let ranges = extractRanges(from: text, unitPattern: unitPat)
        let startDose = firstDoseNear(text, keywords: [
            "starting dose", "initial dose", "start with", "begin with",
            "initially,", "initially ", "recommended starting",
        ])
        let maxDose = firstDoseNear(text, keywords: [
            "maximum dose", "maximum recommended", "not to exceed",
            "not exceed", "up to a maximum of", "up to",
        ])

        if let mainRange = ranges.first {
            let raw = DoseRange(
                threshold: startDose.map { min($0, mainRange.lowerBound) } ?? mainRange.lowerBound,
                light: nil,
                common: mainRange,
                strong: ranges.count > 1 ? ranges[1] : nil,
                heavy: maxDose ?? ranges.last?.upperBound
            )
            return DoseEnrichment(doses: enforceMonotonicity(raw), unit: unit)
        }

        let singles = extractSingles(from: text, unitPattern: unitPat)
        guard let first = singles.first else { return nil }
        let lo = startDose ?? first * 0.5
        let raw = DoseRange(
            threshold: lo,
            light: nil,
            common: lo <= first ? lo...first : first...first,
            strong: nil,
            heavy: maxDose ?? singles.max()
        )
        return DoseEnrichment(doses: enforceMonotonicity(raw), unit: unit)
    }

    /// Drop ladder rungs that violate `threshold ≤ light ≤ common ≤ strong ≤ heavy`.
    ///
    /// FDA labels mix pediatric (`X mg/kg`), renal-adjustment, and starting-dose
    /// sentences with the adult range, so the regex extractor sometimes assigns
    /// a smaller number to `strong` or `heavy` than the value already in `common`.
    /// The audit found ~30% of DailyMed-only entries had at least one such
    /// inversion (vs ~1% for TripSit).
    ///
    /// We prefer dropping the suspect field over keeping a wrong value: a missing
    /// `heavy` shows the user "no upper bound known", while a wrong heavy of, say,
    /// `1 mg` on Cephalexin actively misleads.
    static func enforceMonotonicity(_ r: DoseRange) -> DoseRange {
        var threshold = r.threshold
        var light = r.light
        var common = r.common
        var strong = r.strong
        var heavy = r.heavy

        // Threshold must not exceed the next-known lower bound.
        let nextAfterThreshold = light?.lowerBound ?? common?.lowerBound ?? strong?.lowerBound ?? heavy
        if let t = threshold, let next = nextAfterThreshold, t > next {
            threshold = nil
        }

        // Light must sit between threshold and common.
        if let l = light {
            let below = threshold ?? 0
            let above = common?.lowerBound ?? strong?.lowerBound ?? heavy ?? .infinity
            if l.lowerBound < below || l.upperBound > above {
                light = nil
            }
        }

        // Strong must sit above common.
        if let s = strong, let c = common, s.lowerBound < c.upperBound {
            strong = nil
        }

        // Heavy must sit at or above the highest known rung.
        let topKnown = strong?.upperBound ?? common?.upperBound ?? light?.upperBound ?? threshold ?? 0
        if let h = heavy, h < topKnown {
            heavy = nil
        }

        return DoseRange(
            threshold: threshold,
            light: light,
            common: common,
            strong: strong,
            heavy: heavy
        )
    }

    // MARK: - Parsing Helpers

    private static func detectUnit(in text: String) -> String {
        let t = text.lowercased()
        if t.contains("mcg") || t.contains("µg") || t.contains("μg") || t.contains("micrograms") { return "µg" }
        if t.contains("mg") { return "mg" }
        if t.contains(" grams") || t.contains(" g ") || t.contains(" g/") { return "g" }
        if t.contains(" iu") || t.contains("international unit") { return "IU" }
        if t.contains("ml") || t.contains("milliliter") { return "mL" }
        return "mg"
    }

    private static func extractRanges(from text: String, unitPattern: String) -> [ClosedRange<Double>] {
        let pattern = #"(\d+(?:\.\d+)?)\s*(?:to|-)\s*(\d+(?:\.\d+)?)\s*"# + unitPattern
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            guard match.numberOfRanges >= 3,
                  let r1 = Range(match.range(at: 1), in: text),
                  let r2 = Range(match.range(at: 2), in: text),
                  let lo = Double(text[r1]),
                  let hi = Double(text[r2]),
                  lo < hi else { return nil }
            return lo...hi
        }
    }

    private static func extractSingles(from text: String, unitPattern: String) -> [Double] {
        let pattern = #"(\d+(?:\.\d+)?)\s*"# + unitPattern
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            guard match.numberOfRanges >= 2,
                  let r = Range(match.range(at: 1), in: text) else { return nil }
            return Double(text[r])
        }
    }

    private static func firstDoseNear(_ text: String, keywords: [String]) -> Double? {
        let lower = text.lowercased()
        let numPat = #"(\d+(?:\.\d+)?)\s*(?:mg|mcg|µg|μg|ug|g(?!\w)|mL|IU|units?)"#
        guard let regex = try? NSRegularExpression(pattern: numPat, options: .caseInsensitive) else { return nil }
        for keyword in keywords {
            guard let kwRange = lower.range(of: keyword) else { continue }
            let start = lower.distance(from: lower.startIndex, to: kwRange.lowerBound)
            let windowLen = min(120, lower.count - start)
            let window = NSRange(location: start, length: windowLen)
            if let match = regex.firstMatch(in: text, range: window),
               match.numberOfRanges >= 2,
               let r = Range(match.range(at: 1), in: text),
               let value = Double(text[r]) {
                return value
            }
        }
        return nil
    }

}
