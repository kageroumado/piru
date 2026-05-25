import Foundation

/// Centralized tag inference. Inspects compound name, drug-class strings, and
/// chemical structure hints (SMILES/InChIKey when available) to attach
/// mechanism/family/provenance/status tags from a controlled vocabulary.
///
/// The same compound often picks up multiple tags (e.g. 4-MeO-PCP gets
/// `arylcyclohexylamine`, `NMDA-antagonist`, `dissociative`,
/// `research-chemical`). The `category` field captures the primary clinical
/// classification; `tags` capture everything orthogonal to that.
enum Tagger {
    /// Suffix/substring → tags. Order matters only for human readability;
    /// final list is deduplicated.
    private static let nameRules: [(String, [String])] = [
        // Chemical families
        ("nbome", ["NBOMe", "phenethylamine", "5-HT2A-agonist", "research-chemical"]),
        ("nboh", ["NBOH", "phenethylamine", "5-HT2A-agonist", "research-chemical"]),
        ("nbf", ["NBF", "phenethylamine", "5-HT2A-agonist", "research-chemical"]),
        ("nbmd", ["NBMD", "phenethylamine", "research-chemical"]),
        ("2c-", ["2C-x", "phenethylamine", "5-HT2A-agonist"]),
        ("dox", ["DOx", "phenethylamine", "5-HT2A-agonist"]),
        ("doi", ["DOx", "phenethylamine", "5-HT2A-agonist", "radioligand-origin"]),
        ("dom", ["DOx", "phenethylamine", "5-HT2A-agonist"]),
        ("dob", ["DOx", "phenethylamine", "5-HT2A-agonist"]),
        ("doc", ["DOx", "phenethylamine", "5-HT2A-agonist"]),
        ("amphetamine", ["phenethylamine", "DRI", "NDRI", "TAAR1"]),
        ("cathinone", ["cathinone", "DRI"]),
        ("pyrovalerone", ["pyrrolidinophenone", "DRI"]),
        ("pvp", ["pyrrolidinophenone", "DRI"]),
        ("mdpv", ["pyrrolidinophenone", "DRI"]),
        ("tryptamine", ["tryptamine"]),
        ("dipt", ["tryptamine", "5-HT2A-agonist"]),
        ("dmt", ["tryptamine", "5-HT2A-agonist"]),
        ("racetam", ["racetam", "nootropic"]),
        ("piracetam", ["racetam", "nootropic"]),
        ("ampakine", ["ampakine", "AMPA-PAM"]),
        ("salvinorin", ["salvinorin", "kappa-opioid-agonist"]),
        ("nitazene", ["nitazene", "mu-opioid-agonist", "research-chemical"]),
        ("etonitazene", ["nitazene", "mu-opioid-agonist", "research-chemical"]),
        ("isotonitazene", ["nitazene", "mu-opioid-agonist", "research-chemical"]),
        ("metonitazene", ["nitazene", "mu-opioid-agonist", "research-chemical"]),
        ("protonitazene", ["nitazene", "mu-opioid-agonist", "research-chemical"]),
        ("clonitazene", ["nitazene", "mu-opioid-agonist", "research-chemical"]),
        ("fentanyl", ["mu-opioid-agonist"]),
        ("fentanil", ["mu-opioid-agonist"]),
        ("carfentanil", ["mu-opioid-agonist"]),
        ("sufentanil", ["mu-opioid-agonist"]),
        ("alfentanil", ["mu-opioid-agonist"]),
        ("remifentanil", ["mu-opioid-agonist"]),
        ("acetylfentanyl", ["mu-opioid-agonist", "research-chemical"]),
        ("furanylfentanyl", ["mu-opioid-agonist", "research-chemical"]),
        ("u-47700", ["mu-opioid-agonist", "research-chemical"]),
        ("u-48800", ["mu-opioid-agonist", "research-chemical"]),
        ("u-50488", ["kappa-opioid-agonist", "research-chemical"]),
        ("azepam", ["benzodiazepine", "GABAA-PAM"]),
        ("azolam", ["benzodiazepine", "GABAA-PAM"]),
        ("azenil", ["benzodiazepine", "GABAA-PAM"]),
        ("zolpidem", ["GABAA-PAM"]),
        ("zopiclone", ["GABAA-PAM"]),
        ("zaleplon", ["GABAA-PAM"]),
        // Arylcyclohexylamines / dissociatives
        ("pcp", ["arylcyclohexylamine", "NMDA-antagonist", "sigma-1"]),
        ("ketamine", ["arylcyclohexylamine", "NMDA-antagonist"]),
        ("methoxetamine", ["arylcyclohexylamine", "NMDA-antagonist", "research-chemical"]),
        ("mxe", ["arylcyclohexylamine", "NMDA-antagonist", "research-chemical"]),
        ("dck", ["arylcyclohexylamine", "NMDA-antagonist", "research-chemical"]),
        ("dcm", ["arylcyclohexylamine", "NMDA-antagonist", "research-chemical"]),
        ("o-pce", ["arylcyclohexylamine", "NMDA-antagonist", "research-chemical"]),
        ("3-meo-pcp", ["arylcyclohexylamine", "NMDA-antagonist", "research-chemical"]),
        ("4-meo-pcp", ["arylcyclohexylamine", "NMDA-antagonist", "research-chemical"]),
        ("diphenidine", ["diarylethylamine", "NMDA-antagonist", "research-chemical"]),
        ("ephenidine", ["diarylethylamine", "NMDA-antagonist", "research-chemical"]),
        ("mxp", ["diarylethylamine", "NMDA-antagonist", "research-chemical"]),
        // Eugeroics
        ("modafinil", ["DAT-inhibitor", "eugeroic"]),
        ("adrafinil", ["eugeroic", "prodrug"]),
        ("armodafinil", ["DAT-inhibitor", "eugeroic"]),
        // Empathogens / SRAs
        ("mdma", ["SNDRI", "phenethylamine"]),
        ("mda", ["SNDRI", "phenethylamine"]),
        ("mdai", ["SRI"]),
        // SSRIs/SNRIs
        ("fluoxetine", ["SRI"]),
        ("sertraline", ["SRI"]),
        ("citalopram", ["SRI"]),
        ("escitalopram", ["SRI"]),
        ("paroxetine", ["SRI"]),
        ("venlafaxine", ["SNRI"]),
        ("duloxetine", ["SNRI"]),
        // MAOIs
        ("moclobemide", ["MAOI-A", "RIMA"]),
        ("phenelzine", ["MAOI-A", "MAOI-B"]),
        ("tranylcypromine", ["MAOI-A", "MAOI-B"]),
        ("selegiline", ["MAOI-B"]),
        // Cannabinoids
        ("jwh-", ["synthetic-cannabinoid", "research-chemical"]),
        ("am-", ["synthetic-cannabinoid", "research-chemical"]),
        ("ab-", ["synthetic-cannabinoid", "research-chemical"]),
        ("adb-", ["synthetic-cannabinoid", "research-chemical"]),
        ("mdmb-", ["synthetic-cannabinoid", "research-chemical"]),
        ("5f-", ["synthetic-cannabinoid", "research-chemical"]),
        ("4f-", ["synthetic-cannabinoid", "research-chemical"]),
    ]

    /// Wikidata drug-class P5642 label → tag(s).
    private static let wikidataClassRules: [(String, [String])] = [
        ("nbome", ["NBOMe", "5-HT2A-agonist"]),
        ("phenethylamine", ["phenethylamine"]),
        ("substituted phenethylamine", ["phenethylamine"]),
        ("tryptamine", ["tryptamine"]),
        ("substituted tryptamine", ["tryptamine"]),
        ("substituted amphetamine", ["phenethylamine"]),
        ("cathinone", ["cathinone"]),
        ("substituted cathinone", ["cathinone"]),
        ("arylcyclohexylamine", ["arylcyclohexylamine", "NMDA-antagonist"]),
        ("benzodiazepine", ["benzodiazepine", "GABAA-PAM"]),
        ("designer benzodiazepine", ["benzodiazepine", "GABAA-PAM", "research-chemical"]),
        ("synthetic cannabinoid", ["synthetic-cannabinoid", "research-chemical"]),
        ("synthetic opioid", ["research-chemical"]),
        ("nitazene", ["nitazene", "mu-opioid-agonist"]),
        ("fentanyl analogue", ["mu-opioid-agonist", "research-chemical"]),
        ("piperazine", ["piperazine"]),
        ("racetam", ["racetam", "nootropic"]),
        ("ampakine", ["ampakine", "AMPA-PAM"]),
        ("eugeroic", ["eugeroic"]),
        ("kappa opioid agonist", ["kappa-opioid-agonist"]),
        ("mu opioid agonist", ["mu-opioid-agonist"]),
        ("serotonin–norepinephrine reuptake inhibitor", ["SNRI"]),
        ("selective serotonin reuptake inhibitor", ["SRI"]),
        ("monoamine oxidase inhibitor", ["MAOI-A"]),
        ("nmda receptor antagonist", ["NMDA-antagonist"]),
        ("designer drug", ["research-chemical"]),
        ("psychedelic", []),
        ("dissociative", []),
        ("stimulant", []),
        ("depressant", []),
    ]

    /// Apply name-based and source-class-based rules.
    static func tags(for name: String, sourceClasses: [String] = []) -> [String] {
        var out = Set<String>()
        let lower = name.lowercased()
        for (needle, tags) in nameRules where lower.contains(needle) {
            tags.forEach { out.insert($0) }
        }
        for cls in sourceClasses {
            let c = cls.lowercased()
            for (needle, tags) in wikidataClassRules where c.contains(needle) {
                tags.forEach { out.insert($0) }
            }
        }
        return Array(out).sorted()
    }

    /// Merge tag lists, preserving sort order.
    static func merge(_ lists: [String]...) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for list in lists {
            for tag in list where !seen.contains(tag) {
                seen.insert(tag)
                out.append(tag)
            }
        }
        return out.sorted()
    }
}
