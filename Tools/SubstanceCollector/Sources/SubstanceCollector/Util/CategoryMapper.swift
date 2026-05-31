import Foundation

/// Maps arbitrary source category strings (TripSit, PsychonautWiki, Wikidata
/// drug-class P5642 values, PubChem MeSH terms) to the iOS
/// `SubstanceCategory` raw value (the *display* form, e.g. "Stimulant").
///
/// The new cases — `eugeroic`, `ampakine`, `dysdelic` — are handled by
/// name-specific overrides in `overrideForName(_:)` so we don't pollute them
/// with TripSit's generic `stimulant`/`other` labels.
enum CategoryMapper {
    /// Source label → SubstanceCategory raw value.
    private static let table: [String: String] = [
        "stimulant": "Stimulant", "stimulants": "Stimulant",
        "psychedelic": "Psychedelic", "psychedelics": "Psychedelic",
        "hallucinogen": "Psychedelic", "hallucinogens": "Psychedelic",
        "dissociative": "Dissociative", "dissociatives": "Dissociative",
        "dysdelic": "Dysdelic", "kappa-agonist": "Dysdelic",
        "kappa-opioid-agonist": "Dysdelic", "salvinorin": "Dysdelic",
        "opioid": "Opioid", "opioids": "Opioid",
        "opiate": "Opioid", "opiates": "Opioid",
        "depressant": "Depressant", "depressants": "Depressant",
        "sedative": "Depressant", "sedatives": "Depressant",
        "barbiturate": "Depressant", "barbiturates": "Depressant",
        "anxiolytic": "Depressant", "hypnotic": "Depressant",
        "benzodiazepine": "Benzodiazepine", "benzodiazepines": "Benzodiazepine",
        "designer benzodiazepine": "Benzodiazepine",
        "gabapentinoid": "GABAergic", "gabaergic": "GABAergic",
        "empathogen": "Empathogen", "entactogen": "Empathogen",
        "empathogens": "Empathogen", "entactogens": "Empathogen",
        "cannabinoid": "Cannabinoid", "cannabinoids": "Cannabinoid",
        "synthetic cannabinoid": "Cannabinoid",
        "nootropic": "Nootropic", "nootropics": "Nootropic",
        "racetam": "Nootropic", "ampakine": "AMPAkine",
        "ampa-pam": "AMPAkine", "ampa-positive-modulator": "AMPAkine",
        "eugeroic": "Eugeroic", "afinil": "Eugeroic",
        "wake-promoting": "Eugeroic",
        "antidepressant": "Antidepressant", "antidepressants": "Antidepressant",
        "ssri": "Antidepressant", "snri": "Antidepressant",
        "maoi": "Antidepressant", "rima": "Antidepressant",
        "anticonvulsant": "Antidepressant", "mood-stabilizer": "Antidepressant",
        "antipsychotic": "Antipsychotic", "antipsychotics": "Antipsychotic",
        "neuroleptic": "Antipsychotic",
        "antihistamine": "Antihistamine", "deliriant": "Antihistamine",
        "deliriants": "Antihistamine",
        "analgesic": "Analgesic", "analgesics": "Analgesic", "nsaid": "Analgesic",
        "cardiovascular": "Cardiovascular",
        "antimicrobial": "Antimicrobial", "antibiotic": "Antimicrobial",
        "antifungal": "Antimicrobial", "antiviral": "Antimicrobial",
        "gastrointestinal": "Gastrointestinal",
        "respiratory": "Respiratory",
        "endocrine": "Endocrine",
        "immunological": "Immunological",
        "supplement": "Supplement", "vitamin": "Supplement",
        "steroid": "Supplement",
    ]

    /// Modifier labels that should NOT collapse a substance into "Other";
    /// kept for tag extraction.
    static let modifierLabels: Set<String> = [
        "tentative", "research-chemical", "habit-forming", "common",
        "inactive", "vendor-only", "investigational", "no-human-data",
    ]

    /// Priority order — when multiple substantive categories are present,
    /// pick the highest-priority one. This roughly matches what users care
    /// about when scanning a long list.
    private static let priority: [String] = [
        "Opioid", "Benzodiazepine", "Dissociative", "Dysdelic",
        "Empathogen", "Psychedelic", "AMPAkine", "Eugeroic",
        "Stimulant", "Cannabinoid", "GABAergic", "Depressant",
        "Antidepressant", "Antipsychotic", "Nootropic",
        "Supplement", "Antihistamine", "Analgesic",
        "Cardiovascular", "Antimicrobial", "Gastrointestinal",
        "Respiratory", "Endocrine", "Immunological", "Other",
    ]

    /// Map a list of raw labels to a single category. Name override takes
    /// precedence (so e.g. modafinil is `Eugeroic` even if TripSit calls it
    /// "stimulant").
    static func map(labels: [String], name: String) -> String {
        if let override = overrideForName(name) { return override }

        let mapped: [String] = labels.compactMap {
            table[$0.lowercased().trimmingCharacters(in: .whitespaces)]
        }
        if mapped.isEmpty { return "Other" }

        for p in priority where mapped.contains(p) {
            return p
        }
        return mapped.first ?? "Other"
    }

    /// Compounds where source-label classification is unreliable.
    /// Keys are normalized names (`NameNormalizer.normalize`).
    private static let nameOverrides: [String: String] = {
        var t: [String: String] = [:]
        // Eugeroics — TripSit/Wikidata call most of these "stimulant" or
        // "wakefulness-promoting"; the iOS UI wants them in their own bin.
        for n in [
            "modafinil", "armodafinil", "adrafinil", "fluorenol",
            "fladrafinil", "flmodafinil", "hydrafinil",
            "9meBC", "9-me-bc", "9mebc",
        ] {
            t[NameNormalizer.normalize(n)] = "Eugeroic"
        }
        // AMPAkines
        for n in [
            "idra-21", "idra21", "sunifiram", "unifiram", "pepa",
            "org 26576", "org26576", "cx-516", "cx516", "cx-546",
            "cx546", "cx-614", "cx614", "cx-691", "cx691",
            "cx-717", "cx717", "ly-451646", "ly451646", "ly-503430",
            "ly503430", "ly-404187", "ly404187", "ampalex",
        ] {
            t[NameNormalizer.normalize(n)] = "AMPAkine"
        }
        // Dysdelics — kappa-opioid agonists & salvinorin family
        for n in [
            "salvinorin a", "salvinorin b", "salvinorin c",
            "divinatorin a", "divinatorin b", "divinatorin c",
            "herkinorin", "mesyl salvinorin b", "mesyl sal b",
            "symbms", "symbmst", "22-thiocyanatosalvinorin",
            "22-thiocyanatosalvinorin a", "salvia divinorum",
            "ibogaine", "ibogamine", "noribogaine",
        ] {
            t[NameNormalizer.normalize(n)] = "Dysdelic"
        }
        return t
    }()

    static func overrideForName(_ name: String) -> String? {
        nameOverrides[NameNormalizer.normalize(name)]
    }
}
