import Foundation

struct SourceInfo {
    let name: String
    let url: String
    let detail: String
    let description: String
}

enum AppSources {
    static let all: [SourceInfo] = [
        SourceInfo(
            name: "TripSit",
            url: "https://tripsit.me",
            detail: "tripsit.me",
            description: "Harm reduction community providing factsheets on psychoactive substances, including dosage ranges, duration, interactions, and safety information.",
        ),
        SourceInfo(
            name: "OpenFDA",
            url: "https://open.fda.gov",
            detail: "open.fda.gov — FDA Drug Labels API",
            description: "U.S. Food and Drug Administration open data API providing drug labeling information, pharmacologic classes, routes of administration, and brand/generic names.",
        ),
        SourceInfo(
            name: "PsychonautWiki",
            url: "https://psychonautwiki.org",
            detail: "psychonautwiki.org",
            description: "Community-driven encyclopedia of psychoactive substances providing dosage, duration, pharmacology, subjective effects, and harm reduction information.",
        ),
        SourceInfo(
            name: "DrugBank",
            url: "https://go.drugbank.com",
            detail: "go.drugbank.com",
            description: "Comprehensive pharmaceutical knowledge base combining detailed drug data with drug target information. Used for pharmacokinetic parameters and drug properties.",
        ),
        SourceInfo(
            name: "PubMed",
            url: "https://pubmed.ncbi.nlm.nih.gov",
            detail: "pubmed.ncbi.nlm.nih.gov",
            description: "Biomedical literature database maintained by the National Library of Medicine, providing access to peer-reviewed research articles and clinical studies.",
        ),
        SourceInfo(
            name: "PiHKAL",
            url: "https://isomerdesign.com/PiHKAL/PiHKAL/",
            detail: "Phenethylamines I Have Known and Loved — Shulgin & Shulgin (1991)",
            description: "Pharmacological reference text by Alexander and Ann Shulgin documenting the synthesis, dosage, duration, and qualitative effects of phenethylamine compounds.",
        ),
        SourceInfo(
            name: "TiHKAL",
            url: "https://isomerdesign.com/PiHKAL/TiHKAL/",
            detail: "Tryptamines I Have Known and Loved — Shulgin & Shulgin (1997)",
            description: "Pharmacological reference text by Alexander and Ann Shulgin documenting the synthesis, dosage, duration, and qualitative effects of tryptamine compounds.",
        ),
        SourceInfo(
            name: "DailyMed",
            url: "https://dailymed.nlm.nih.gov",
            detail: "dailymed.nlm.nih.gov — NLM/FDA Drug Label Database",
            description: "Official FDA drug labeling database maintained by the National Library of Medicine, containing approved product labeling (package inserts) for prescription and OTC drugs.",
        ),
        SourceInfo(
            name: "EMCDDA",
            url: "https://www.emcdda.europa.eu",
            detail: "European Monitoring Centre for Drugs and Drug Addiction",
            description: "EU agency providing risk assessments and pharmacological profiles of new psychoactive substances (NPS) and novel research chemicals.",
        ),
        SourceInfo(
            name: "WHO",
            url: "https://www.who.int/teams/health-product-and-policy-standards/medicines-selection-and-ip",
            detail: "WHO Expert Committee on Drug Dependence",
            description: "World Health Organization critical reviews and assessments of psychoactive substances, including pharmacological evaluations and scheduling recommendations.",
        ),
    ]

    static func info(for name: String) -> SourceInfo? {
        all.first { $0.name == name }
    }

    static func substanceURL(for source: String, substance: String) -> URL? {
        switch source {
        case "PsychonautWiki":
            let slug = substance.replacingOccurrences(of: " ", with: "_")
            return URL(string: "https://psychonautwiki.org/wiki/\(slug)")
        case "TripSit":
            let slug = substance.lowercased()
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? substance.lowercased()
            return URL(string: "https://drugs.tripsit.me/\(slug)")
        case "DailyMed":
            let query = substance
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? substance
            return URL(string: "https://dailymed.nlm.nih.gov/dailymed/search.cfm?labeltype=all&query=\(query)")
        case "PubMed":
            let query = substance
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? substance
            return URL(string: "https://pubmed.ncbi.nlm.nih.gov/?term=\(query)+pharmacology")
        case "EMCDDA":
            let query = substance
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? substance
            return URL(string: "https://www.emcdda.europa.eu/publications/drug-profiles_en?search=\(query)")
        default:
            guard let sourceInfo = info(for: source),
                  !sourceInfo.url.isEmpty else { return nil }
            return URL(string: sourceInfo.url)
        }
    }
}
